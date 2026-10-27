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

The snapshot is shared at $XDG_STATE_HOME/claude-usage/usage.json, guarded by a file lock.
Standard library only (Python 3.9+).
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

# /usage report kinds → snapshot names. Unknown kinds (per-model weekly limits, …) keep their kind.
KIND_NAMES = {"session": "five_hour", "weekly_all": "seven_day"}


# --- snapshot file -------------------------------------------------------------------------------

class Locked:
    """An exclusive file lock in the state folder (blocking, or failing at once with nowait=True).
    usage.lock guards writes of usage.json (held briefly); usage.check.lock lets one check run at a time."""
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
        return json.loads(FILE.read_text())
    except (OSError, ValueError):
        return {}


def _write(snap: dict) -> None:
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(snap, ensure_ascii=False, indent=2))
    tmp.replace(FILE)


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


def from_usage_report(report: dict) -> dict:
    """Windows from a /usage report's `rate_limits.limits` list."""
    windows = {}
    for lim in ((report or {}).get("rate_limits") or {}).get("limits") or []:
        if not isinstance(lim, dict) or lim.get("percent") is None:
            continue
        kind = str(lim.get("kind") or "limit")
        name = KIND_NAMES.get(kind, kind)
        w = {"pct": float(lim["percent"]), "resets_at": iso(lim.get("resets_at")), "status": lim.get("severity")}
        if name not in KIND_NAMES.values():  # e.g. a per-model weekly limit: say what it is
            scope = lim.get("scope")
            w["label"] = kind.replace("_", " ").capitalize() + (f" ({scope})" if isinstance(scope, str) else "")
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
    with Locked():
        snap = load()
        snap["checked_transcripts"] = now
        _write(snap)


def check(claude: str) -> str | None:
    """Ask Claude Code for /usage, headless. No model call, no cost. Returns an error text, or None."""
    exe = shutil.which(os.path.expanduser(claude)) or os.path.expanduser(claude)
    try:
        lock = Locked(nowait=True, name="usage.check.lock").__enter__()
    except BlockingIOError:
        return None  # another check is running right now
    try:
        if time.time() - load().get("at", 0) < 15:
            return None  # someone just checked
        argv = [exe, "-p", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                "--strict-mcp-config", "--", "/usage"]
        with tempfile.TemporaryDirectory() as d:  # an empty folder: no CLAUDE.md, no project settings
            try:
                r = subprocess.run(argv, cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                   errors="replace", timeout=60)
            except FileNotFoundError:
                return f"Claude Code not found ({claude}); set its path in the widget settings"
            except (OSError, subprocess.TimeoutExpired) as e:
                return f"check failed: {e}"
    finally:
        lock.__exit__()
    for line in r.stdout.splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if isinstance(ev, dict) and isinstance(ev.get("usage_report"), dict):
            windows = from_usage_report(ev["usage_report"])
            if windows:
                store(windows, "check", time.time())
                return None
            return "Claude Code reported no plan limits (is it logged in with a Claude subscription?)"
    tail = (r.stderr.strip() or r.stdout.strip())[-200:]
    return f"no usage report from Claude Code (exit {r.returncode}){': ' + tail if tail else ''}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="check now")
    mode.add_argument("--auto", action="store_true", help="check only if the numbers are older than --max-age")
    ap.add_argument("--max-age", type=int, default=300, help="seconds (default 300)")
    ap.add_argument("--claude", default="claude", help="Claude Code executable (default: claude on PATH)")
    a = ap.parse_args()

    scan_transcripts()
    error = None
    if a.refresh or (a.auto and time.time() - load().get("at", 0) > a.max_age):
        error = check(a.claude)
    snap = load()
    snap.pop("checked_transcripts", None)
    if snap.get("at"):
        snap["age_seconds"] = round(time.time() - snap["at"])
    if error:
        snap["error"] = error
    json.dump(snap, sys.stdout, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
