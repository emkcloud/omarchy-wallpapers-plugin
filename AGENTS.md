# AGENTS.md

Guidelines for AI agents working on this repository. Read this file before making any changes.

## Project overview

Omarchy shell plugin: **`emkcloud.wallpaper-manager`**. It browses the remote
wallpaper collection of the `emkcloud/omarchy-wallpapers` repo and manages the
local installation of its wallpapers inside Omarchy (install / remove /
set-default), theme by theme.

## Structure

- `manifest.json` — plugin manifest (id `emkcloud.wallpaper-manager`, kind
  `overlay`, entry point `WallpaperManager.qml`). Validated by
  `omarchy plugin validate`.
- `WallpaperManager.qml` — the plugin UI (Quickshell/QML).
- `manager.sh` — bash helper: fetches JSON from the wallpapers repo, computes
  local install state, caches previews.
- `datasets/`, `images/`, `masters/` — never here. The wallpapers live in the
  separate repo `emkcloud/omarchy-wallpapers`.

## Plugin contract (Omarchy)

- Plugin id must NOT use the reserved `omarchy.*` namespace.
- `kinds` supported: `bar-widget`, `panel`, `overlay`, `menu`, `service`, `bar`.
- Overlay lifecycle: implement `open(payload)` / `close()`; summon with
  `omarchy-shell shell summon <id> '{}'` and hide with `shell hide <id>`.
- `keepLoaded: true` keeps the window mounted between summons.
- The plugin receives injected properties from the shell: `manifest`
  (carries `__sourceDir`, used to locate `manager.sh`), `shell`,
  `pluginRegistry`. Declare `property var manifest: null` to receive them.
- Reference sources (read-only): `/usr/share/omarchy/shell/README.md`,
  `/usr/share/omarchy/shell/plugins/image-picker/`,
  `/usr/share/omarchy/shell/plugins/dev-gallery/`,
  `/usr/share/omarchy/shell/services/PluginRegistry.qml`.

## Operational rules

- Themed colors come from `qs.Commons.Color` / `qs.Commons.Style` — never hardcode.
- Remote data flows through `manager.sh` (curl + jq); QML parses TSV output.
- Actions delegate to `wallpapers.py` (sha256 checks, parallel download, bg cache
  refresh) and `omarchy-theme-bg-set` for the default background.
- Local preview cache: `~/.cache/omarchy/wallpaper-manager/<theme>/`.
- Install target (local Omarchy): `~/.config/omarchy/backgrounds/<theme>/`.
- The UI is an overlay `PanelWindow` (pattern from `image-picker`); keyboard
  navigation uses `Keys` on the grid (arrows/j-k/h-l, Enter=install,
  Del=remove, D=default, Esc=back).

## Local development

```bash
ln -s /home/massimo/Repositories/omarchy-wallpapers-plugin \
      ~/.config/omarchy/plugins/emkcloud.wallpaper-manager
omarchy-shell shell rescanPlugins
omarchy-shell shell enablePlugin emkcloud.wallpaper-manager '{}'
omarchy-shell shell summon emkcloud.wallpaper-manager '{}'
```

Changes under `~/.config/omarchy/plugins/` hot-reload on save; force reload with
`omarchy-shell shell rescanPlugins`.

## Distribution

The repo root is the plugin: `omarchy plugin add
https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes`.
Keep `manifest.json` at the repo root (required by `omarchy plugin add`).

## Notes for the agent

- The user speaks Italian: respond and comment in Italian.
- Commit messages: concise (short and to the point).