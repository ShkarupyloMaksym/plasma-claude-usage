# Similar projects (researched 2026-10-27)

Found by web search and by reading each README. Star counts and dates are as shown on GitHub that
day. None of the KDE widgets below was found as a KDE Store listing; KClaude says it installs via
"Get New Widgets", but no store page turned up.

## KDE Plasma 6 widgets for Claude limits

| Project | Data source | Notable features | License |
|---|---|---|---|
| [chrisOTM/claude-usage-plasmoid](https://github.com/chrisOTM/claude-usage-plasmoid) | `api.anthropic.com/api/oauth/usage` with the token from `~/.claude/.credentials.json`; refreshes the token itself | reset notifications with sound, colours incl. pulsing at 100 %, 45 s rate limit + cache | MIT |
| [chaybits/ai-session-usage](https://github.com/chaybits/ai-session-usage) | runs `claude` headless with a usage request (no prompt); optional status-line tap; Codex via `codex app-server` | Claude **and** ChatGPT/Codex, stale data turns yellow after 15 min, row order, Rainmeter + Windows widget versions | GPL-3.0+ |
| [iglemartin/AIUsageMeter](https://github.com/iglemartin/AIUsageMeter) | status-line tap only (`rate_limits` in Claude Code's status-line JSON → `~/.cache/ai-usage-meter/usage.json`) | no credentials, no network; bar or ring; % used or % remaining; "Connect to Claude Code" button edits `settings.json` with backup | MIT |
| [imdizmo/claude-usage-tracker](https://github.com/imdizmo/claude-usage-tracker) | OAuth usage endpoint + local session logs | pace marker and projection at reset, token activity (today/7d/30d, 12-week grid), live sessions, threshold alerts; also a PySide6 tray | MIT |
| [JamesStuder/plasma-claude-usage](https://github.com/JamesStuder/plasma-claude-usage) | OAuth usage endpoint + session logs | **same repo name as ours**; v1 was a Plasma widget, now "Claude Tray" (.NET/Avalonia) with pace, tokens per model, session list | MIT |
| [Agundur-KDE/KClaude](https://github.com/Agundur-KDE/KClaude) | status-line hook `rate_limits` → `quota.json` | mainly a Claude Code session launcher (Konsole, notifications, KRunner); usage is a small line | ? |
| [43v3r-y0ung/claude-usage-kdewidget](https://github.com/43v3r-y0ung/claude-usage-kdewidget), [schiz0x00/kclaude](https://github.com/schiz0x00/kclaude), [Nael-Nathanael/claude-limits-plasmoid](https://github.com/Nael-Nathanael/claude-limits-plasmoid), [JakeGT/claude-usage-plasmoid](https://github.com/JakeGT/claude-usage-plasmoid), [nicholas-fedor/clankerwatch](https://github.com/nicholas-fedor/clankerwatch) | mostly the OAuth endpoint | per-model token history, monthly window, Go daemon, … (not read in detail) | |
| plasma-ai-usage-monitor ([Fedora COPR spec](https://copr-be.cloud.fedoraproject.org/results/loofitheboss/plasma-ai-usage-monitor/srpm-builds/10429391/plasma-ai-usage-monitor.spec)) | provider **API keys** in KDE Wallet | multi-provider API cost/budget tracking, SQLite history, CSV export; a different audience (API users, not subscriptions) | GPL-3.0+ |

## Other desktops

- GNOME: [Claude Code Usage Monitor](https://extensions.gnome.org/extension/10086/claude-code-usage-monitor/),
  [stfnRO/gnome-shell-extension-claude-usage](https://github.com/stfnRO/gnome-shell-extension-claude-usage)
  (OAuth API every 3 min, Sonnet row), [wilfison/ai-usagebar](https://github.com/wilfison/ai-usagebar) (Claude + Codex + more).
- Waybar / Omarchy: [mryll/claudebar](https://github.com/mryll/claudebar) (per-model limits, extra-usage cost, AUR),
  [infiniV/claude-usage-waybar](https://github.com/infiniV/claude-usage-waybar) (status-line data + ccusage spend).
- macOS only: Usage4Claude, Claude Monitor, ClaudeCodeMonitor, CodexBar.

## Ways to get the numbers

| Way | Cost | Touches credentials | Freshness | Risk |
|---|---|---|---|---|
| OAuth usage endpoint with Claude Code's token (most widgets) | free | **reads, some refresh and rewrite the token file** | any time | undocumented API; a token refresh racing Claude Code can log you out |
| Status-line tap (`rate_limits` in the status-line JSON) | free | no | only while you use Claude Code | edits `~/.claude/settings.json` |
| **`claude -p "/usage"` headless** (ai-session-usage) | **free: 0 turns, $0** (tested 2026-10-27, Claude Code 2.1.311) | no (Claude Code does it) | any time | relies on the CLI's output format |
| A minimal model call for the `rate_limit_event` (our v1.0.0) | ~$0.0006 per check with Haiku | no | any time | costs a little plan usage |

Tested here: `claude -p "/usage" --output-format stream-json --verbose --no-session-persistence`
prints an `assistant` event with `usage_report.rate_limits.limits[]` (`kind` session / weekly_all,
`percent`, `resets_at`, `severity`), `num_turns: 0`, `total_cost_usd: 0`. Exact `/usage` numbers,
no model call.

## What this means for us

- The space is crowded on GitHub but **nothing was found on the KDE Store** yet, so a polished store
  listing is still early.
- Our honest differentiators: **free, exact, no credentials** (via `claude -p /usage`), stdlib only,
  a shared snapshot other tools can feed, clear privacy text.
- Worth borrowing: pace marker / projection (imdizmo, Claude Tray), reset notifications (chrisOTM),
  stale-data colouring (chaybits), % used ↔ % remaining and a ring style (AIUsageMeter), per-model
  weekly limits when `/usage` reports them (claudebar), optional Codex (chaybits, ai-usagebar).
- Pick a distinct store name: "Claude Usage" and `plasma-claude-usage` are both taken in spirit.
