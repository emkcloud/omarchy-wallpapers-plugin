# Development guide

Architecture, conventions and the traps not to fall into. Read this before
changing QML. For how to build, test and run things, see `docs/TESTING.md` and
the *Local development* section below.

## Project overview

`emkcloud.wallpaper-manager` is an Omarchy shell plugin that browses the
emkcloud wallpaper collections served from CloudFront, and installs / removes /
sets the default wallpaper in the local Omarchy theme, with optional automatic
rotation. It ships two entry points: a fullscreen **overlay** and a **bar
widget** that opens it.

All network, disk and image work is done by `scripts/manager.sh`, driven by the
QML over `Process` and parsed from TSV/JSON on stdout. The QML never talks to
the CDN or the filesystem directly — it *renders state* and *calls the script*.

## Repository layout

```
manifest.json            plugin manifest (id, version, entry points, kind)
config/config.json       CDN base + path/link overrides (no code)
interface/
  WallpaperManager.qml   overlay entry point: controller + window shell
  BarLauncher.qml        bar widget: opens the overlay
  Settings.qml           persistent settings + screen cursor state (id: settings)
  views/                 the six full screens, one file each
  sections/              composite chrome shared across screens (hero, footer)
  components/            local QML atoms
  js/Model.js            pure logic (parsing, formatting, cursor math)
scripts/manager.sh       all shell work (catalog, install, remove, image, …)
help/                    data-driven Help content (index.json, *.md)
datasets/                tracked placeholder, runtime cache lives in ~/.cache
assets/                  logo and README screenshots
docs/                    DEVELOPMENT.md, TESTING.md
```

- `interface/` holds all QML so the repo root keeps only metadata and config.
- `interface/js/Model.js` must stay **pure**: no QML ids, no state. It parses
  TSV/JSON and does arithmetic. The controller owns the models and the state.

## Architecture

Three ideas carry the whole design. Understand these and the rest is detail.

### 1. One controller, many disposable screens

`WallpaperManager.qml` is the **single controller** (`id: root`): it owns every
model, every `Process`/`FileView`, the keyboard state machine and the actions.
It is written **logic-first, UI-last** (state → processes → actions → window
shell).

The screens in `views/` are **render-only**: they take `required property var
manager` (the panel) and read state / call actions through it. They never own
business state.

> **One screen at a time.** A `Loader` (`contentLoader`) mounts only the active
> screen; a second (`previewLoader`) mounts the fullscreen preview. Leaving a
> screen **destroys** its component. This is deliberate: a persistent-but-hidden
> screen can still hold focus, take clicks, or leave a `Popup` floating over the
> next screen. Destroying it removes that whole class of bug.

Because a screen can be `null`, the controller reaches it through **guarded
accessors** instead of direct ids:

```qml
function themesView()  { return root.view === "themes"  ? contentLoader.item : null }
function wallpapersGrid() { var v = wallpapersView(); return v ? v.grid : null }
function wallpapersCollectionDropdown() { … }
```

Each returns `null` when the screen is not mounted, so callers guard naturally.
After a screen is mounted, `restoreViewScroll()` re-applies the list/grid scroll
to the current cursor row.

### 2. State lives where it survives a screen switch

Since screens are destroyed, any state that must outlive them lives **outside**:

- `Settings.qml` — a persistent object created once by the panel (id
  `settings`). It owns the settings values (resolution, caps, rotation,
  per-theme defaults, favorites) **and** the Setup / Help cursor state
  (`setup*`, `setupHelp*` members), plus the `FileView`/debounce load-save
  machinery. The Setup screen is thus a pure renderer over `settings.*`.
- The panel (`root`) owns navigation and interaction state: `view`,
  `selectedIndex`, search/filter strings, `checkedWallpapers`, the custom-install
  state and the derived pane widths.

**Screen-state ownership**

| State | Owner | Why |
|---|---|---|
| `view`, `selectedIndex`, search/filters | panel | navigation survives every switch |
| settings values, Setup/Help cursor | `Settings` | must survive Setup/Help rebuild |
| custom-install data + cache | panel | shared with the grid/theme screens |
| transient focus/edit (Setup row, Help topic) | `Settings` | cursor must persist |
| hover/scroll position | view + `restoreViewScroll()` | rebuilt on mount |

### 3. The script is the only I/O

Every operation is one `manager.sh` invocation, run by a dedicated `Process` that
parses a stable, line-based protocol:

| Command | Output | Consumed by |
|---|---|---|
| `themes` | `TSV` theme rows | `themesProc` |
| `catalog <theme>` | `TSV` wallpaper rows | `catalogProc` / `customCatalogProc` |
| `limits` | `LIMITS\t<files>\t<bytes>` | `limitsProc` |
| `warm` | `url\tpath` preview lines + `WARM` | `warmProc` |
| `install` / `remove` / `set-default` / `random-install` | `PROGRESS\t…` per file | `actionProc` |
| `image` / `prewarm` | `url\tpath` | detail/preview/prewarm procs |

`runAction(args)` is the single entry for mutating actions; it records
`lastAction`, sets `actionRunning`, and lets `onExited` apply the result. See
*Actions & progress*.

## Code map — `interface/WallpaperManager.qml`

Source order, top to bottom. This is where each concern lives.

| Section | Key members | Role |
|---|---|---|
| paths | `pluginRoot`, `pluginPaths`, `scriptPath`, `logoPath`, `pluginBase`, `pluginLinks` | resolve layout from `config/config.json`; `pluginRoot` comes from this file's own location, never `manifest.__sourceDir` (the shell strips it) |
| `Settings` | `id: settings` | persistent settings + Setup/Help cursor state |
| state | `opened`, `view`, `themeName`, `selectedIndex`, filters, `checkedWallpapers`, custom state | single source of truth for navigation |
| live screen handles | `themesView()`, `wallpapersGrid()`, `scrollToList()`, `restoreViewScroll()`, … | guarded accessors for the Loader-mounted screens |
| tokens | `foreground`, `background`, `accent`, `dim`, `borderSpec`, `contentMargin`, `heroHeight`, `themePaneWidth`, `customPaneWidth` | `Color.menu.*` / `Style.*` aliases; pane widths derived here, not read from views |
| cache / images | `customCatalogCache`, `imagePathByUrl`, `cachedImagePath()`, `prefetchAllCatalogs()` | in-memory caches that make screens open instantly |
| summon / hide | `open()`, `close()`, `requestClose()` | overlay lifecycle |
| cursor state machine | `activeCount()`, `stepCursor()`, `moveCursor()`, `pageCursor()`, `activateCursor()`, `spaceCursor()`, `dismissCursor()`, `handleTextKey()`, `takeCursor()` | one `selectedIndex`, driven identically by mouse and keyboard |
| screen hooks | `setupActivateCursor()`, `helpMoveSelection()`, `custom*` | bridge the panel's keys to `settings` / views |
| actions | `actionInstall/Remove/…`, `runAction()`, `cancelAction()` | user operations |
| result application | `applyActionResult()`, `applyCustomActionResult()`, `applyProgress()`, `flushProgress()` | update models in place, no full reload |
| processes | `warmProc`, `themesProc`, `catalogProc`, `customCatalogProc`, `actionProc`, … | run `manager.sh`, parse output |
| window shell | `panel`, `card`, `keys`, `heroRule`, `contentLoader`, `previewLoader` | the overlay chrome + the screen Loader |

### Screen composition

Every screen shares the same skeleton inside the card:

```
hero header (sections/HeroBar: icon, title, meta, buttons/pills)
+ PanelSeparator
+ body  (the mounted view)
+ dim status caption (sections/ActionFooter, bottom)
```

`HeroBar` and `ActionFooter` are the two shared chrome pieces. Both are
data-driven: the panel passes `view`, counts, progress and flags as properties;
the components emit intent signals (`onInstallRequested`, `onShowThemesRequested`,
…). Neither reads panel state directly.

## Screens

The overlay shows **six screens**, switched by the single `view` property.

| `view` | file | content |
|---|---|---|
| `"themes"` | `views/ThemeSelectionView.qml` | theme master list + big detail |
| `"wallpapers"` | `views/WallpapersView.qml` | collection picker + search + grid |
| `"preview"` | `views/PreviewView.qml` | fullscreen wallpaper + actions |
| `"help"` | `views/HelpView.qml` | data-driven guide |
| `"setup"` | `views/SetupView.qml` | three-column settings editor |
| `"custom"` | `views/CustomInstallView.qml` | previews (left) + install scopes (right) |

Navigation between them:

- `themes` → `wallpapers` (`Enter`/click) → `preview` (Enter/click).
- `help`, `setup`, `custom` are reached from the footer/hero; Esc retraces the
  origin (`*ReturnView`), except Esc on the grid from "Select only", which
  returns to `custom` (`wallpaperReturnCustom`).

### Themes (`themes`)

Master list of remote themes (left) + detail pane (right). `selectedIndex`
drives both the highlight and the detail for mouse and keyboard alike. The
detail shows the theme image, palette, description and the bulk actions
(Install all / Shuffle / Remove all). Moving the cursor calls
`prefetchCustomCatalog()`, and on load `prefetchAllCatalogs()` warms **every**
theme so Custom Install opens instantly.

### Wallpapers (`wallpapers`)

Filter row (collection dropdown / search / `Select all` / `Clear`) + the grid.
`filterFocus` is the focusable strip (Setup model); `searching` routes all keys
to the search editor. Multi-select is `checkedWallpapers` (filename → true),
tracked by `selectionRevision`. The footer's Install/Uninstall buttons and the
`i`/`u` keys share one gate:

```
wallpapersCanInstall = the selection (checks, else cursor tile) has a non-installed row
wallpapersCanRemove  = the selection has an installed row
```

so a fully-installed selection disables Install and an all-to-install selection
disables Uninstall — visually and on the keyboard.

### Preview (`preview`)

Fullscreen image over the card (`z: 10`), with the info pill, filmstrip and
Download / Back / Close actions. The panel owns the target wallpaper; the view
renders. The image uses a two-buffer cross-fade (`previewImage` / `previewImageAlt`)
with an 80 ms fade so stepping through the filmstrip never flashes black.

### Help (`help`)

Three columns: roadmap (left), topic content (centre), index + resources
(right). All content is data under `help/` (`index.json`, `roadmap.json`, one
Markdown file per topic). The cursor (`settings.setupHelpSelectedFlat`) lives in
`Settings`; the view mirrors it for rendering and picks the first topic on mount.

### Setup (`setup`)

Three columns, same sidebar width as Help: roadmap, section editor, section
index + usage + actions. **All values and the cursor live in `Settings`**
(`settings.resolution`, `settings.setupSection`, …); the view only binds and
calls. `manager.sh rotate` powers "Rotate now". Settings auto-save (debounced)
to `~/.config/omarchy/<pluginId>/settings.json`.

### Custom install (`custom`)

Left: 3×3 previews + theme info. Right: the install scopes (Full collections,
Favorites when any is available, one per collection, Shuffle, Select only) + the
random-default switch. Its catalog is kept as a **plain JS array**
(`customCatalogItems`), never a `ListModel`: see bug 9.

The Favorites row is built by `Model.favoritesSummary(customCatalogItems,
settings.favorites)` — the intersection of the starred files with this theme's
catalogue — and installs with `install <theme> --bulk <file…>` (caps honoured,
like a collection) or removes with `remove <theme> <file…>`.

## Favorites

Global, cross-theme stars keyed by `filename` (identical in every theme; the
theme only changes the URL/sha). State lives in `Settings.qml`
(`favorites` + `favoritesRevision`, persisted in the plugin `settings.json`
beside `themeDefaults`), the pure logic in `Model.js`
(`sanitizeFavorites` / `isFavorite` / `favoritesSummary`, plus the
`FAVORITES_FILTER` pseudo-collection). UI: the star badge on the tile
(`WallpapersView`) and beside the installed disc in `PreviewView`, the `f`/`m`
action from `Model.textAction`, the **Favorites** entry in `collectionOptions`,
and the Favorites card above. `f`/`m` act on `favoriteTargets()` — the checked tiles
when a selection exists (group star, or group clear when every one is already
starred), else the cursor tile. No `manager.sh` change beyond the `--bulk` flag.

## Actions & progress

`runAction(args)` is the single mutation entry. `actionScopeTotal` is fixed from
the **first** `PROGRESS` line of the action (never the theme total), so the
overlay caption describes the scope the user asked for.

On `actionProc.onExited`:

- `applyActionResult()` patches the in-memory `wallpapersModel` in place.
- `applyCustomActionResult()` patches `customCatalogItems` **and** the cache in
  place (no `manager.sh catalog` re-read — that was the slow path); only
  `random-install` still reloads, because its files are unknown.
- `customReloading` keeps the overlay up through the recompute; it is raised
  **before** `actionRunning` is cleared, so the spinner never blinks.
- A custom action chains the random default **only if it completed**; a
  cancelled one shows "Stopping…" and leaves the user on the screen.

### Overlay captions

`actionLabel` always describes the running action's own scope. During the
post-action recompute it reads "Finalizing…" (a completed action) or
"Stopping…" (a cancelled one). It never falls back to the theme's whole size.

## Caching (why screens are instant)

Catalog data is warmed **once at plugin start** and then read from disk/memory:

- `warmProc` runs `manager.sh warm` on `Component.onCompleted`: it downloads
  `datasets.json` + every theme catalog from the CDN if not cached (reusing them
  until the configured base changes), and prewarms each theme's first 9 previews.
- It emits `url\tpath` lines that populate `imagePathByUrl`, so the Custom
  Install previews load from disk on first paint.
- `prefetchAllCatalogs()` (on themes load) fills `customCatalogCache` for every
  theme, the selected one first, one process at a time.

The image cache is keyed by plugin id under `~/.cache/omarchy/<pluginId>/`, so
the official and developer installs never share files.

## Design canon (Omarchy)

There is no written design guide; the standard is implicit and lives in
`qs.Commons` tokens, the `qs.Ui` library, and `omarchy dev ui-preview`. This
plugin is **aligned** to it — do not drift.

This plugin is a fullscreen **overlay** (family A: `menu`, `clipboard`, `emojis`),
not a bar-anchored panel (family B: `audio`, `network`): colors are
`Color.menu.*`, padding is `Style.spacing.panelPadding`.

- **One flat surface.** The card is a single `Ui/BorderSurface` filled with
  `Color.menu.background`, `radius: Style.cornerRadius`, `padding:
  Style.spacing.panelPadding`, `borderSpec: Border.surfaceSpec("menu", …)`
  (never `border.color` — the spec carries the Hyprland gradient and per-side
  widths). No header/footer bars, no per-region fills: separation is
  `Style.spacing.md` + `Ui/PanelSeparator`. Rules bleed to the card edges by
  cancelling the content padding (`-card.leftPadding` + explicit
  `card.width - card.borderLeft - card.borderRight`).
- **Card size**: `Math.min(Style.space(N), panel.width - Style.gapsOut * 2)`.
- **Header** = `Ui/PanelHero` via `sections/HeroBar.qml`: icon + bold title +
  UPPERCASE meta + optional pill + `trailingControl` buttons. The icon is the
  emkcloud logo (`components/HeroLogo.qml`), the only image allowed in the
  runtime UI. **`heroHeight` is pinned** (`heroBar.implicitHeight`), applied to
  every screen, so switching view never shifts the separator.
- **Secondary text** is `Qt.darker(foreground, 1.4)` (`root.dim`), not
  `Util.alpha`.
- **Selection** is `Ui/CursorSurface` only; mouse hover calls
  `root.takeCursor(index)` and visuals derive from `hasCursor` / `current`, so
  exactly one tile is highlighted across mouse and keyboard. The wallpapers grid
  adds an **accent** ring on top (`Border.flat(root.accent, …)`).
- **Buttons** are `Ui/Button` with `bordered: true`; never pin `hasCursor`.
  No tooltips — key hints live in the footer hint row (`keyHint`).
- **Pills** follow `PanelHero`'s `detail` pill: transparent fill,
  `Border.flat(tint, …)`, caption in the tint.
- **Status** is a single dim caption at the bottom; there is no footer bar.
- **Spinner**: while an install/remove runs, `components/RunningOverlay.qml`
  shows an opaque scrim + accent spinner + pulsing caption. Keyboard navigation
  is guarded on `actionRunning`; only Esc (cancel) is accepted. Image *loading*
  has no spinner — feedback is the hero meta line.
- **Rounding** always comes from `Style.cornerRadius`. Images use
  `components/RoundedImage.qml` (`layer.effect: MultiEffect` + mask) because
  `clip: true` only clips rectangularly.

### Keyboard

`Ui/PanelKeyCatcher` wraps the content; the panel keeps the state machine. Keys:
arrows + h/j/k/l move, Enter/Space activate (on the grid Space toggles the
checkbox while Enter opens the preview), Esc back/close, `d` default, `r`
refresh, `f` shuffle, `s` setup (any screen), `u` uninstall / remove, `q` and
`x`/`X` close from any screen, `Del` remove, PageUp/PageDown page, F1 help.
Backspace is filter-only.

## Conventions

- **UI language**: all user-facing strings are **English**. No i18n framework.
- **Logical, not visual.** A component receives values and renders them; it must
  not render a value, then recompute and self-correct. Compute first, then mount
  the screen (e.g. a "browse a collection" target is carried in
  `pendingCollectionFilter` and applied with the rows, so the title and dropdown
  never show a transient value).
- Prefer immutable-style updates of plain-object/array state plus a revision
  counter, so bindings re-read them (QML does not track object internals).

## Bugs fixed along the way (do not reintroduce)

1. `fetch()` in `manager.sh` must pass extra curl args (`curl ... "$@"`) or `-o`
   is dropped.
2. A `Process` needs its `command` set **before** `running = true`, else it hangs.
3. Inotify does **not** follow symlinks: the dev wrapper is symlinks, so QML
   edits need `omarchy restart shell`.
4. Tiles must not anchor-horizontalCenter themselves (single-column bug).
5. `GridView` has no `columns` in Qt 6 — compute `colCount = max(1, floor(width /
   cellWidth))` and `positionViewAtIndex` after every move.
6. In `actionProc.onExited` call `progressTimer.stop()` (the id), not
   `root.progressTimer` (undefined → TypeError aborts the handler).
7. Progress is **throttled, not debounced**: start the timer only when idle, and
   `flushProgress()` before clearing buffers so the last line is never lost.
8. `loadWallpapers()` must guard a slow catalog with `catalogSerial` /
   `catalogPending`: a `Process` ignores a new `command` while running, so a
   stale result could otherwise populate the wrong theme's model.
9. A `ListModel` with one `append` per row blocks the first paint of the Custom
   Install screen (~1.3 s on a 750-row theme). Keep large catalogs in a plain JS
   array (`customCatalogItems`): assigning it is O(1).
10. Inside a `Loader`'s `Component`, outer ids are **not** visible without
    `pragma ComponentBehavior: Bound` at the top of the file — otherwise
    `settings: settings` injects `undefined`. Both the panel and `SetupView.qml`
    carry the pragma for this reason.
11. A catalogue `filename` is untrusted and becomes a path segment: never append
    it to the destination without validating it. `is_safe_filename()` rejects a
    directory component, `.`/`..` and a leading dash, and `download_one()`
    additionally checks the resolved path stays under `DEST_BASE`. The same rule
    applies to the theme (`require_safe_theme()`), another directory name from
    the untrusted datasets. The image extension allowlist alone does not stop
    `../../../../Pictures/photo.png` from overwriting an unrelated file during a
    bulk install. The theme keys of `datasets.json` are the same: they become a
    directory under the cache (`prefetch_catalogs`) and a folder under
    `DEST_BASE` (`cmd_themes`), so both skip a key that fails
    `is_safe_filename()`.
12. Catalogue values are untrusted **data** at every sink, not only paths. A
    `size_bytes` fed to `$(( ))` is a source-traced execution boundary: Bash
    recursively evaluates a variable's value in arithmetic context, so
    `a[$(cmd)]` runs the command substitution. `is_nonneg_int()` must gate every
    remote number before arithmetic (invalid → 0). Likewise a URL must pass
    `is_remote_url()` (http/https) and be passed after `--` so it cannot be read
    as a curl option or a `file://` local read.

## Testing

See `docs/TESTING.md`: the unit suite (`node --test`), the static checks
(`bash -n`, `qmllint`, `omarchy plugin validate`) and the manual pass.

## Local development

Two installs coexist, distinguished by id:

- **Developer** — `emkcloud.wallpaper-manager-developer`: symlinks back to this
  checkout.
- **Official** — `emkcloud.wallpaper-manager`: a real checkout, installed with
  `omarchy plugin add … --enable --yes`.

```bash
bash scripts/developer.sh link     # create/enable/summon the dev plugin
bash scripts/developer.sh refresh  # re-sync symlinks + dev manifest
bash scripts/developer.sh unlink   # remove it
```

`refresh` re-syncs the symlinks and regenerates the dev `manifest.json` (only
`.id`/`.name` differ) without clearing the cache. After editing the manifest (a
version bump), use `refresh`. `link` also clears the dev dataset cache so a dev
session exercises the full download path.

> ⚠️ The dev wrapper is symlinks; inotify does not follow them, so after QML
> edits run `omarchy restart shell` and re-summon.

The dataset/image caches are keyed by plugin id, so the two installs never share
files. Automatic rotation writes shared state (the current theme background):
keep it off on one install while testing it on the other.

## Distribution

The repo root is the plugin: `omarchy plugin add
https://github.com/emkcloud/omarchy-wallpapers-plugin.git --enable --yes`. Keep
`manifest.json` at the root.

- **CDN snapshot**: bump `base` in `config/config.json` to the new versioned
  CloudFront path. Clients get it through `omarchy plugin update`.
- **Plugin release**: bump `version` in `manifest.json`, commit, `git tag -a
  <version>`, push the tag. The manifest `version` and the tag carry the same
  number. Do not confuse this with `base`.
- **Marketplace acceptance**: a release is not published until a verification
  issue passes; see `docs/PUBLISHING.md` for the flow and the pre-submission
  security checklist.
