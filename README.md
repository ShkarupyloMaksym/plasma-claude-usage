# Claude Usage — a KDE Plasma widget

Your Claude plan usage on the Plasma panel: the **session** (5-hour) and **weekly** limits, the same
numbers `/usage` shows in [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```
S ▬▬▬▬▬▬░░░░ 39%   W ▬░░░░░░░░░ 11%
```

- **Free and exact:** it asks Claude Code for `/usage` itself, which Claude Code answers locally
  (no model call, no cost). No API keys, and it never reads your Claude login.
- Click for every limit Claude Code reports (session, weekly, per-model weekly limits when your plan
  has them), with reset times and a **pace** line: where an even pace would be now, and where you'll
  end up by the reset.
- Notifications when a limit resets and when usage crosses the warning / critical level.
- Colours change at 75 % and 90 % (configurable, or pick your own colours). Old numbers are dimmed.
- Works on horizontal and vertical panels, in the system tray (hidden while there's no data, asks
  for attention at the critical level), and on the desktop (shows the full view when there's room).

> Not affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.

## Requirements

- KDE Plasma 6
- Python 3.9+ (standard library only)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and logged in with a
  Claude subscription (Pro / Max / Team). Tested with Claude Code 2.1.311 on Plasma 6.8.

## Install

From the KDE Store: *Add Widgets… → Get New Widgets… → Download New Plasma Widgets*, search
"Claude Usage". *(Coming soon.)*

From source:

```sh
git clone https://github.com/ShkarupyloMaksym/plasma-claude-usage
cd plasma-claude-usage
make install          # or: kpackagetool6 -t Plasma/Applet -i package
```

Then right-click the panel → *Add or Manage Widgets…* → **Claude Usage**.

## How it gets the numbers

The widget re-reads its bundled script (`package/contents/code/claude_usage.py`) every minute. The
script uses, newest first:

1. **A check**, when the numbers are older than 5 minutes (configurable, or off): it runs
   `claude -p /usage` in an empty temporary folder, with no MCP servers and no saved session. Claude
   Code answers `/usage` locally, without asking a model, so it reports **0 turns and $0** and uses
   none of your plan; Claude Code itself fetches your limits, with its own login.
2. **Reports from `/usage` in a terminal.** Claude Code saves each one in the session transcript
   under `~/.claude/projects/`; the script reads only those report records.

The latest numbers are kept in `~/.local/state/claude-usage/usage.json` (with a lock), so other
tools can read or update them too. The widget itself makes no network requests; Claude Code does,
for the check.

## Settings

Right-click → *Configure Claude Usage…*

**Appearance**

| Setting | Default |
|---|---|
| Show session / weekly / labels / time until reset | on / on / on / off |
| Pace marker | on |
| Percent remaining instead of used | off |
| Style: bar and percent, percent only, bar only | bar and percent |
| Bar width | 36 px |
| Warning / critical from | 75 % / 90 % used |
| Normal / warning / critical colours | the Plasma theme's |

**Updates & alerts**

| Setting | Default |
|---|---|
| Ask Claude Code for /usage when older than | on, 5 min |
| Dim when older than | 15 min |
| Re-read every | 60 s |
| Notify when a limit resets / crosses a level | on / on |
| Paths to Claude Code and Python 3 | `claude`, `python3` |
| "Open usage page" goes to | https://claude.ai/settings/usage |

## Development

```sh
make link     # Plasma loads the widget from this folder
make view     # open it in plasmoidviewer
make test     # run the data script, print the JSON
make check    # load the widget headless (horizontal + vertical) and confirm it runs
make lint
make package  # dist/claude-usage-<version>.plasmoid, for the KDE Store
```

See [docs/similar-projects.md](docs/similar-projects.md) for the other Claude usage widgets and
how each gets its numbers.

## License

MIT, see [LICENSE](LICENSE).
