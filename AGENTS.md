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
- `logo.png` — emkcloud brand mark (the org GitHub avatar), used as the hero
  icon. The only image in this repo. The original near-black backdrop
  (`#010409`, rounded square) has been made **transparent** so the mark sits on
  `Color.menu.background`: alpha is derived from the max RGB channel
  (`-separate -evaluate-sequence Max -level 4%,85%`), which keeps the three
  brand colors bit-exact (`#155DFC`, `#E12AFB`, `#05DF72`) and preserves the
  anti-aliased edges. Do NOT re-flatten it on black.
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
- Install target (local Omarchy): `~/.config/omarchy/backgrounds/<theme>/`.
- Preview thumbnails load directly from the remote `url` in the catalog (the
  `GridView` only instantiates visible delegates, so loading is lazy). No local
  preview cache.

## Design canon (decision 2026-09-03)

There is **no written design guide** in Omarchy. The standard is implicit and
lives in three places: the `qs.Commons` token singletons, the `qs.Ui` component
library, and the living showcase `omarchy dev ui-preview`
(`omarchy.dev-gallery`). This plugin is **fully aligned** to it — do not drift.

Omarchy has two chrome families. We are family A (fullscreen overlay), not
family B (bar-anchored panel):

| | A — overlay | B — panel |
|---|---|---|
| Examples | `menu`, `clipboard`, `emojis`, `reminders` | `audio`, `network`, `agents` |
| Colors | `Color.menu.*` | `Color.popups.*` |
| Padding | `Style.spacing.panelPadding` (18) | `Style.spacing.popupPadding` (14) |

Rules that follow from that:

- **One flat surface.** The card is a single `Ui/BorderSurface` filled with
  `Color.menu.background`, `radius: Style.cornerRadius`, `padding:
  Style.spacing.panelPadding`, `borderSpec: Border.surfaceSpec("menu",
  "border", …)` (never `border.color`: the spec is what carries the Hyprland
  gradient and per-side widths). **No header/footer bars, no per-region fills.**
  Separation is `Style.spacing.md` of empty space plus `Ui/PanelSeparator`
  (1px, `foreground @ 0.12`).
- **Card size**: `Math.min(Style.space(N), panel.width - Style.gapsOut * 2)`.
  `Style.gapsOut` is the canonical screen margin (it is already half of
  Hyprland's `gaps_out`).
- **Header** = `Ui/PanelHero`: icon + bold title (`Style.font.title`) +
  UPPERCASE meta caption + optional `detail` pill + `trailingControl` for the
  buttons. The icon is the **emkcloud logo** (`logo.png` at the repo root, the
  org avatar) via the local `HeroLogo` inline component: a `RoundedImage`
  `Style.font.displayLarge` wide, same in every view, with the old nerd-font
  glyphs (`󰸌` themes, `` wallpapers) as fallback if the file cannot be
  resolved. `logo.png` is the only image allowed in this repo.
- **Header height** is pinned: `root.heroHeight =
  Math.max(hero.implicitHeight, previewHero.implicitHeight)` is applied as
  `height` to both heroes, so switching view — or a title growing a resolution
  suffix — never shifts the separator and the content below.
- **Secondary text** is `Qt.darker(foreground, 1.4)` (exposed as `root.dim`),
  not `Util.alpha(...)`.
- **Selection**: `Ui/CursorSurface` only. Its contract forbids reading
  `containsMouse` for color/border — mouse hover calls `root.takeCursor(index)`
  and visuals derive from `hasCursor` / `current`, so exactly one tile is ever
  highlighted across mouse *and* keyboard. `current` marks the theme default
  wallpaper.
- **Keyboard** = `Ui/PanelKeyCatcher` wrapping the content; the panel keeps the
  state machine (`moveCursor(dx,dy)` / `activateCursor()` / `dismissCursor()`).
  Canonical keys: arrows + h/j/k/l, Enter/Space activate, Esc back/close,
  **x/X remove** (`deleteRequested`), `d` default and `r` refresh via
  `textKey`. Del/Backspace and **PageUp/PageDown** (jump a whole visible page
  of tiles — visible rows × columns — via `pageCursor(dir)`) work through a
  fallback `Keys.onPressed` on the card (the catcher does not accept them, so
  they bubble up).
- **Buttons** = `Ui/Button` with `bordered: true`. Never pin `hasCursor: true`
  — the component derives `hot` from its own hover. Key hints go in
  `tooltipText`, which is the canonical hint channel.
- **Pills** (installed / default) follow the `detail` pill of `PanelHero`:
  transparent fill, `Border.flat(tint, …)`, caption text in the tint. No
  colored blobs.
- **Status** is a single dim caption centered at the bottom. There is no footer
  bar.
- **No spinners** (decision 2026-09-03). Do NOT reintroduce one. Wallpapers
  resolve in well under 400ms here (pixmap cache / fast network), so a rotating
  glyph either blinks for a single frame or has to be delayed until it is
  pointless. Loading feedback is textual and instant: `LOADING <file>` /
  `FAILED TO LOAD <file>` in the hero meta line. (`BusyIndicator` does not exist
  anywhere in the shell either.)
- Lint with `qmllint -I <dir containing a `qs` symlink to
  /usr/share/omarchy/shell>`. The residual `unqualified` /
  `missing-property` warnings on `Style.spacing.*`, `Style.font.*`,
  `Color.menu.*` are unavoidable (the shell's own code produces them).

## Current state (history)

Built and tested on this machine (branch `main`). What works today:

- **Flow**: summon → `manager.sh themes` fetches `datasets.json` (only
  `kind=="theme"` collections) and emits TSV
  (`name|title|catalogUrl|sections|count|preview`) → pick a theme →
  `manager.sh catalog <theme> <url>` fetches `catalog.json` and emits TSV
  (`filename|name|code|url|sha256|installed|is_default`) → grid of tiles.
- **Collection label**: the tiles show `root.themeLabel(model)`, i.e. the
  readable `title` of the dataset (`"tokyo-night"` → `"Tokyo Night"`, added by
  `build_collection` in the wallpapers repo) uppercased → `TOKYO NIGHT`. If a
  dataset has no `title` the slug is normalized (`-`/`_` → space) as fallback.
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
- **Keyboard**: driven by `Ui/PanelKeyCatcher` (see "Design canon"). Themes view
  — arrows/h-j-k-l move, Enter/Space selects, Esc closes. Grid — same movement
  (vertical via a computed `colCount`, not the nonexistent `GridView.columns`),
  Enter=fullscreen preview, x/X or Del/Backspace=remove, PageUp/PageDown=jump
  a page of tiles, d=set default,
  r=refresh, Esc=back to themes (Esc again closes). Preview — h/l or j/k or
  arrows next/prev, Enter=install, Esc=back to grid. Mouse: hover moves the
  shared cursor, **click on a tile opens the fullscreen preview** (same as
  Enter), click outside the card closes. Since a single click on a tile already
  switches view, "set default" by mouse lives **in the preview**: double click
  on the wallpaper (`previewView.onImage(point)` routes the taps — a tap outside
  the image goes back, on the image the single tap is inert because it is the
  first half of the double tap). Do NOT put single-tap-selects back on the tile.
- **Fullscreen preview** (Enter on a tile): full-res wallpaper at natural size
  under a `PanelHero` whose title is `<code> - <name> (<width>x<height>)` — the
  code inline in the title (no `detail` pill, decision 2026-09-03) and the real
  resolution of the visible image, appended only once the image of the selected
  item is `Ready` (`previewView.shown`) so a name is never paired with the
  previous resolution. Filename in the meta line, installed/default pills in
  `trailingControl`.
  **Double-buffered**: the current image stays visible while the next one is
  preloaded in a hidden `nextImage`; the swap happens only when the new one is
  `Ready` (instant from the pixmap cache), so navigating never shows a blank
  screen. On load error the previous wallpaper stays on screen and the meta line
  reports `FAILED TO LOAD <file>`. No spinner.

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
- **Do NOT verify the UI with screenshots** (`grim` + reading the image): it is
  slow and expensive. After restarting the shell, just ask the user to look at
  the overlay and report the visual result.
- Corner rounding must always come from `Style.cornerRadius` (mirrors
  Hyprland's `decoration:rounding`), never a hardcoded number. Images need the
  `RoundedImage` inline component (`layer.effect: MultiEffect` + mask) because
  `clip: true` on an `Image` only clips rectangularly.