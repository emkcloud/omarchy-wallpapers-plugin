# AGENTS.md

Guidelines for AI agents working on this repository. Read this file before making any changes.

## Project overview

Omarchy shell plugin: **`emkcloud.wallpaper-manager`**. It browses the remote
wallpaper collection of the `emkcloud/omarchy-wallpapers` repo and manages the
local installation of its wallpapers inside Omarchy (install / remove /
set-default), theme by theme.

## Repository layout

- `manifest.json` — plugin manifest (id `emkcloud.wallpaper-manager`, kinds
  `overlay` + `bar-widget`). Entry points: `interface/WallpaperManager.qml`
  (overlay) and `interface/BarLauncher.qml` (bar launcher). Validated by
  `omarchy plugin validate`.
- `interface/` — the QML UI. Kept in a subdirectory so root holds only plugin
  metadata and config; the entry points are exactly one level deep.
- `interface/WallpaperManager.qml` — the UI view + thin controller: state,
  `Process`/`FileView` and the three screens. Imports `"components"` and
  `"js/Model.js" as Model`.
- `interface/BarLauncher.qml` — bar launcher: one click toggles this plugin's own
  overlay via the scoped shell facade (`bar.shell.toggle(pluginId, …)`). The
  developer install shares the file but gets a distinct glyph from its
  `-developer` moduleName.
- `interface/js/` — JavaScript logic modules, kept out of the QML files.
- `interface/js/Model.js` — pure logic, no QML ids/state: TSV parsing,
  `themeLabel`, cursor arithmetic, key mapping, status text, `parsePaths`.
- `interface/components/` — local QML atoms shared by the screens:
  `RoundedImage.qml` (rounded image via MultiEffect mask), `HeroLogo.qml`
  (brand mark + glyph fallback), `Pill.qml` (state pill), `ThemeProgress.qml`
  (install progress of one theme: caption + percentage + accent bar),
  `SearchField.qml` (shared search box with caret and clear X),
  `RunningOverlay.qml` (opaque scrim + accent spinner + pulsing caption while
  an install/remove runs, shared by the themes detail pane and the preview).
- `config/` — plugin config, kept out of the repo root.
- `config/config.json` — plugin config, read by both `manager.sh` and the QML.
  - `repo` / `release` — pin the upstream snapshot. `manager.sh` reads the
    `release` (a tag), builds every upstream URL from it, then rebases the
    absolute URLs embedded in the generated JSON onto that ref, so clients stay
    frozen on a tested snapshot while `main` keeps moving. Missing or invalid
    falls back to `main`. Bump `release` and push to roll a new release: clients
    pick it up with `omarchy plugin update`.
  - `paths` — `scripts`, `assets`, `logo`, `datasets`. The first three are
    relative to the plugin root; `datasets` is now relative to the **app cache**
    (`~/.cache/omarchy/<pluginId>`), so the layout is data-driven. The QML
    resolves `scriptPath` / `logoPath` from these (silent fallback to the
    shipped layout if the file is missing/invalid); `manager.sh` reads
    `paths.datasets` for its cache dir (an absolute path is honoured as-is).
- `scripts/` — helper scripts, kept out of the repo root.
- `scripts/manager.sh` — bash helper: builds the dataset cache (see `datasets/`
  below), computes local install state, and runs install/remove/set-default
  natively (curl + jq + sha256). Talks to the QML via TSV on stdout. Reads
  `config/config.json` from the plugin root (`SCRIPT_DIR/../config/config.json`).
- `scripts/developer.sh` — dev-only helper (`link` / `unlink`): installs this
  checkout as `emkcloud.wallpaper-manager-developer` via symlinks. See *Local
  development*.
- `assets/` — local plugin assets. Scalable by kind; today
  `assets/images/logo.png` (hero icon) and `assets/images/banner.png` (README
  banner) exist, but future icons/fonts belong here too. This is **not** the
  upstream wallpaper repo.
- `assets/images/banner.png` — the README banner (2000×1125), shown under the
  title. Repo-only: not referenced by the plugin at runtime.
- `assets/images/logo.png` — emkcloud brand mark (the org GitHub avatar), used
  as the hero icon. The original near-black backdrop (`#010409`, rounded
  square) has been made **transparent** so the mark sits on
  `Color.menu.background`: alpha is derived from the max RGB channel
  (`-separate -evaluate-sequence Max -level 4%,85%`), which keeps the three
  brand colors bit-exact (`#155DFC`, `#E12AFB`, `#05DF72`) and preserves the
  anti-aliased edges. Do NOT re-flatten it on black.
- `datasets/` — empty placeholder kept only so a relative `paths.datasets`
  still has a (gitignored) home in the repo. The real cache lives in the app
  cache, **outside** the plugin directory: the shell watches
  `~/.config/omarchy/plugins/` and hot-reloads a plugin whenever a file under it
  changes, so caching datasets inside the plugin closed the overlay on every
  catalog fetch. `.gitignore` ignores `datasets/*` except `.gitkeep`.
- Dataset cache (`~/.cache/omarchy/<pluginId>/datasets/`) — runtime cache of the
  pinned upstream dataset. `manager.sh` fills it on the **first run**:
  `datasets.json` plus every theme catalog (eager warm-up; a catalog that fails
  is fetched again on demand), tagged by a `.release` marker. The marker forces
  a wipe + re-download when `release` changes. One release at a time.
- `images/`, `masters/` — never here. The wallpapers live in the separate repo
  `emkcloud/omarchy-wallpapers`.
- `README.md` — user-facing docs (install, usage, requirements).
- `LICENSE` — project license.
- `AGENTS.md` — this file.

## Plugin contract (Omarchy)

- Plugin id must NOT use the reserved `omarchy.*` namespace.
- `kinds` supported: `bar-widget`, `panel`, `overlay`, `menu`, `service`, `bar`.
- This plugin pairs two kinds: `overlay` (the three-screen UI) and
  `bar-widget` (the launcher). Enabling a `bar-widget` inserts it into
  `bar.layout[barWidget.defaultSection]`, which is also what marks the plugin
  enabled — so the bar icon is the standard way users open it, no CLI needed.
  A plugin already enabled as a plain overlay must be disabled + re-enabled to
  pick up the bar entry.
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
| state | `view`, `themeName`, `themeCatalogUrl`, `selectedIndex`, `lastThemeIndex`, `cursorActive`, `busy`, `statusText`, `filterText`, `wallpaperFilterText`, `searching`, `themesModel`, `themesDisplayModel`, `wallpapersModel`, `wallpapersDisplayModel` | single source of truth |
| tokens | `foreground`, `background`, `accent`, `urgent`, `scrim`, `dim`, `borderSpec`, `contentMargin`, `contentSpacing`, `minTileWidth`, `themeTileWidth`, `tileGap`, `tileInset`, `fontFamily`, `heroHeight` | `Color.menu.*` / `Style.*` aliases |
| components | `RoundedImage`, `HeroLogo`, `Pill`, `ThemeProgress`, `SearchField` | atoms in `components/`, shared by both grids and the preview |
| startup / termination | `open()`, `close()`, `onOpenedChanged` | summon / hide |
| cursor state machine | `activeGrid`, `activeCount`, `stepCursor`, `moveCursor`, `pageCursor`, `activateCursor`, `dismissCursor`, `handleTextKey`, `takeCursor` | one `selectedIndex` driven by mouse *and* keyboard |
| actions | `currentItem`, `showPreview`, `closePreview`, `previewNext`, `actionInstall`, `actionRemove`, `actionSetDefault`, `actionInstallAll`, `actionRemoveAll`, `runAction` | user operations |
| processes | `themesProc`, `catalogProc`, `actionProc` | run `manager.sh`, parse TSV |
| overlay UI | `panel`, `card`, `keys`, `hero`, `heroRule`, `themesGrid`, `grid`, `footer`, `previewView` | the chrome and the three screens |

Pure helpers live in `interface/js/Model.js` (imported as `Model`): `parseThemes`,
`parseCatalog`, `themeLabel`, `ucfirst`, `formatSize`, `themeMatches`,
`wallpaperMatches`, `stepIndex`, `textAction`, `themesStatus`, `catalogStatus`,
`parsePaths`. Keep it free of QML ids/state —
the view owns the models, the processes and `selectedIndex`.

The steps below walk the same file in **runtime order**, not source order.

## Application layout

The plugin ships two entry points: the overlay described below, and
`interface/BarLauncher.qml` (a `WidgetButton` that toggles that overlay from the
bar). Both share the same code; the bar icon is just a launcher.

The overlay shows **three screens**, switched by the single `view` property on
`root`:

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
thumbnail with the accent-colored code + name overlaid on a translucent band
at its bottom (no extra row). Header
has Back / Refresh / Close buttons and shows the theme name + count. Footer has
three sections on one row — Install / Remove on the left, the theme's progress
in the middle, Install all / Remove all on the right. Enter or click opens the
preview; x/X or Del removes; d sets default; r refreshes; Esc returns to themes
(Esc again closes).

**Technical.**
- Header: `PanelHero` (`hero`) — title `"Theme / " +
  Model.ucfirst(root.themeName)`, no `detail` pill, `meta` = "browse and manage
  wallpapers", `trailingControl` = `heroActions` (`Ui/Button`s
  Back/Refresh/Close, `bordered: true`).
- Body: `GridView` (`grid`) over `wallpapersModel`, same dynamic-columns recipe
  as the themes grid. `current: tile.model.isDefault === "1"` marks the theme's
  default background.
- Thumbnail source priority: local installed file (instant) → remote `preview`
  → full `url`. GridView only instantiates visible delegates, so loading is
  lazy, page by page. This works for thousands of images.
- Tile overlays mirror the preview, scaled with the thumbnail: the installed
  disc top-right (accent when on disk, dim otherwise; `disc = clamp(width *
  0.075, Style.space(9), Style.space(16))`) and the `DEFAULT` `Pill` top-left on
  the theme's default wallpaper. The shared `components/Pill.qml` exposes
  `labelPixelSize` / `hPadding` / `vPadding` so it can shrink to thumbnail size.
- Tile taps open the preview (same as Enter) — never toggle state, so "set
  default" by mouse lives in the preview. Do NOT put single-tap-selects back on
  the tile.
- Footer: `Column` (`footer`) — `PanelSeparator`, then the `actionRow` (only
  visible on this view) with three sections on one row: primary Install/Remove
  on the left, `ThemeProgress` (`wallpapersProgress`, the open theme's install
  bar) in the middle, bulk Install all/Remove all on the right. No status
  caption and no footer bar, so the footer keeps the same height as the themes
  one. The middle section is fenced by two vertical rules: one at
  `themeListPane.width - 1` (continuing the sidebar border, so Install/Remove
  spans the sidebar's width) and one before the bulk buttons. "Set default"
  stays on the preview (double click / `d`), so it is not in the footer.
- Data: `loadWallpapers()` sets `catalogProc.command` **before**
  `catalogProc.running = true` (bug #2), then parses the TSV columns in step 6
  into `wallpapersModel`.
- Keyboard: movement is vertical via the computed `colCount` (GridView has no
  `columns` property in Qt 6), and `positionViewAtIndex` is called after every
  move to keep the selection visible.

### 5. Single wallpaper preview (`view = "preview"`)

**Functional.** The wallpaper full-res, full-bleed (no padding, no rounding),
with a header (`<Theme> / <code> - <name>` as the title, `<file> · <size MB>` or
failed feedback in the meta line, an info pill (`<resolution> | <WxH>`) then a
`Download` button, before Back/Close) and a footer on one row — Install
and Uninstall on the left,
the open theme's progress in the middle, the `<enter> install` hint on the
right. `Download` saves the full-res file to a folder picked with Omarchy's own
`omarchy-file-select` (portal chooser; the overlay is hidden while it runs).
Uninstall is tinted `Color.urgent` (the theme's red — no fixed danger color),
border included. Install is disabled when the wallpaper is already installed and
Uninstall when it is not (and `i`/`u`/Enter become no-ops), driven by
`currentInstalled`; a dot overlaid top-right of the image (on a dark disc, like
the theme rows) shows the state. While an action runs this screen accepts only
Esc (which stops the process): navigation, Download/Back/Close and the other
keys are disabled, like the themes screen's action rule.
A thumbnail navigator (filmstrip) sits bottom-right over the image and follows
the selection. h/l/j/k or arrows walk wallpapers, Enter installs, `d` or double
click toggles the theme default (sets it, installing the file first if needed;
if it already is the default, clears it back to the theme's own background) and
shows a `DEFAULT` pill before the dot; Esc returns to the grid.

**Technical.**
- `previewView` overlays the card (`z: 10`). Header: `PanelHero`
  (`previewHero`) pinned to `root.heroHeight`. The title is
  `<theme> / <collection> / <name>` (all `ucfirst`, collection dropped when
  empty); the meta carries the filename plus `Model.formatSize(sizeBytes)`, or
  the failed feedback. No `detail` pill.
- Full-bleed: `previewImageFrame` cancels the card padding (negative margins) so
  the image touches the border's inner edge and starts right under the rule; no
  rounded mask, `clip: true` only. The footer is a sibling of `previewView`, so
  the frame cannot anchor to `footer.top`: it anchors bottom to its parent and
  reserves `footer.height` as the bottom margin.
- Double buffer: hidden `nextImage` preloads the target (`nextSource`: local
  file if installed, else remote `url`); the swap to `previewImage` happens only
  on `Image.Ready`, so navigating never shows a blank screen. On load error the
  previous wallpaper stays up and the meta reports `failed to load`. No spinner.
- Fill: `previewImage` uses `Image.PreserveAspectCrop`, so the wallpaper covers
  the whole frame (like it would on the desktop) instead of letterboxing.
- Footer first rule is at `themeListPane.width - 1` (the themes screen's
  master/detail divider), so the Install/Uninstall section spans the sidebar's
  width and the progress starts where the detail pane does.
- Path pill: bottom-left of the image, `~`-shortened install path
  (`currentInstallPath`), theme-background fill + border, centred with the
  filmstrip; shown whether or not the file is installed.
- Navigator: `previewStrip` (`ListView` horizontal, ~7 cells) bottom-right;
  `currentIndex` follows `root.selectedIndex` and `positionStrip()` centres it
  (clamped to the ends, so the first cell is flush left and the last flush right,
  no blank gutter), animated by a `Behavior on contentX`.
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
- **Dataset cache**: the upstream JSON is cached in `paths.datasets` (the app
  cache, outside the watched plugin dir) and read
  locally. On the first run `ensure_datasets()` downloads `datasets.json` and
  then warms every catalog (`prefetch_catalogs`, best-effort); a missing catalog
  is retried by `ensure_catalog(theme)`. The `.release` marker ties the cache to
  the pinned ref: when `release` changes the cache is wiped and rebuilt. Once
  cached, listing needs no network; wallpapers, previews and set-default stay
  remote. A failed `datasets.json` exits non-zero (no live fallback).
- **Image cache**: the big remote images (theme detail pane, fullscreen
  preview) are downloaded once by `manager.sh image` into
  `${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/<pluginId>/` and then loaded from
  disk, so switching selection never re-downloads or re-decodes a 2K frame.
  The key is `md5(url)` and the URL already carries the release ref, so a
  release bump invalidates the cache on its own. The QML resolves the selected
  image through `detailImageProc` / `previewImageProc` (latest request wins,
  `flock` on the script side) and prefetches the ±3 neighbours via `prewarm`,
  which prints `url<TAB>path` per warmed image; QML records them in
  `imagePathByUrl` so navigating to a neighbour loads the local file instead of
  the remote URL. The directory is per plugin id (`WALLPAPER_MANAGER_ID`, set
  from `manifest.id`), so the official and developer installs never share files.
- **`manager.sh` command surface**:

  | command | args | stdout (TSV) |
  |---|---|---|
  | `themes` | — | `name  title  catalogUrl  collections  count  preview  installed  palette  description  image  present` (`preview` = card thumbnail, `image` = 2K for the detail pane; `palette` = comma-separated hex, read straight from the dataset — no hardcoded fallback; `present` = the Omarchy theme exists locally) |
  | `catalog` | `<theme> <catalog-url>` | `filename  name  code  url  sha256  installed  isDefault  preview  sizeBytes  collection  resolution  width  height` (local catalog; the URL arg is only a fallback) |
  | `install` | `<theme> [selector]` | human text; no selector = all, selector matches id/name/code/filename. Streams `PROGRESS\t<theme>\t<installed>\t<total>` lines while it runs |
  | `random-install` | `<theme> [count]` | human text; installs `<count>` random wallpapers (default 5). Same `PROGRESS` stream |
  | `remove` | `<theme> [selector]` | human text; same selector matching. Same `PROGRESS` stream (count decreases) |
  | `set-default` | `<theme> <filename> <url>` | human text; downloads if missing then `omarchy-theme-bg-set` |
  | `unset-default` | `<theme> <filename>` | human text; if it is the background, falls back to the theme's own default background |
  | `image` | `<url>` | local cache path of the image (downloads it once); empty on failure |
  | `prewarm` | `<url>...` | `url<TAB>path` per warmed image; warms the image cache (best-effort) |
  | `download` | `<url> <dest-dir>` | copies the original into the folder (numeric suffix on collision), prints the saved path |

  (`installed` / `isDefault` are `"0"`/`"1"`; `manager.sh` prints the default
  column as `current`, the QML model names it `isDefault`.)
- **Image guard**: only files whose extension is in the allowlist
  (`ALLOWED_IMAGE_EXTS`: `webp`, `jpg`, `jpeg`, `png`, case-insensitive) are
  installed. `is_allowed_image` is checked in `download_one` (install /
  random-install), in `cmd_set_default` (a background must be a real image) and
  when selecting rows for `cmd_install` (invalid entries are skipped with a
  warning). `download` (user-chosen save) is not filtered. Content stays pinned
  by sha256.
- **Shell ⇄ QML protocol**: TSV lines on stdout, one record per line with the
  fixed columns above; QML splits on `\t` and appends each row to a `ListModel`
  (`themesModel`, `wallpapersModel`).
- **State** lives on `root`: `view`, `selectedIndex`, `cursorActive`, `busy`,
  `statusText`. Mouse and keyboard share one cursor through `CursorSurface`
  (visuals from `hasCursor` / `current`, never `containsMouse`), so exactly one
  tile is ever highlighted.
- **Actions**: `actionInstall` / `actionRemove` / `actionSetDefault` /
  `actionInstallAll` / `actionRemoveAll` all funnel into `runAction(args)` →
  `actionProc`. On exit `applyActionResult()` updates the in-memory catalog in
  place (`setProperty` on `wallpapersModel` / the display model) instead of
  reloading it: a full reload reset the grid/strip scroll, restarted the
  navigator and made the whole UI lag. The theme counts stay live from the
  `PROGRESS` lines. **One operation at a time**: `runAction` ignores a new task
  while `actionProc` runs, the bulk buttons are disabled (and dimmed) until it
  finishes, and Esc cancels the running process. `runAction` records the theme
  argument in `actionTheme`, so the row badge and the footer progress
  (`progressTheme`) keep showing the theme being worked on even when the user
  browses another one.
- **Themes search**: `/` (or Tab) opens the search editor; typing filters the
  left list by name/title through `Model.themeMatches`. The list binds to
  `activeThemesModel` — `themesModel` when the filter is empty, else the
  JS-rebuilt `themesDisplayModel` (Menu-style rebuild, no `QQC.TextField`, so
  arrow keys keep driving the cursor). While `searching` the `PanelKeyCatcher`
  is `blocked` and the card's `Keys.onPressed` fallback owns every key:
  printable chars append, Backspace/Ctrl+Backspace/Ctrl+U use
  `Util.editsFilter`, arrows/PageUp/PageDown navigate, Enter browses, Esc clears
  the filter then exits. Footer counts stay global.
- **Wallpapers search**: the same shared state/behaviour as the themes one, but
  the field sits in a full-width row above the grid next to two inert buttons
  (`Select all` / `Clear`, multi-select comes next). Typing filters by name or
  code through `Model.wallpaperMatches`; the grid binds to
  `activeWallpapersModel` — `wallpapersModel` when the filter is empty, else the
  JS-rebuilt `wallpapersDisplayModel`. Enter opens the preview.
- **Local components**: `components/RoundedImage.qml` (MultiEffect mask +
  `Style.cornerRadius`, `clip: true` is not enough), `components/HeroLogo.qml`
  (assets/images/logo.png with a nerd-font glyph fallback),
  `components/Pill.qml` (state pills, transparent fill + flat tinted border),
  `components/ThemeProgress.qml` (theme install bar, shared by both footers),
  `components/SearchField.qml` (search box with caret and clear X, shared by the
  themes and wallpapers searches).

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
  (1px, `foreground @ 0.12`). The rules bleed to the card edges: cancel the
  content padding (`-card.leftPadding` + explicit
  `card.width - card.borderLeft - card.borderRight`) so they span the whole
  card, and wrap the footer one in an `Item` (a `Column` forces `x` back to 0).
- **Card size**: `Math.min(Style.space(N), panel.width - Style.gapsOut * 2)`.
  `Style.gapsOut` is the canonical screen margin (it is already half of
  Hyprland's `gaps_out`).
- **Header** = `Ui/PanelHero`: icon + bold title (`Style.font.title`) +
  UPPERCASE meta caption + optional `detail` pill + `trailingControl` for the
  buttons. The icon is the **emkcloud logo** (`assets/images/logo.png`, the
  org avatar) via the local `components/HeroLogo.qml`: a `RoundedImage`
  `Style.font.displayLarge` wide, same in every view, with the old nerd-font
  glyphs (`󰸌` themes, `` wallpapers) as fallback if the file cannot be
  resolved. It is the only image allowed in the **runtime UI** (the README
  banner is repo-only and never loaded by the plugin).
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
  wallpaper. On the wallpapers grid the cursor also paints an **accent** ring
  (`Border.flat(root.accent, …)`) on top of the tile: the kit's hover-cursor
  border is theme-tuned (often `foreground` at low alpha) and reads poorly over a
  busy thumbnail, so selection follows the shell's own image-picker treatment
  (`[image-picker] selected-border`, accent at full opacity). The filmstrip uses
  the same accent ring for its current cell.
- **Keyboard** = `Ui/PanelKeyCatcher` wrapping the content; the panel keeps the
  state machine (`moveCursor(dx,dy)` / `activateCursor()` / `dismissCursor()`).
  Canonical keys: arrows + h/j/k/l, Enter/Space activate, Esc back/close,
  **x/X remove** (`deleteRequested`), `d` default, `r` refresh and `u` uninstall
  via `textKey`. Del/Backspace and **PageUp/PageDown** (jump a whole visible page
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
- **Spinner** (decision 2026-09-15, supersedes the 2026-09-03 "no spinners"): a
  running overlay (`components/RunningOverlay.qml`) is shown while an action
  installs/removes — an opaque scrim, an accent spinner (`Shape` +
  `PathAngleArc` + `RotationAnimator`) and a pulsing caption (`actionLabel`:
  "Downloading <size>…" / "Removing…" / "Downloading <n> wallpapers…"). It is
  used by the fullscreen preview (a sibling of `previewImageFrame` anchored to it
  with `z: 6`, so it also covers the filmstrip) and by the themes screen
  (covering the whole `themesView` — sidebar + detail — while a bulk
  install/remove runs). Its `MouseArea` swallows clicks and the keyboard
  navigation is guarded on `actionRunning` (`moveCursor` / `pageCursor` /
  `activateCursor` / `startSearch` all return early) and the hero actions are
  dimmed, so only Esc (cancel) is accepted while it is up.
  Image *loading* still has no spinner: feedback is the hero meta line.
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
6. In `actionProc.onExited` call `progressTimer.stop()` (the id), **not**
   `root.progressTimer.stop()`: ids are not properties of root, so
   `root.progressTimer` is `undefined` and `.stop()` throws a TypeError that
   aborts the handler before `refresh()`. The catalog then never reloads and the
   installed state (dot, Install/Uninstall, strip thumbnails) stays stale after
   an install/remove.
7. Progress must be **throttled, not debounced**: `applyProgress` starts the
   timer only when it is idle (`if (!progressTimer.running) stop/start`), never
   `restart()`. A fast local `remove` emits every `PROGRESS` line back-to-back,
   so `restart()` kept postponing the flush until the process exited and the
   buffered count was then discarded — the themes list stayed at the pre-action
   count and only a re-entry showed the wallpapers gone. `onExited` also calls
   `flushProgress()` before clearing `pendingProgress*` so the last line is
   never lost.

## Local development

Two installs can coexist, distinguished by id:

- **Developer** — `emkcloud.wallpaper-manager-developer`: symlinks back to this
  checkout, created by `scripts/developer.sh link`. Edit the repo, then
  `omarchy restart shell`. Every screen flags itself with a **`developer`** pill
  (`root.dev`, derived from the manifest id) so the two installs are never
  confused.
- **Official** — `emkcloud.wallpaper-manager`: a real git checkout, installed
  with `omarchy plugin add … --enable --yes`; use it to test add/update exactly
  as a user would. `scripts/developer.sh` never touches it.

```bash
bash scripts/developer.sh link     # create/enable/summon the dev plugin
bash scripts/developer.sh unlink   # remove it
```

`link` generates the dev `manifest.json` from the official one (only `.id` and
`.name` change) and symlinks `interface`, `scripts`, `config`, `assets`. It also
clears the dev dataset cache (`~/.cache/omarchy/<dev-id>/datasets`) so every dev
session re-downloads the dataset and exercises the full path. Because the plugin is a
`bar-widget`, `link` does a `disable` + `enable` so the bar icon is (re)placed;
the same is needed once for an already-enabled official install. `unlink`
refuses to delete anything without the `.dev-wrapper` marker.

> ⚠️ **Symlink vs hot-reload.** The shell watches `~/.config/omarchy/plugins/`
> with inotify, which does **not** follow symlinks. The dev wrapper is symlinks,
> so edits are NOT hot-reloaded: after changing QML, restart the shell:
> `omarchy restart shell`, then re-summon. (For true hot-reload, copy the files
> into `~/.config/omarchy/plugins/<id>/` instead of symlinking.)

The dataset and image caches are keyed by plugin id
(`WALLPAPER_MANAGER_ID`, passed by the QML), so the official and dev installs
never share files and neither writes inside the watched plugin directory.

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
