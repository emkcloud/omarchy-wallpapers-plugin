# AGENTS.md

Guidelines for AI agents working on this repository. Read this file before making any changes.

## Project overview

Omarchy shell plugin: **`emkcloud.wallpaper-manager`**. It browses the remote
wallpaper collection of the `emkcloud/omarchy-wallpapers` repo and manages the
local installation of its wallpapers inside Omarchy (install / remove /
set-default), theme by theme.

## Repository layout

- `manifest.json` — plugin manifest (id `emkcloud.wallpaper-manager`, kind
  `overlay`, entry point `interface/WallpaperManager.qml`). Validated by
  `omarchy plugin validate`.
- `interface/` — the QML UI. Kept in a subdirectory so root holds only plugin
  metadata and config; the entry point is exactly one level deep.
- `interface/WallpaperManager.qml` — the UI view + thin controller: state,
  `Process`/`FileView` and the three screens. Imports `"components"` and
  `"js/Model.js" as Model`.
- `interface/js/` — JavaScript logic modules, kept out of the QML files.
- `interface/js/Model.js` — pure logic, no QML ids/state: TSV parsing,
  `themeLabel`, cursor arithmetic, key mapping, status text, `parsePaths`.
- `interface/components/` — local QML atoms shared by the screens:
  `RoundedImage.qml` (rounded image via MultiEffect mask), `HeroLogo.qml`
  (brand mark + glyph fallback), `Pill.qml` (state pill).
- `config/` — plugin config, kept out of the repo root.
- `config/config.json` — plugin config, read by both `manager.sh` and the QML.
  - `repo` / `release` — pin the upstream snapshot. `manager.sh` reads the
    `release` (a tag), builds every upstream URL from it, then rebases the
    absolute URLs embedded in the generated JSON onto that ref, so clients stay
    frozen on a tested snapshot while `main` keeps moving. Missing or invalid
    falls back to `main`. Bump `release` and push to roll a new release: clients
    pick it up with `omarchy plugin update`.
  - `paths` — `scripts`, `assets`, `logo`, `datasets`, all relative to the
    plugin root, so the layout is data-driven. The QML resolves `scriptPath` /
    `logoPath` from these (silent fallback to the shipped layout if the file is
    missing/invalid); `manager.sh` reads `paths.datasets` for its cache dir.
- `scripts/` — helper scripts, kept out of the repo root.
- `scripts/manager.sh` — bash helper: builds the dataset cache (see `datasets/`
  below), computes local install state, and runs install/remove/set-default
  natively (curl + jq + sha256). Talks to the QML via TSV on stdout. Reads
  `config/config.json` from the plugin root (`SCRIPT_DIR/../config/config.json`).
- `scripts/developer.sh` — dev-only helper (`link` / `unlink`): installs this
  checkout as `emkcloud.wallpaper-manager-developer` via symlinks. See *Local
  development*.
- `assets/` — local plugin assets. Scalable by kind; today only
  `assets/images/logo.png` exists, but future icons/fonts belong here too. This
  is **not** the upstream wallpaper repo.
- `assets/images/logo.png` — emkcloud brand mark (the org GitHub avatar), used
  as the hero icon. The original near-black backdrop (`#010409`, rounded
  square) has been made **transparent** so the mark sits on
  `Color.menu.background`: alpha is derived from the max RGB channel
  (`-separate -evaluate-sequence Max -level 4%,85%`), which keeps the three
  brand colors bit-exact (`#155DFC`, `#E12AFB`, `#05DF72`) and preserves the
  anti-aliased edges. Do NOT re-flatten it on black.
- `datasets/` — runtime cache of the pinned upstream dataset, gitignored except
  for the tracked `.gitkeep`. `manager.sh` fills it on the **first run**:
  `datasets.json` plus every theme catalog (eager warm-up; a catalog that fails
  is fetched again on demand), tagged by a `.release` marker. `omarchy plugin
  update` merges with `git merge --ff-only`, so ignored files survive the update:
  the marker is what forces a wipe + re-download when `release` changes. One
  release at a time.
- `datasets/.gitkeep` — keeps the otherwise empty cache dir in git.
- `.gitignore` — `datasets/*` plus `!datasets/.gitkeep`.
- `images/`, `masters/` — never here. The wallpapers live in the separate repo
  `emkcloud/omarchy-wallpapers`.
- `README.md` — user-facing docs (install, usage, requirements).
- `LICENSE` — project license.
- `AGENTS.md` — this file.

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
  everything relative to the QML file instead, then walk up to the plugin root:
  the QML sits one level deep (`interface/`), so `Qt.resolvedUrl("..")` → strip
  `file://` and the trailing `/` gives the root (same pattern used by the
  shell's own plugins, e.g. `agents/Panel.qml`), then join the relative paths
  from `config/config.json`.
- Reference sources (read-only): `/usr/share/omarchy/shell/README.md`,
  `/usr/share/omarchy/shell/plugins/image-picker/`,
  `/usr/share/omarchy/shell/plugins/dev-gallery/`,
  `/usr/share/omarchy/shell/services/PluginRegistry.qml`.

## Code map — `interface/WallpaperManager.qml`

The plugin is one view file plus, since the split, a pure-logic JS module and a
`components/` folder for the shared QML atoms. `WallpaperManager.qml` is written
**logic-first, UI-last**: state, imports and the script-driven processes come
before the `PanelWindow`. This is the source order and where each concern lives:

| Source order | ids / functions | Role |
|---|---|---|
| paths | `pluginRoot`, `configFile`, `pluginPaths`, `scriptPath`, `logoPath` | resolve the layout from `config/config.json` `paths`, from the plugin root |
| state | `view`, `themeName`, `themeCatalogUrl`, `selectedIndex`, `cursorActive`, `busy`, `statusText`, `themesModel`, `wallpapersModel` | single source of truth |
| tokens | `foreground`, `background`, `accent`, `urgent`, `scrim`, `dim`, `borderSpec`, `contentMargin`, `contentSpacing`, `minTileWidth`, `themeTileWidth`, `tileGap`, `tileInset`, `fontFamily`, `heroHeight` | `Color.menu.*` / `Style.*` aliases |
| components | `RoundedImage`, `HeroLogo`, `Pill` | atoms in `components/`, shared by both grids and the preview |
| startup / termination | `open()`, `close()`, `onOpenedChanged` | summon / hide |
| cursor state machine | `activeGrid`, `activeCount`, `stepCursor`, `moveCursor`, `pageCursor`, `activateCursor`, `dismissCursor`, `handleTextKey`, `takeCursor` | one `selectedIndex` driven by mouse *and* keyboard |
| actions | `currentItem`, `showPreview`, `closePreview`, `previewNext`, `actionInstall`, `actionRemove`, `actionSetDefault`, `actionInstallAll`, `actionRemoveAll`, `runAction` | user operations |
| processes | `themesProc`, `catalogProc`, `actionProc` | run `manager.sh`, parse TSV |
| overlay UI | `panel`, `card`, `keys`, `hero`, `heroRule`, `themesGrid`, `grid`, `footer`, `previewView` | the chrome and the three screens |

Pure helpers live in `interface/js/Model.js` (imported as `Model`): `parseThemes`,
`parseCatalog`, `themeLabel`, `stepIndex`, `textAction`, `themesStatus`,
`catalogStatus`, `parsePaths`. Keep it free of QML ids/state — the view owns the
models, the processes and `selectedIndex`.

The steps below walk the same file in **runtime order**, not source order.

## Application layout

The plugin is one overlay that shows **three screens**, switched by the single
`view` property on `root`:

| `view` | screen | content |
|---|---|---|
| `"themes"` | theme list | all remote themes (`kind=="theme"`) |
| `"wallpapers"` | wallpaper list | the wallpapers of the selected theme |
| `"preview"` | single wallpaper | fullscreen preview + actions |

Every screen is the same skeleton inside the container: **hero header** (icon,
title, meta caption, optional pills/buttons) + `PanelSeparator` + **body** +
dim status caption at the bottom. Each step covers the functional anatomy first
(what the user sees and does), then the technical implementation and its code
anchors. Cross-cutting rules — selection, keyboard, buttons, pills, status,
rounding — live once in the **Design canon**; the steps point there instead of
repeating them.

### 1. Startup application — `open`

**Functional.** Summoning the plugin shows the container with the themes screen
already loading.

**Technical.**
- `open(payload)` resets the state (`view = "themes"`, `selectedIndex = 0`,
  `cursorActive = true`, `statusText = ""`) then calls `loadThemes()`.
- When opened, keyboard focus is forced onto the `PanelKeyCatcher` (`keys`) via
  `Qt.callLater`, so the arrows work immediately.
- Script and logo are resolved from the **plugin root** (not
  `manifest.__sourceDir`, which the shell strips): `Qt.resolvedUrl("..")` →
  strip `file://` and the trailing `/`, then join the relative paths from
  `config/config.json` (`paths`).
- Loading any screen follows one pattern: set `busy = true` + status text →
  start a `Process` → `StdioCollector` parses the TSV rows into a `ListModel`
  and clears `busy` on finish/exit. See step 6.

### 2. Container — the overlay chrome

**Functional.** A dim scrim covers the whole screen; a single flat card sits
centered; clicking outside the card closes the overlay.

**Technical.**
- `PanelWindow` (`panel`) fullscreen, `WlrLayer.Overlay`, transparent, keyboard
  exclusive while open.
- Scrim: fullscreen `Rectangle` filled with `Color.menu.scrim`, plus a
  `MouseArea` whose click calls `root.close()`.
- Card: one `BorderSurface` (`card`) centered; size
  `Math.min(Style.space(N), parent - Style.gapsOut * 2)`; `Color.menu.background`,
  `radius: Style.cornerRadius`, `borderSpec: Border.surfaceSpec("menu", "border",
  …)` (never `border.color`), `padding: Style.spacing.panelPadding`. No inner
  fills: separation is `Style.spacing.md` of empty space + `PanelSeparator`.
- Inside the card, `PanelKeyCatcher` (`keys`) wraps the content and maps raw
  keys to semantic signals handled by `root`'s state machine (`moveCursor`,
  `activateCursor`, `dismissCursor`, `deleteRequested`, `textKey`).
- Fallback `Keys.onPressed` on the card (the catcher does not accept these, so
  they bubble up): Del/Backspace = remove, PageUp/PageDown = jump a whole
  visible page of tiles (`pageCursor`).
- The two heroes (grid screens and preview) share a pinned height
  `root.heroHeight = Math.max(hero.implicitHeight, previewHero.implicitHeight)`,
  so switching view never shifts the separator and the content below it.

### 3. Theme list (`view = "themes"`)

**Functional.** Grid of theme cards: each card is a preview image, the
uppercased theme name, and a "N collections · M wallpapers" line. Header shows
the title, the total theme count, the "remote collections" meta and
Refresh/Close buttons (Back is hidden on this view). The footer is just the dim
status caption. Enter/Space or click opens the theme; Esc closes the plugin.

**Technical.**
- Header: `PanelHero` (`hero`) — title "Wallpaper manager", `detail` = theme
  count, `meta` = "remote collections", icon = `HeroLogo` with glyph `󰸌`,
  `trailingControl` = `heroActions` (the same Back/Refresh/Close row as step 4,
  where Back is `visible` only on the wallpapers view).
- Body: `GridView` `themesGrid` over `themesModel`. Themes are few, so tiles
  are wider than the wallpaper ones: dynamic columns
  `columnsHint = Math.max(2, Math.floor(width / root.themeTileWidth))` with
  `themeTileWidth ~ Style.space(340)`; `cellWidth = floor(width / columnsHint)`,
  `cellHeight = cellWidth * 0.72`. Do NOT anchor the delegate (broke grid →
  single column).
- Delegate: `CursorSurface` (bordered, `hasCursor` derived from the shared
  cursor) + `RoundedImage` thumbnail (remote `preview` URL) + name and
  collections/count texts. Hover calls `root.takeCursor(index)`; tap selects the
  theme.
- Data: `loadThemes()` runs `manager.sh themes` (TSV columns in step 6) into
  `themesModel`.
- Labels use `root.themeLabel(model)`: the dataset `title` uppercased
  (`"tokyo-night"` → `"TOKYO NIGHT"`); slug normalized (`-`/`_` → space) if a
  dataset has no `title`.
- `selectTheme(index)` clears `wallpapersModel` first (the grid delegates
  survive the trip through the themes view; leaving them alive while
  `themeName` changes makes them re-resolve paths against the new theme), sets
  `themeName` / `themeCatalogUrl` and switches to `"wallpapers"`.

### 4. Wallpaper list (`view = "wallpapers"`)

**Functional.** Grid of the selected theme's wallpapers: each tile is a
thumbnail, the accent-colored code + name, and installed/default pills. Header
has Back / Refresh / Close buttons and shows the theme name + count. Footer has
Install / Remove / Default on the left and Install all / Remove all on the
right, plus the status caption. Enter or click opens the preview; x/X or Del
removes; d sets default; r refreshes; Esc returns to themes (Esc again closes).

**Technical.**
- Header: `PanelHero` (`hero`) — title `root.themeName`, `detail` = wallpaper
  count, `meta` = "browse and manage", `trailingControl` = `heroActions`
  (`Ui/Button`s Back/Refresh/Close, `bordered: true`).
- Body: `GridView` (`grid`) over `wallpapersModel`, same dynamic-columns recipe
  as the themes grid. `current: tile.model.isDefault === "1"` marks the theme's
  default background.
- Thumbnail source priority: local installed file (instant) → remote `preview`
  → full `url`. GridView only instantiates visible delegates, so loading is
  lazy, page by page. This works for thousands of images.
- Tile taps open the preview (same as Enter) — never toggle state, so "set
  default" by mouse lives in the preview. Do NOT put single-tap-selects back on
  the tile.
- Footer: `Column` (`footer`) — `PanelSeparator`, then the `actionRow` (only
  visible on this view: primary Install/Remove/Default on the left, bulk Install
  all/Remove all on the right), then the dim status caption. No footer bar.
- Data: `loadWallpapers()` sets `catalogProc.command` **before**
  `catalogProc.running = true` (bug #2), then parses the TSV columns in step 6
  into `wallpapersModel`.
- Keyboard: movement is vertical via the computed `colCount` (GridView has no
  `columns` property in Qt 6), and `positionViewAtIndex` is called after every
  move to keep the selection visible.

### 5. Single wallpaper preview (`view = "preview"`)

**Functional.** The wallpaper full-res, aspect-fitted and rounded, with a header
(`<code> - <name> (WxH)`, filename or loading/failed feedback in the meta line,
installed/default pills + Back button) and a key-hint caption at the bottom.
h/l/j/k or arrows walk wallpapers, Enter installs, d or double click sets
default, Esc returns to the grid.

**Technical.**
- `previewView` overlays the card (`z: 10`). Header: `PanelHero`
  (`previewHero`) pinned to `root.heroHeight`. The resolution suffix is appended
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

### 6. Data flow & actions

- **Language**: UI is QML (Qt 6 Quick + Quickshell); remote data and actions are
  bash (`manager.sh`, curl + jq + sha256); the default background is set with
  `omarchy-theme-bg-set`.
- **Imports**: `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `QtQuick`,
  `QtQuick.Effects`, `qs.Commons`, `qs.Ui`.
- **Dataset cache**: the upstream JSON is cached in `paths.datasets` and read
  locally. On the first run `ensure_datasets()` downloads `datasets.json` and
  then warms every catalog (`prefetch_catalogs`, best-effort); a missing catalog
  is retried by `ensure_catalog(theme)`. The `.release` marker ties the cache to
  the pinned ref: when `release` changes the cache is wiped and rebuilt. Once
  cached, listing needs no network; wallpapers, previews and set-default stay
  remote. A failed `datasets.json` exits non-zero (no live fallback).
- **`manager.sh` command surface**:

  | command | args | stdout (TSV) |
  |---|---|---|
  | `themes` | — | `name  title  catalogUrl  collections  count  preview` |
  | `catalog` | `<theme> <catalog-url>` | `filename  name  code  url  sha256  installed  isDefault  preview` (local catalog; the URL arg is only a fallback) |
  | `install` | `<theme> [selector]` | human text; no selector = all, selector matches id/name/code/filename |
  | `remove` | `<theme> [selector]` | human text; same selector matching |
  | `set-default` | `<theme> <filename> <url>` | human text; downloads if missing then `omarchy-theme-bg-set` |

  (`installed` / `isDefault` are `"0"`/`"1"`; `manager.sh` prints the default
  column as `current`, the QML model names it `isDefault`.)
- **Shell ⇄ QML protocol**: TSV lines on stdout, one record per line with the
  fixed columns above; QML splits on `\t` and appends each row to a `ListModel`
  (`themesModel`, `wallpapersModel`).
- **State** lives on `root`: `view`, `selectedIndex`, `cursorActive`, `busy`,
  `statusText`. Mouse and keyboard share one cursor through `CursorSurface`
  (visuals from `hasCursor` / `current`, never `containsMouse`), so exactly one
  tile is ever highlighted.
- **Actions**: `actionInstall` / `actionRemove` / `actionSetDefault` /
  `actionInstallAll` / `actionRemoveAll` all funnel into `runAction(args)` →
  `actionProc`; on exit the list refreshes automatically.
- **Local components**: `components/RoundedImage.qml` (MultiEffect mask +
  `Style.cornerRadius`, `clip: true` is not enough), `components/HeroLogo.qml`
  (assets/images/logo.png with a nerd-font glyph fallback),
  `components/Pill.qml` (state pills, transparent fill + flat tinted border).

### 7. Termination application — `close`

**Functional.** Esc from the themes screen (or a click on the scrim) hides the
overlay; nothing is torn down, so re-summoning is instant and reloads the themes
list.

**Technical.**
- `close()` only sets `opened = false`; there is no teardown because
  `keepLoaded: true` keeps the window mounted between summons.
- The scrim `MouseArea` and the Close button both call `root.close()`; Esc goes
  through the cursor state machine (`dismissCursor()` → `close()` on the themes
  view, a step back on the others).

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
  buttons. The icon is the **emkcloud logo** (`assets/images/logo.png`, the
  org avatar) via the local `components/HeroLogo.qml`: a `RoundedImage`
  `Style.font.displayLarge` wide, same in every view, with the old nerd-font
  glyphs (`󰸌` themes, `` wallpapers) as fallback if the file cannot be
  resolved. It is the only image allowed in this repo.
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
  `components/RoundedImage.qml` (`layer.effect: MultiEffect` + mask) because
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

Two installs can coexist, distinguished by id:

- **Developer** — `emkcloud.wallpaper-manager-developer`: symlinks back to this
  checkout, created by `scripts/developer.sh link`. Edit the repo, then
  `omarchy restart shell`.
- **Official** — `emkcloud.wallpaper-manager`: a real git checkout, installed
  with `omarchy plugin add … --enable --yes`; use it to test add/update exactly
  as a user would. `scripts/developer.sh` never touches it.

```bash
bash scripts/developer.sh link     # create/enable/summon the dev plugin
bash scripts/developer.sh unlink   # remove it
```

`link` generates the dev `manifest.json` from the official one (only `.id` and
`.name` change) and symlinks `interface`, `scripts`, `config`, `assets`,
`datasets`. `unlink` refuses to delete anything without the `.dev-wrapper`
marker.

> ⚠️ **Symlink vs hot-reload.** The shell watches `~/.config/omarchy/plugins/`
> with inotify, which does **not** follow symlinks. The dev wrapper is symlinks,
> so edits are NOT hot-reloaded: after changing QML, restart the shell:
> `omarchy restart shell`, then re-summon. (For true hot-reload, copy the files
> into `~/.config/omarchy/plugins/<id>/` instead of symlinking.)

`manager.sh` resolves its own path with `readlink -f`, so even through the dev
wrapper the dataset cache still lands in this repo's `datasets/`.

Lint: `qmllint -I <dir containing a `qs` symlink to /usr/share/omarchy/shell>`.
The residual `unqualified` / `missing-property` warnings on `Style.spacing.*`,
`Style.font.*`, `Color.menu.*` are unavoidable (the shell's own code produces
them).

## Distribution

The repo root is the plugin: `omarchy plugin add
https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes`.
Keep `manifest.json` at the repo root (required by `omarchy plugin add`).

To roll a new upstream snapshot: bump `release` in `config/config.json`, commit and push.
Installed clients get it with `omarchy plugin update` (a fast-forward of the git
checkout, validated and rescanned by the shell).

## Notes for the agent

- The user speaks Italian: respond and comment in Italian.
- **UI language**: all user-facing strings in `interface/WallpaperManager.qml` are in
  **English** (decision 2026-09-02). Multilingual support is TBD — do not
  introduce a translation framework yet; just keep strings in English until
  the user decides how to handle i18n.
- Commit messages: concise (short and to the point).
- **Do NOT verify the UI with screenshots** (`grim` + reading the image): it is
  slow and expensive. After restarting the shell, just ask the user to look at
  the overlay and report the visual result.
