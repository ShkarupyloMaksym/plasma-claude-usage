#!/usr/bin/env python3
"""Claude plan usage for the Plasma widget: session (5-hour), weekly and any other limits.

Prints one JSON object:
  {"at": unix time, "source": "...", "age_seconds": n,
   "windows": {"five_hour": {"pct", "resets_at", "status", "label"?}, "seven_day": {...}, ...},
   "error"?: "..."}

Where the numbers come from (newest wins):
  - `claude -p /usage`: Claude Code answers /usage locally, without a model call (0 turns, $0),
    and its stream-json output carries the same structured report the terminal shows;
  - the report Claude Code saves in a session transcript when you run /usage yourself;
  - anything else that writes the same snapshot file (e.g. tools that see stream-json runs).

The snapshot is shared at $XDG_STATE_HOME/claude-usage/usage.json. usage.lock guards its writes
(held briefly); usage.check.lock lets one check run at a time. Standard library only (Python 3.9+).
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "claude-usage"
FILE = STATE / "usage.json"
CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")

# /usage report kinds → snapshot names. Other kinds (per-model weekly limits, …) are keyed by kind
# and scope, so two limits of one kind don't overwrite each other.
KIND_NAMES = {"session": "five_hour", "weekly_all": "seven_day"}

# Guards on the check. /usage is answered locally, but if a Claude Code version ever sent it to a
# model instead, these keep that to one tiny, tool-less Haiku turn without the user's hooks.
CHECK_FLAGS = ["--output-format", "stream-json", "--verbose", "--no-session-persistence",
               "--strict-mcp-config", "--tools", "", "--model", "haiku", "--max-turns", "1",
               "--setting-sources", "project"]


# --- snapshot file -------------------------------------------------------------------------------

class Locked:
    """An exclusive file lock in the state folder (blocking, or failing at once with nowait=True)."""
    def __init__(self, nowait: bool = False, name: str = "usage.lock"):
        self.nowait = nowait
        self.name = name

    def __enter__(self):
        STATE.mkdir(parents=True, exist_ok=True)
        self.f = open(STATE / self.name, "w")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | (fcntl.LOCK_NB if self.nowait else 0))
        except BlockingIOError:
            self.f.close()
            raise
        return self

    def __exit__(self, *exc):
        self.f.close()


def load() -> dict:
    try:
        snap = json.loads(FILE.read_text())
        return snap if isinstance(snap, dict) else {}
    except (OSError, ValueError):
        return {}


def _write(snap: dict) -> None:
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(snap, ensure_ascii=False, indent=2))
    tmp.replace(FILE)


def update(**fields) -> None:
    """Set top-level fields of the snapshot (bookkeeping: checked_transcripts, last_check, …)."""
    with Locked():
        _write({**load(), **fields})


def store(windows: dict, source: str, at: float) -> None:
    """Keep a snapshot only if it is newer than the one on disk."""
    if not windows:
        return
    with Locked():
        old = load()
        if old.get("at", 0) > at:
            return
        _write({**old, "at": at, "source": source, "windows": windows})


def iso(ts) -> float | None:
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp() if ts else None
    except ValueError:
        return None


def from_usage_report(report) -> dict:
    """Windows from a /usage report's `rate_limits.limits`. Anything malformed is skipped."""
    rate = report.get("rate_limits") if isinstance(report, dict) else None
    limits = rate.get("limits") if isinstance(rate, dict) else None
    windows = {}
    for lim in limits if isinstance(limits, list) else []:
        if not isinstance(lim, dict):
            continue
        try:
            pct = float(lim.get("percent"))
        except (TypeError, ValueError):
            continue
        kind = str(lim.get("kind") or "limit")
        scope = lim.get("scope") if isinstance(lim.get("scope"), str) else None
        w = {"pct": pct, "resets_at": iso(lim.get("resets_at")), "status": lim.get("severity")}
        if kind in KIND_NAMES:
            name = KIND_NAMES[kind]
        else:
            name = kind + (f":{scope}" if scope else "")
            w["label"] = kind.replace("_", " ").capitalize() + (f" ({scope})" if scope else "")
        windows[name] = w
    return windows


# --- sources -------------------------------------------------------------------------------------

def scan_transcripts() -> None:
    """Pick up /usage reports from Claude Code transcripts changed since the last look."""
    since = load().get("checked_transcripts", 0)
    now = time.time()
    for f in (CLAUDE_DIR / "projects").glob("*/*.jsonl"):
        try:
            if f.stat().st_mtime <= since:
                continue
            with open(f, errors="replace") as fh:
                for line in fh:
                    if '"usageReport"' not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(rec, dict):
                        store(from_usage_report(rec.get("usageReport")), "/usage in a terminal",
                              iso(rec.get("timestamp")) or 0)
        except OSError:
            continue
    update(checked_transcripts=now)


def check(claude: str, max_age: int) -> str | None:
    """Ask Claude Code for /usage, headless. Returns an error text, or None."""
    exe = shutil.which(os.path.expanduser(claude)) or os.path.expanduser(claude)
    try:
        lock = Locked(nowait=True, name="usage.check.lock").__enter__()
    except BlockingIOError:
        return None  # another check is running right now
    try:  # the snapshot is written before the lock is released, so a waiting check sees it
        snap = load()
        if time.time() - snap.get("at", 0) < 15:
            return None  # someone just checked
        update(last_check=time.time())
        with tempfile.TemporaryDirectory() as d:  # an empty folder: no CLAUDE.md, no project settings
            try:
                r = subprocess.run([exe, "-p", *CHECK_FLAGS, "--", "/usage"], cwd=d, stdin=subprocess.DEVNULL,
                                   capture_output=True, text=True, errors="replace", timeout=60)
            except FileNotFoundError:
                return f"Claude Code not found ({claude}); set its path in the widget settings"
            except (OSError, subprocess.TimeoutExpired) as e:
                return f"check failed: {e}"
        for line in r.stdout.splitlines():
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if isinstance(ev, dict) and isinstance(ev.get("usage_report"), dict):
                windows = from_usage_report(ev["usage_report"])
                if not windows:
                    return "Claude Code reported no plan limits (is it logged in with a Claude subscription?)"
                store(windows, "check", time.time())
                return None
        tail = (r.stderr.strip() or r.stdout.strip())[-200:]
        return f"no usage report from Claude Code (exit {r.returncode}){': ' + tail if tail else ''}"
    finally:
        lock.__exit__()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="check now")
    mode.add_argument("--auto", action="store_true", help="check only if the numbers are older than --max-age")
    ap.add_argument("--max-age", type=int, default=300, help="seconds (default 300)")
    ap.add_argument("--claude", default="claude", help="Claude Code executable (default: claude on PATH)")
    a = ap.parse_args()

    error = None
    try:
        scan_transcripts()
    except Exception as e:  # noqa: BLE001 - a bad transcript must not stop the widget
        error = f"could not read transcripts: {e}"
    snap = load()
    now = time.time()
    stale = now - snap.get("at", 0) > a.max_age
    # Back off after a failed check: at most one automatic attempt per max-age window.
    recently_tried = now - snap.get("last_check", 0) < a.max_age
    if a.refresh or (a.auto and stale and not recently_tried):
        failed = check(a.claude, a.max_age)
        update(last_error=failed)           # remembered, so the widget keeps showing it while backing off
        error = failed or error
    elif stale and recently_tried:
        error = snap.get("last_error") or error
    snap = load()
    for k in ("checked_transcripts", "last_check", "last_error"):
        snap.pop(k, None)
    if snap.get("at"):
        snap["age_seconds"] = round(time.time() - snap["at"])
    if error:
        snap["error"] = error
    json.dump(snap, sys.stdout, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
