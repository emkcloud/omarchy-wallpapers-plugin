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
  local install state, caches the `wallpapers.py` helper.
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
  The overlay uses a solid `Color.popups.background` card + `cardBorder`, a
  `scrim` on `Color.background`, and custom readable fills
  (`barFill`, `tileFill`, `tileBorder`) derived from `Color.foreground`. High
  contrast was explicitly requested by the user.
- Remote data flows through `manager.sh` (curl + jq); QML parses TSV output.
- Actions delegate to `wallpapers.py` (sha256 checks, parallel download, bg cache
  refresh) and `omarchy-theme-bg-set` for the default background.
- Install target (local Omarchy): `~/.config/omarchy/backgrounds/<theme>/`.
- The UI is an overlay `PanelWindow` (pattern from `image-picker`); keyboard
  navigation uses `Keys` on the grid (arrows/j-k/h-l, Enter=install,
  Del=remove, D=default, Esc=back).
- Preview thumbnails load directly from the remote `url` in the catalog (the
  `GridView` only instantiates visible delegates, so loading is lazy). No local
  preview cache.

## Current state (history)

Built and tested on this machine (branch `main`). What works today:

- **Flow**: summon → `manager.sh themes` fetches `datasets.json` (only
  `kind=="theme"` collections) → pick a theme → `manager.sh catalog <theme>
  <url>` fetches `catalog.json` and emits TSV
  (`filename|name|code|url|sha256|installed|is_default`) → grid of tiles.
- **Preview strategy**: tiles load the **reduced `preview` URL** from the
  catalog (`previews/<theme>/<section>/…-preview.webp`), not the full-res
  image. If the wallpaper is already installed locally, the tile uses the local
  file (instant); if a wallpaper lacks a `preview`, it falls back to its full
  `url`. The `GridView` only instantiates visible delegates → lazy, page-by-page
  loading. This works for thousands of images.
- **Grid layout**: `GridView` with dynamic columns
  (`columnsHint` = `max(2, width / minTileWidth)`), `cellWidth = width/columns`,
  `cellHeight = cellWidth*0.9`. `minTileWidth ~ Style.space(190)` keeps
  previews readable. Do NOT put anchors on the delegate (broke grid → single
  column).
- **Keyboard**: themes view — arrows/j-k move, Enter selects, Esc closes.
  Grid — arrows/j-k-h-l move (vertical via a computed `colCount`, not the
  nonexistent `GridView.columns`), Enter=fullscreen preview, Del/Backspace=
  remove, D=set default, Esc=back to themes (Esc again closes). Preview — ←/→
  (h/l) or ↑/↓ (j/k) next/prev, Enter=install, Esc=back to grid. Mouse: click
  selects, double-click = set default, click outside card closes.
- **Fullscreen preview** (Enter on a tile): full-res wallpaper at natural size
  in a header bar with name, real resolution, filename and installed/default
  badges. **Double-buffered**: the current image stays visible while the next
  one is preloaded in a hidden `nextImage`; the swap happens only when the new
  one is `Ready` (instant from the pixmap cache), so navigating never shows a
  blank screen. A `BusyIndicator` spins over the current image while a remote
  wallpaper downloads. The preview header uses the same height as the main one
  (`Style.space(64)`) to avoid resize jumps between screens.

### Bugs fixed along the way (do not reintroduce)

1. `fetch()` in `manager.sh` must pass extra curl args (`curl ... "$@"`, not
   only `"$1"`) — otherwise `-o` is dropped and downloads fail.
2. `catalogProc` needs its `command` set **before** `running = true`
   (in `loadWallpapers()`); starting it without a command hangs the UI on
   "Caricamento…" forever.
3. Inotify does NOT follow the symlink → QML edits are not hot-reloaded; a
   shell restart is required (see below). This once made the user see a stale,
   "transparent" version.
4. Tiles must not anchor-horizontalCenter themselves (single-column bug).
5. `GridView` has no `columns` property in Qt 6 — `grid.columns` /
   `themesGrid.columns` are `undefined`, so Up/Down turned `selectedIndex`
   into `NaN` (left/right worked since they use `±1`). Compute the column
   count manually (`colCount = max(1, floor(width / cellWidth))`) and call
   `positionViewAtIndex` after every move to keep the selection visible.

## Local development

```bash
ln -s /home/massimo/Repositories/omarchy-wallpapers-plugin \
      ~/.config/omarchy/plugins/emkcloud.wallpaper-manager
omarchy-shell shell rescanPlugins
omarchy-shell shell enablePlugin emkcloud.wallpaper-manager '{}'
omarchy-shell shell summon emkcloud.wallpaper-manager '{}'
```

> ⚠️ **Symlink vs hot-reload.** The shell watches `~/.config/omarchy/plugins/`
> with inotify, which does **not** follow symlinks. If the plugin dir is a
> symlink, edits are NOT hot-reloaded. After changing QML, restart the shell:
> `omarchy restart shell`, then re-summon. (For true hot-reload, copy the files
> into `~/.config/omarchy/plugins/<id>/` instead of symlinking.)

## Distribution

The repo root is the plugin: `omarchy plugin add
https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes`.
Keep `manifest.json` at the repo root (required by `omarchy plugin add`).

## Notes for the agent

- The user speaks Italian: respond and comment in Italian.
- **UI language**: all user-facing strings in `WallpaperManager.qml` are in
  **English** (decision 2026-09-02). Multilingual support is TBD — do not
  introduce a translation framework yet; just keep strings in English until
  the user decides how to handle i18n.
- Commit messages: concise (short and to the point).