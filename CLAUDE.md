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

## Layout

- `package/`: the plasmoid (what `kpackagetool6` installs and the `.plasmoid` zip contains).
  - `metadata.json`: id, name, version (bump for every store upload), author, website.
  - `contents/ui/main.qml`: the widget (panel view, popup, tooltip, actions, timer).
  - `contents/ui/configGeneral.qml` + `contents/config/{main.xml,config.qml}`: settings.
  - `contents/code/claude_usage.py`: the data script, Python 3 stdlib only, prints JSON.
- `Makefile`: package / install / link / view / test / lint.

## Rules

- **Public repo.** Nothing personal in it: no local paths, no usage numbers, no session data.
  Check `git diff --cached` before every commit for `/home/`, emails other than the author's, tokens.
- The shared snapshot format (`~/.local/state/claude-usage/usage.json`: `at`, `source`, `windows`
  with `five_hour` / `seven_day` → `pct`, `resets_at`, `status`) is also written by claude-admin's
  `backend/usage.py` (a separate, private repo). Change both together, and keep the file lock (`usage.lock`).
- The check must stay minimal and honest: no tools, nothing saved, an empty temp folder, and the
  README states what it costs. Never read transcripts for anything but `usageReport` records.
- Keep the data script standard-library only and compatible with Python 3.9.
- Commit only when asked; the user pushes (or explicitly asks for a push).
