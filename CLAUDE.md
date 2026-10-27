# CLAUDE.md

## What this is

`plasma-claude-usage`: a KDE Plasma 6 widget that shows Claude plan usage (session 5 h / weekly),
like `/usage`. **Public** on GitHub (`ShkarupyloMaksym/plasma-claude-usage`, MIT); the goal is the
KDE Store. Split out of the author's claude-admin panel, whose web UI shows the same numbers.

Status (newest last; dated, never rewritten: strike and annotate instead):
- **2026-10-27:** Moved from claude-admin into its own repo; standalone (bundled data script instead
  of claude-admin's panel.py); plugin id `io.github.shkarupylomaksym.claudeusage`; settings for
  display style, bar width, thresholds, labels, check age/model, paths, open URL. Checked headless
  with plasmoidviewer and qmllint; the data script ran a real check. Not yet on the KDE Store.
- **2026-10-27:** v1.1.0. ~~Paid probe (a Haiku call, ~$0.0006)~~ → free check `claude -p /usage`
  (stream-json `usage_report`, 0 turns, $0; found via research, `docs/similar-projects.md`). Per-model
  limits, pace marker + projection, % remaining, stale dimming, reset/threshold notifications
  (`Notifier.qml`, loaded so a missing KNotifications module can't break the widget), custom colours,
  two settings pages, vertical panels, `Plasmoid.status`, desktop full view, keyboard/accessibility.
  Colour bug (bars turned white after the widget was opened): colours now come from a non-inheriting
  theme reference instead of the applet's inherited highlight colour. Tests: `make check` (a broken
  copy fails it, the real one passes in both orientations); plasmoidviewer prints no QML errors on
  stderr, so don't rely on its silence. Settings pages: only qmllint-checked.

## Layout

- `package/`: the plasmoid (what `kpackagetool6` installs and the `.plasmoid` zip contains).
  - `metadata.json`: id, name, version (bump for every store upload), author, website.
  - `contents/ui/main.qml`: the widget (panel view, popup, tooltip, actions, timer).
  - `contents/ui/config{Appearance,Updates}.qml` + `contents/config/{main.xml,config.qml}`: settings.
  - `contents/ui/Notifier.qml`: desktop notifications (optional module, loaded by a Loader).
  - `contents/code/claude_usage.py`: the data script, Python 3 stdlib only, prints JSON.
- `Makefile`: package / install / link / view / test / check / lint.
- `docs/similar-projects.md`: the other Claude usage widgets and how each gets its numbers.

## Rules

- **Public repo.** Nothing personal in it: no local paths, no usage numbers, no session data.
  Check `git diff --cached` before every commit for `/home/`, emails other than the author's, tokens.
- The shared snapshot format (`~/.local/state/claude-usage/usage.json`: `at`, `source`, `windows`
  with `five_hour` / `seven_day` → `pct`, `resets_at`, `status`) is also written by claude-admin's
  `backend/usage.py` (a separate, private repo). Change both together, and keep both file locks: `usage.lock` (held briefly around writes) and
  `usage.check.lock` (one check at a time).
- The check is `claude -p /usage` (answered locally by Claude Code: no model call, $0), in an empty
  temp folder, nothing saved. Never read transcripts for anything but `usageReport` records, and never
  read Claude Code's credentials.
- Keep the data script standard-library only and compatible with Python 3.9.
- Commit only when asked; the user pushes (or explicitly asks for a push).
