# AGENTS.md

Guidelines for AI agents working on this repository. Read this file before making any changes.

## Project overview

Omarchy shell plugin: **`emkcloud.wallpaper-manager`**. It browses the remote
wallpaper collection of the `emkcloud/omarchy-wallpapers` repo and manages the
local installation of its wallpapers inside Omarchy (install / remove /
set-default), theme by theme.

## Repository layout

- `manifest.json` — plugin manifest (id `emkcloud.wallpaper-manager`, kind
  `overlay`, entry point `WallpaperManager.qml`). Validated by
  `omarchy plugin validate`.
- `WallpaperManager.qml` — the entire UI. Quickshell/QML, **one file**, all
  views plus the inline components `RoundedImage`, `HeroLogo`, `Pill`.
- `manager.sh` — bash helper: fetches JSON from the wallpapers repo, computes
  local install state, and runs install/remove/set-default natively (curl + jq +
  sha256). Talks to the QML via TSV on stdout.
- `config.json` — pins the upstream release: `{"repo": "...", "release": "..."}`.
  `manager.sh` reads the `release` (a tag) and builds every upstream URL from it,
  then rebases the absolute URLs embedded in the generated JSON onto that ref, so
  clients stay frozen on a tested snapshot while `main` keeps moving. Missing or
  invalid file falls back to `main`. Bump this file and push to roll a new
  release: clients pick it up with `omarchy plugin update`.
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
- The plugin receives injected properties from the shell: `manifest`, `shell`,
  `pluginRegistry`. Declare `property var manifest: null` to receive them.
  **Do NOT use `manifest.__sourceDir`**: the shell strips it from the manifest
  given to third-party plugins (`publicPluginManifest` in `shell.qml`). Locate
  `manager.sh` / `logo.png` relative to the QML file itself instead:
  `Qt.resolvedUrl(".")` → strip `file://` and the trailing `/` (pattern used
  by the shell's own plugins, e.g. `agents/Panel.qml`).
- Reference sources (read-only): `/usr/share/omarchy/shell/README.md`,
  `/usr/share/omarchy/shell/plugins/image-picker/`,
  `/usr/share/omarchy/shell/plugins/dev-gallery/`,
  `/usr/share/omarchy/shell/services/PluginRegistry.qml`.

## Operational rules

- Themed colors come from `qs.Commons.Color` / `qs.Commons.Style` — never hardcode.
- Remote data flows through `manager.sh` (curl + jq); QML parses TSV output.
- Upstream ref comes from `config.json` (`release`); `manager.sh` builds
  `https://raw.githubusercontent.com/<repo>/<release>` and rebases every embedded
  URL onto it (`rebase_url`). Never hardcode `main` in `manager.sh`.
- Actions (install/remove/set-default) are implemented natively in `manager.sh`
  (sha256 checks, parallel download via background jobs, bg cache refresh) plus
  `omarchy-theme-bg-set` for the default background. There is no `wallpapers.py`
  dependency or cache anymore.
- Install target (local Omarchy): `~/.config/omarchy/backgrounds/<theme>/`.
- Preview thumbnails load directly from the remote `url` in the catalog (the
  `GridView` only instantiates visible delegates, so loading is lazy). No local
  preview cache.

## Application layout

The plugin is one overlay that shows **three screens**, switched by the single
`view` property on `root`:

| `view` | screen | content |
|---|---|---|
| `"themes"` | 1 — theme list | all remote themes (`kind=="theme"`) |
| `"wallpapers"` | 2 — wallpaper list | the wallpapers of the selected theme |
| `"preview"` | 3 — single wallpaper | fullscreen preview + actions |

Every screen is the same skeleton inside the container: **hero header** (icon,
title, meta caption, optional pills/buttons) + `PanelSeparator` + **body** +
dim status caption at the bottom. Each section below covers the functional
anatomy first (what the user sees and does), then the technical implementation
(how it is built).

### 0. STARTUP — lifecycle

**Functional.** Summoning the plugin shows the container with the themes screen
already loading; Esc from the themes screen closes it; re-summoning reloads.

**Technical.**
- `open(payload)` resets the state (`view = "themes"`, `selectedIndex = 0`,
  `cursorActive = true`, `statusText = ""`) then calls `loadThemes()`.
- `close()` only sets `opened = false`; `keepLoaded` keeps the window mounted
  between summons.
- When opened, keyboard focus is forced onto the `PanelKeyCatcher` (`keys`)
  via `Qt.callLater`, so the arrows work immediately.
- Script and logo are resolved **relative to the QML file**, not
  `manifest.__sourceDir` (the shell strips it): `Qt.resolvedUrl(".")` → strip
  `file://` and the trailing `/`.
- Loading any screen is always the same pattern: set `busy = true` + status
  text → start a `Process` → `StdioCollector` parses the TSV lines into a
  `ListModel` and clears `busy` on finish/exit.

### 1. CONTAINER — the overlay chrome

**Functional.** A dim scrim covers the whole screen; a single flat card sits
centered; clicking outside the card closes the overlay.

**Technical.**
- `PanelWindow` fullscreen, `WlrLayer.Overlay`, transparent, keyboard exclusive
  while open.
- Scrim: fullscreen `Rectangle` filled with `Color.menu.scrim`, plus a
  `MouseArea` whose click calls `root.close()`.
- Card: one `BorderSurface` (id `card`) centered; size
  `Math.min(Style.space(N), parent - Style.gapsOut * 2)`; `Color.menu.background`,
  `radius: Style.cornerRadius`, `borderSpec: Border.surfaceSpec("menu", "border",
  …)` (never `border.color`), `padding: Style.spacing.panelPadding`. No inner
  fills: separation is `Style.spacing.md` of empty space + `PanelSeparator`.
- Inside the card, `PanelKeyCatcher` (id `keys`) wraps the content and maps raw
  keys to semantic signals handled by `root`'s state machine (`moveCursor`,
  `activateCursor`, `dismissCursor`, `deleteRequested`, `textKey`).
- Fallback `Keys.onPressed` on the card (the catcher does not accept these, so
  they bubble up): Del/Backspace = remove, PageUp/PageDown = jump a whole
  visible page of tiles (`pageCursor`).
- The two heroes (grid screens and preview) share a pinned height
  `root.heroHeight = Math.max(hero.implicitHeight, previewHero.implicitHeight)`,
  so switching view never shifts the separator and the content below it.

### 2. SCREEN 1 — theme list (`view = "themes"`)

**Functional.** Grid of theme cards: each card is a preview image, the
uppercased theme name, and a "N collections · M wallpapers" line. Header shows the
title, the total theme count and the "remote collections" meta; the footer is
just the dim status caption. Enter/Space or click opens the theme; Esc closes
the plugin.

**Technical.**
- Header: `PanelHero` (id `hero`) — title "Wallpaper manager", `detail` = theme
  count, `meta` = "remote collections", icon = `HeroLogo` with glyph `󰸌`.
- Body: `GridView` `themesGrid` over `themesModel`. Dynamic columns:
  `columnsHint = Math.max(2, Math.floor(width / root.minTileWidth))` with
  `minTileWidth ~ Style.space(190)`; `cellWidth = floor(width / columnsHint)`,
  `cellHeight = cellWidth * 0.9`. Do NOT anchor the delegate (broke grid →
  single column).
- Delegate: `CursorSurface` (bordered, `hasCursor` derived from the shared
  cursor) + `RoundedImage` thumbnail (remote `preview` URL) + name and
  collections/count texts. Hover calls `root.takeCursor(index)`; tap selects the
  theme.
- Data: `loadThemes()` runs `manager.sh themes` → TSV
  `name|title|catalogUrl|collections|count|preview` parsed into `themesModel`.
- Labels use `root.themeLabel(model)`: the dataset `title` uppercased
  (`"tokyo-night"` → `"TOKYO NIGHT"`); slug normalized (`-`/`_` → space) if a
  dataset has no `title`.
- `selectTheme(index)` clears `wallpapersModel` first (the grid delegates
  survive the trip through the themes view; leaving them alive while
  `themeName` changes makes them re-resolve paths against the new theme), sets
  `themeName` / `themeCatalogUrl` and switches to `"wallpapers"`.

### 3. SCREEN 2 — wallpaper list (`view = "wallpapers"`)

**Functional.** Grid of the selected theme's wallpapers: each tile is a
thumbnail, the accent-colored code + name, and installed/default pills. Header
has Back / Refresh / Close buttons and shows the theme name + count. Footer
has Install / Remove / Default on the left and Install all / Remove all on the
right, plus the status caption. Enter or click opens the preview; x/X or Del
removes; d sets default; r refreshes; Esc returns to themes (Esc again closes).

**Technical.**
- Header: `PanelHero` (id `hero`) — title `root.themeName`, `detail` = wallpaper
  count, `meta` = "browse and manage", `trailingControl` = `heroActions`
  (`Ui/Button`s Back/Refresh/Close, `bordered: true`).
- Body: `GridView` (id `grid`) over `wallpapersModel`, same dynamic-columns
  recipe as the themes grid. `current: tile.model.isDefault === "1"` marks the
  theme's default background.
- Thumbnail source priority: local installed file (instant) → remote `preview`
  → full `url`. GridView only instantiates visible delegates, so loading is
  lazy, page by page. This works for thousands of images.
- Tile taps open the preview (same as Enter) — never toggle state, so "set
  default" by mouse lives in the preview. Do NOT put single-tap-selects back on
  the tile.
- Footer: `Column` (id `footer`) — `PanelSeparator`, then the `actionRow`
  (only visible on this view: primary Install/Remove/Default on the left, bulk
  Install all/Remove all on the right), then the dim status caption. No footer
  bar.
- Data: `loadWallpapers()` sets `catalogProc.command` **before**
  `catalogProc.running = true` (bug #2), then parses TSV
  `filename|name|code|url|sha256|installed|is_default|preview`.
- Keyboard: movement is vertical via the computed `colCount` (GridView has no
  `columns` property in Qt 6), and `positionViewAtIndex` is called after every
  move to keep the selection visible.

### 4. SCREEN 3 — single wallpaper preview (`view = "preview"`)

**Functional.** The wallpaper full-res, aspect-fitted and rounded, with a header
(`<code> - <name> (WxH)`, filename or loading/failed feedback in the meta line,
installed/default pills + Back button) and a key-hint caption at the bottom.
h/l/j/k or arrows walk wallpapers, Enter installs, d or double click sets
default, Esc returns to the grid.

**Technical.**
- `previewView` overlays the card (`z: 10`). Header: `PanelHero` (id
  `previewHero`) pinned to `root.heroHeight`. The resolution suffix is appended
  only when `previewView.shown` (the visible image is the selected item's), so a
  name is never paired with the previous resolution. The code is inline in the
  title — no `detail` pill.
- Double buffer: hidden `nextImage` preloads the target (`nextSource`: local
  file if installed, else remote `url`); the swap to `previewImage` happens only
  on `Image.Ready`, so navigating never shows a blank screen. On load error the
  previous wallpaper stays up and the meta reports `FAILED TO LOAD <file>`. No
  spinner.
- Aspect-fit: the `fitted` rect is computed from the natural size
  (`previewView.fittedSize`); the rounded mask (`MultiEffect`) is sized exactly
  to the fitted rect, so the corners stay rounded even when the wallpaper
  letterboxes.
- Input: `TapHandler` — a tap outside the image goes back, a double tap on the
  image sets default (`previewView.onImage(point)` routes the taps; the single
  tap on the image is inert, being the first half of the double tap).
  `previewNext(delta)` walks the selection; Esc = `closePreview()`.

### 5. Technology / data flow

- **Language**: UI is QML (Qt 6 Quick + Quickshell); remote data and actions are
  bash (`manager.sh`, curl + jq + sha256); the default background is set with
  `omarchy-theme-bg-set`.
- **Imports**: `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `QtQuick`,
  `QtQuick.Effects`, `qs.Commons`, `qs.Ui`.
- **Shell ⇄ QML protocol**: TSV lines on stdout, one record per line with a
  fixed column list; QML splits on `\t` and appends each row to a `ListModel`
  (`themesModel`, `wallpapersModel`).
- **State** lives on `root`: `view`, `selectedIndex`, `cursorActive`, `busy`,
  `statusText`. Mouse and keyboard share one cursor through `CursorSurface`
  (visuals from `hasCursor` / `current`, never `containsMouse`), so exactly one
  tile is ever highlighted.
- **Actions**: `actionInstall` / `actionRemove` / `actionSetDefault` /
  `actionInstallAll` / `actionRemoveAll` all funnel into `runAction(args)` →
  `actionProc`; on exit the list refreshes automatically.
- **Inline components**: `RoundedImage` (MultiEffect mask + `Style.cornerRadius`,
  `clip: true` is not enough), `HeroLogo` (logo.png with a nerd-font glyph
  fallback), `Pill` (state pills, transparent fill + flat tinted border).
- **Lint**: `qmllint -I <dir containing a `qs` symlink to
  /usr/share/omarchy/shell>`. The residual `unqualified` /
  `missing-property` warnings on `Style.spacing.*`, `Style.font.*`,
  `Color.menu.*` are unavoidable (the shell's own code produces them).

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
- Corner rounding must always come from `Style.cornerRadius` (mirrors
  Hyprland's `decoration:rounding`), never a hardcoded number. Images need the
  `RoundedImage` inline component (`layer.effect: MultiEffect` + mask) because
  `clip: true` on an `Image` only clips rectangularly.

## Bugs fixed along the way (do not reintroduce)

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

To roll a new upstream snapshot: bump `release` in `config.json`, commit and push.
Installed clients get it with `omarchy plugin update` (a fast-forward of the git
checkout, validated and rescanned by the shell).

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