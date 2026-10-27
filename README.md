# Claude Usage — a KDE Plasma widget

Your Claude plan usage on the Plasma panel: the **session** (5-hour) and **weekly** limits, the same
numbers `/usage` shows in [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```
S ▬▬▬▬▬▬░░░░ 39%   W ▬░░░░░░░░░ 11%
```

Click it for both bars with their reset times, **Check now**, and a link to your usage page.
Colours change at 75 % and 90 % (configurable).

> Not affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.

## Requirements

- KDE Plasma 6
- Python 3.9+ (standard library only)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and logged in with a
  Claude subscription (Pro / Max / Team). Tested with Claude Code 2.1.311.

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

The widget runs its bundled script (`package/contents/code/claude_usage.py`) every minute. The
script uses, newest first:

1. **Reports from `/usage`.** When you run `/usage` in Claude Code, the report is saved in the session
   transcript under `~/.claude/projects/`. The script looks only for those report records.
2. **A check**, if you allow it (on by default) and the numbers are older than 10 minutes: one
   minimal `claude -p` call with no tools, a one-line system prompt, no MCP servers and no saved
   session, in an empty temporary folder. Its only purpose is the `rate_limit_event` Claude Code
   prints. With Haiku it costs about **$0.0006** and counts toward your plan like any other use
   (with defaults, at most ~6 per hour while you're logged in).

The latest numbers are kept in `~/.local/state/claude-usage/usage.json` (with a lock), so other
tools can read or update them too. The widget itself makes no network requests; Claude Code does,
for the check.

## Settings

Right-click → *Configure Claude Usage…*

| Setting | Default |
|---|---|
| Show session / weekly / labels / reset times | on / on / on / off |
| Style: bar and percent, percent only, bar only | bar and percent |
| Bar width | 36 px |
| Colour thresholds (warning, critical) | 75 %, 90 % |
| Ask Claude Code for fresh numbers when older than | on, 10 min |
| Model for the check | haiku |
| Re-read every | 60 s |
| Paths to Claude Code and Python 3 | `claude`, `python3` |
| "Open usage page" goes to | https://claude.ai/settings/usage |

## Development

```sh
make link     # Plasma loads the widget from this folder
make view     # open it in plasmoidviewer
make test     # run the data script, print the JSON
make lint
make package  # dist/claude-usage-<version>.plasmoid, for the KDE Store
```

## License

MIT, see [LICENSE](LICENSE).
