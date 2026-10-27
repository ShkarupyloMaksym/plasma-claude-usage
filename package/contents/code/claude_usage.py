#!/usr/bin/env python3
"""Claude plan usage for the Plasma widget: session (5-hour) and weekly limits, in percent used.

Prints one JSON object:
  {"at": unix time, "source": "...", "age_seconds": n,
   "windows": {"five_hour": {"pct", "resets_at", "status"}, "seven_day": {...}}, "error"?: "..."}

Where the numbers come from (newest wins):
  - the report Claude Code saves in a session transcript when you run /usage;
  - a probe: one minimal `claude -p` call (no tools, one-line prompt, nothing saved) whose only job is
    to receive the `rate_limit_event` Claude Code prints. With Haiku it costs about $0.0006.
  - anything else that writes the same snapshot file (e.g. other tools that see stream-json runs).

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


# --- snapshot file -------------------------------------------------------------------------------

class Locked:
    """An exclusive lock on the state folder (blocking, or failing at once with nowait=True)."""
    def __init__(self, nowait: bool = False):
        self.nowait = nowait

    def __enter__(self):
        STATE.mkdir(parents=True, exist_ok=True)
        self.f = open(STATE / "usage.lock", "w")
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


def store(windows: dict, source: str, at: float) -> None:
    """Keep a snapshot only if it is newer than the one on disk."""
    if not windows:
        return
    with Locked():
        old = load()
        if old.get("at", 0) > at:
            return
        snap = {**old, "at": at, "source": source, "windows": windows}
        tmp = FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(snap, ensure_ascii=False, indent=2))
        tmp.replace(FILE)


def from_rate_limit(info: dict) -> dict:
    """Windows from a stream-json `rate_limit_event`'s `rate_limit_info`."""
    raw = info.get("unifiedWindows") or {}
    if not raw and info.get("rateLimitType") and info.get("utilization") is not None:
        raw = {info["rateLimitType"]: info}
    return {name: {"pct": round(float(w["utilization"]) * 100, 1), "resets_at": w.get("resetsAt"),
                   "status": w.get("status")}
            for name, w in raw.items() if isinstance(w, dict) and w.get("utilization") is not None}


def iso(ts) -> float | None:
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp() if ts else None
    except ValueError:
        return None


# --- sources -------------------------------------------------------------------------------------

def scan_transcripts() -> None:
    """Pick up /usage reports from Claude Code transcripts changed since the last look."""
    since = load().get("checked_transcripts", 0)
    now = time.time()
    names = {"session": "five_hour", "weekly_all": "seven_day"}
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
                    limits = ((rec.get("usageReport") or {}).get("rate_limits") or {}).get("limits") or []
                    windows = {names.get(l.get("kind"), l.get("kind")): {
                        "pct": float(l["percent"]), "resets_at": iso(l.get("resets_at")), "status": l.get("severity")}
                        for l in limits if isinstance(l, dict) and l.get("percent") is not None}
                    store(windows, "/usage in a terminal", iso(rec.get("timestamp")) or 0)
        except OSError:
            continue
    with Locked():
        snap = load()
        snap["checked_transcripts"] = now
        tmp = FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(snap, ensure_ascii=False, indent=2))
        tmp.replace(FILE)


def probe(claude: str, model: str) -> str | None:
    """Ask Claude Code for fresh numbers with a minimal call. Returns an error text, or None."""
    exe = shutil.which(os.path.expanduser(claude)) or os.path.expanduser(claude)
    try:
        lock = Locked(nowait=True).__enter__()
    except BlockingIOError:
        return None  # another check is running right now
    try:
        if time.time() - load().get("at", 0) < 30:
            return None  # someone just checked
        argv = [exe, "-p", "--model", model, "--tools", "", "--system-prompt", "Reply with the single word OK.",
                "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
                "--output-format", "stream-json", "--verbose", "--", "OK"]
        with tempfile.TemporaryDirectory() as d:  # an empty folder: no CLAUDE.md, no project settings
            try:
                r = subprocess.run(argv, cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                   errors="replace", timeout=90)
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
        if isinstance(ev, dict) and ev.get("type") == "rate_limit_event":
            store(from_rate_limit(ev.get("rate_limit_info") or {}), "check", time.time())
            return None
    tail = (r.stderr.strip() or r.stdout.strip())[-200:]
    return f"no usage data from Claude Code (exit {r.returncode}){': ' + tail if tail else ''}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="check now")
    mode.add_argument("--auto", action="store_true", help="check only if the numbers are older than --max-age")
    ap.add_argument("--max-age", type=int, default=600, help="seconds (default 600)")
    ap.add_argument("--claude", default="claude", help="Claude Code executable (default: claude on PATH)")
    ap.add_argument("--model", default="haiku", help="model for the check (default: haiku, the cheapest)")
    a = ap.parse_args()

    scan_transcripts()
    error = None
    if a.refresh or (a.auto and time.time() - load().get("at", 0) > a.max_age):
        error = probe(a.claude, a.model)
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
