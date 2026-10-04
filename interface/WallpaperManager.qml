pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "views"
import "sections"
import "components"
import "js/Model.js" as Model

Item {
  id: root

  // Injected by omarchy-shell.
  property var manifest: null
  // True for the `-developer` install, so every screen can flag itself.
  // Temporarily forced off while the layout is refined: set `showDevBadge` to
  // true (or drop the `showDevBadge &&` guard) to show it again.
  readonly property bool showDevBadge: false
  readonly property bool dev: showDevBadge && manifest !== null
    && String(manifest.id || "").indexOf("-developer") !== -1
  // The shell strips `__sourceDir` from third-party manifests before injecting
  // them, so the plugin root is resolved relative to this file's own location
  // instead (same pattern as the shell's plugins, e.g. agents). The QML lives
  // one level deep (`interface/`), so the root is its parent directory.
  readonly property string pluginRoot: {
    if (manifest && manifest.__sourceDir) return manifest.__sourceDir.replace(/\/$/, "")
    var url = Qt.resolvedUrl("..").toString()
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  // ---- layout paths ---------------------------------------------------------
  // Resolved from `config/config.json` at the plugin root, so where the script and the
  // logo live is data, not code (`paths.scripts` / `paths.assets` /
  // `paths.logo`). Silent fallback to the shipped layout if the file is missing
  // or invalid; the defaults match the repo layout so the logo never flickers.
  property var pluginPaths: ({
    scripts: "scripts",
    assets: "assets",
    logo: "assets/images/logo.png",
    help: "help"
  })

  // The versioned CloudFront base from `config/config.json` (`base`). The
  // Archive RAW links derive `<base>/datasets/datasets.json` from it, so they
  // always open the dataset of the snapshot currently in use.
  property string pluginBase: "https://content.emkcloud.com/wallpapers/1.1.0"

  // Project links, resolved from `config/config.json` `links` so the Help
  // resources and the GitHub button can be repointed without a code change.
  // The defaults match the shipped config so nothing flickers while it loads.
  property var pluginLinks: ({
    repo: "https://github.com/emkcloud/omarchy-wallpapers-plugin",
    donation: "https://github.com/sponsors/emkcloud",
    issues: "https://github.com/emkcloud/omarchy-wallpapers-plugin/issues",
    releases: "https://github.com/emkcloud/omarchy-wallpapers-plugin/releases",
    marketplace: "https://plugins.omarchy.org/plugin.html?id=emkcloud.wallpaper-manager",
    wallpapersReleases: "https://github.com/emkcloud/omarchy-wallpapers/releases",
    database: ""
  })

  // Archive RAW target: an explicit `links.database` wins, otherwise the
  // datasets.json of the configured version.
  readonly property string pluginDatabaseUrl: {
    if (pluginLinks && pluginLinks.database) return String(pluginLinks.database)
    if (!pluginBase) return ""
    return pluginBase.replace(/\/+$/, "") + "/datasets/datasets.json"
  }

  FileView {
    id: configFile
    path: root.pluginRoot ? root.pluginRoot + "/config/config.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.pluginPaths = Model.parsePaths(text(), root.pluginPaths)
      root.pluginLinks = Model.parseLinks(text(), root.pluginLinks)
      root.pluginBase = Model.parseBase(text(), root.pluginBase)
    }
  }

  // Roadmap data, loaded once and shared by Help and Setup (both render it
  // through `components/RoadmapPane.qml`).
  property var roadmapData: Model.parseRoadmap("")

  FileView {
    id: roadmapFile
    path: root.helpRoot ? root.helpRoot + "/roadmap.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.roadmapData = Model.parseRoadmap(text())
    onLoadFailed: root.roadmapData = Model.parseRoadmap("")
  }

  // Help index, loaded once and shared by Help (sections/resources/feature) and
  // Setup (the "Propose a feature" action).
  property var helpIndex: Model.emptyHelpIndex()

  FileView {
    id: helpIndexFile
    path: root.helpRoot ? root.helpRoot + "/index.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.helpIndex = Model.parseHelpIndex(text())
    onLoadFailed: root.helpIndex = Model.emptyHelpIndex()
  }

  // Resolve the "Propose a feature" target (config link or literal URL) once,
  // so both Help and Setup use the same destination.
  readonly property string helpFeatureUrl: {
    var f = helpIndex ? helpIndex.feature : null
    if (!f) return ""
    if (f.link && pluginLinks[f.link]) return String(pluginLinks[f.link])
    return String(f.url || "")
  }

  // Active Omarchy theme: `theme.name` (e.g. "osaka-jade"). Used to land the
  // cursor on the theme the user is actually running when the overlay opens.
  property string activeThemeSlug: ""
  // Last theme observed in `theme.name`, so a real switch can be told apart
  // from the initial load (which must not re-apply a remembered default).
  property string lastActiveTheme: ""
  FileView {
    id: activeThemeFile
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    // `text()` is stale inside the change signal itself: reload -> onLoaded.
    onFileChanged: reload()
    onLoaded: {
      var next = text().trim()
      var prev = root.lastActiveTheme
      root.lastActiveTheme = next
      root.activeThemeSlug = next
      if (prev !== "" && next !== "" && prev !== next)
        root.scheduleThemeDefaultApply(next)
    }
    onLoadFailed: root.activeThemeSlug = ""
  }

  readonly property string scriptPath: {
    var p = pluginRoot
    var s = pluginPaths.scripts
    return p ? p.replace(/\/$/, "") + "/" + s + "/manager.sh" : s + "/manager.sh"
  }

  // emkcloud logo shipped with the plugin, used as the hero icon in every view.
  readonly property string logoPath: {
    var p = pluginRoot
    return p ? Util.fileUrl(p.replace(/\/$/, "") + "/" + pluginPaths.logo) : ""
  }

  // Help screen data root: index.json, roadmap.json and the topic Markdown
  // files live here (see docs/DEVELOPMENT.md).
  readonly property string helpRoot: {
    var p = pluginRoot
    var h = pluginPaths.help || "help"
    return p ? p.replace(/\/$/, "") + "/" + h : h
  }

  // Plugin repository, opened by the GitHub button in the hero actions.
  readonly property string pluginRepoUrl: String(pluginLinks.repo || "")

  // Links resolved from config.json `links`, like the hero actions.
  readonly property string pluginReleasesUrl: String(pluginLinks.releases || "")
  readonly property string pluginIssuesUrl: String(pluginLinks.issues || "")
  readonly property string wallpapersReleasesUrl: String(pluginLinks.wallpapersReleases || "")
  readonly property string marketplaceUrl: String(pluginLinks.marketplace || "")

  // Setup screen settings: persisted per plugin id under the user config, so
  // the official and developer installs never share them. `pluginId` is known
  // from the install directory itself, so the path is stable from creation and
  // never depends on when the shell injects the manifest (which is what used to
  // make a reload flip one install onto the other's settings file).
  readonly property string settingsDir: Quickshell.env("HOME") + "/.config/omarchy/" + pluginId
  readonly property string settingsPath: settingsDir + "/settings.json"

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  // First-run cache warm-up: `manager.sh warm` is running (datasets + catalogs +
  // previews). While true, opening the overlay shows "Initiating…" instead of an
  // empty theme list, and `themesPending` remembers that the load is waiting.
  property bool warming: true
  property bool themesPending: false
  property string view: "themes"          // "themes" | "wallpapers" | "preview" | "help" | "setup" | "custom"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  // Themes-screen cursor to restore when leaving a theme (goBack): browsing a
  // theme must not lose which row was open.
  property int lastThemeIndex: 0
  // True when the wallpapers grid was entered from the custom-install screen
  // ("Select only"): Esc then returns there instead of the theme list.
  property bool wallpaperReturnCustom: false
  // Wallpaper cursor per theme (`themeName` -> index), so re-entering a theme
  // resumes where it was left instead of jumping back to the first tile.
  property var wallpaperCursorByTheme: ({})
  property int pendingWallpaperIndex: 0
  property bool pendingWallpaperSelect: false
  // Collection to select once the catalog lands. "Browse" from Custom Install
  // asks for a collection before the theme's rows exist; applying it later
  // avoids the dropdown briefly showing the raw value ("countries") and then
  // swapping to the pretty label ("Countries") — the UI must not self-update.
  property string pendingCollectionFilter: ""
  // Catalog request guard: a slow `manager.sh catalog` for a theme the user has
  // already left must never repopulate `wallpapersModel`. Every request bumps
  // `catalogSerial`; a result is applied only while its serial and theme still
  // match the current selection, and the superseded request is re-run on exit.
  property int catalogSerial: 0
  property bool catalogPending: false
  // Multi-select of the wallpapers screen: filename -> true. `selectionRevision`
  // makes the plain-object map a tracked dependency for the tile checkboxes.
  property var checkedWallpapers: ({})
  property int selectionRevision: 0
  // Number of checked wallpapers, reactive on `selectionRevision`.
  readonly property int checkedCount: {
    var rev = selectionRevision
    var n = 0
    for (var key in checkedWallpapers) if (checkedWallpapers[key]) n++
    return n
  }
  // Footer/keys gating on the wallpapers screen: Install is meaningful only when
  // something in the selection is not installed, Uninstall only when something
  // is. With no checks, the cursor wallpaper decides. Reactive on the selection
  // and on the catalog (an action changes `installed` in place). One pass over
  // the selection, so "Select all" on a big grid stays cheap.
  readonly property var wallpapersSelectionState: {
    var rev = selectionRevision + wallpapersRevision
    var names = checkedCount > 0 ? checkedFilenames() : cursorFilenames()
    // One pass over the model to build filename -> installed, so a large
    // selection is not O(selection * model).
    var installedBy = {}
    for (var m = 0; m < activeWallpapersModel.count; m++) {
      var row = activeWallpapersModel.get(m)
      if (row) installedBy[String(row.filename)] = String(row.installed)
    }
    var installable = false
    var removable = false
    for (var i = 0; i < names.length; i++) {
      if (installedBy[names[i]] === "1") removable = true
      else installable = true
      if (installable && removable) break
    }
    return { installable: installable, removable: removable }
  }
  readonly property bool wallpapersCanInstall: wallpapersSelectionState.installable
  readonly property bool wallpapersCanRemove: wallpapersSelectionState.removable
  // Mark (star/unstar) needs a target: a checked selection or the cursor tile.
  // On an empty grid (e.g. the Favorites filter with no stars) it is disabled,
  // exactly like Install/Uninstall.
  readonly property bool wallpapersCanFavorite: checkedCount > 0 || currentItem() !== null
  // Set while a selection-based install/remove runs: the checks are cleared when
  // it finishes (not before, so the grid keeps showing what was acted on).
  property bool actionClearsChecks: false
  // PanelKeyCatcher emits `returnRequested` (Enter) just before `activateRequested`,
  // and `activateRequested` alone for Space: the flag keeps Enter on "activate"
  // and lets Space toggle the checkbox on the wallpapers screen.
  property bool enterHandled: false
  // A panel appearing under a stationary pointer re-hovers the tile/grid below
  // it, which would steal the cursor just restored by goBack/closePreview. Hover
  // selection is armed again a beat after every view switch (see `hoverGate`).
  property bool hoverArmed: true
  property bool busy: false
  property string statusText: ""
  // Search: one filter per list. `filterText` narrows the themes list,
  // `wallpaperFilterText` the wallpapers grid (each binds the list to a rebuilt
  // display model when active). `searching` routes all keys to the search
  // editor instead of the cursor shortcuts; it is shared by both views.
  // Entered with `/`, exited with Esc/Tab.
  property string filterText: ""
  property string wallpaperFilterText: ""
  // Collection filter on the wallpapers screen (`""` = every collection).
  property string collectionFilter: ""
  // Keep the picker label in sync when the filter is reset programmatically:
  // the Dropdown's own selection breaks the `value` binding.
  onCollectionFilterChanged: if (wallpapersCollectionDropdown())
    wallpapersCollectionDropdown().value = collectionFilter
  property bool searching: false
  // Set when Esc stops a running action, so `actionProc.onExited` reports a
  // cancellation instead of a completion.
  property bool actionCancelled: false
  // UI mirror of "an action is running". Driven explicitly (set on start, reset
  // on cancel/exit) instead of reading `actionProc.running`, whose value can lag
  // behind cancellation and leave the buttons dimmed.
  property bool actionRunning: false
  // Theme the running action operates on (set centrally in `runAction`), so its
  // row can flag the "installing" state and the footer keeps showing its
  // progress even while the user browses another theme.
  property string actionTheme: ""
  // How many wallpapers the running operation touches, so the "Downloading N
  // wallpapers…" caption describes the action (the collection / scope the user
  // asked for) instead of the theme's whole size. Fixed from the FIRST progress
  // line of the action: later phases (a trailing single default file) must not
  // move it, and it must not drift to the theme total. 0 means "no info yet":
  // fall back to the theme's own count.
  property int actionScopeTotal: 0
  // Arguments of the running/last action, so `onExited` can apply its effect to
  // the in-memory catalog instead of reloading the whole thing.
  property var lastAction: []
  // "Add remote source" placeholder: shows a COMING SOON label for 3s on click.
  property bool addSourceSoon: false

  // Bumped whenever `themesModel` is reloaded: property bindings that read the
  // model rows (`selectedTheme`, `themeCounts`) depend on it to re-evaluate.
  property int themesRevision: 0
  // Same for `wallpapersModel`: `currentInstalled` depends on it so the preview
  // Install/Uninstall state refreshes after a catalog reload.
  property int wallpapersRevision: 0
  // Storage caps: current local usage, refreshed on open and after every
  // action. When a cap is reached, bulk installs (Install all / Shuffle) are
  // disabled and the themes screen flags it.
  property int localFileCount: 0
  property real localBytes: 0
  readonly property real maxDiskBytes: settings.maxDiskGb * 1073741824
  // A small headroom: the bulk installer stops when the remaining budget is
  // below the smallest wallpaper, so the used size can sit just under the cap
  // while nothing else fits.
  readonly property real diskLimitSlack: 8 * 1024 * 1024
  readonly property bool storageLimitReached: localFileCount >= settings.maxLocalFiles
    || localBytes + diskLimitSlack >= maxDiskBytes
  // Which cap triggered it, with its value, so the banner is self-explanatory
  // ("Storage limit 1000" vs "Storage limit 3 GB").
  readonly property string storageLimitReason: {
    var fileHit = localFileCount >= settings.maxLocalFiles
    var diskHit = localBytes + diskLimitSlack >= maxDiskBytes
    if (fileHit && diskHit)
      return "Storage limit " + settings.maxLocalFiles + " · " + settings.maxDiskGb + " GB"
    if (fileHit) return "Storage limit " + settings.maxLocalFiles
    if (diskHit) return "Storage limit " + settings.maxDiskGb + " GB"
    return ""
  }

  // ---- image cache ----------------------------------------------------------
  // Big remote images are downloaded once by `manager.sh image` into
  // ~/.cache/omarchy/<pluginId>/ and then loaded from disk, so switching
  // selection never re-downloads or re-decodes the 2K original. The id comes
  // from the install directory, so the official and developer installs keep
  // separate caches.
  //
  // The directory name is the plugin id (`~/.config/omarchy/plugins/<id>`), and
  // `pluginRoot` is derived from this file's own location, so it is known
  // immediately. Reading it from the injected `manifest` instead was wrong: the
  // shell assigns `manifest` only after the component loads, so during a reload
  // `pluginId` briefly fell back to the official id and pointed the developer
  // install at the official settings file and cache. The manifest id stays as
  // the fallback for a layout that does not name the directory after the id.
  readonly property string pluginId: {
    var root = String(pluginRoot || "").replace(/\/+$/, "")
    var name = root !== "" ? root.split("/").pop() : ""
    if (name !== "") return name
    return manifest && manifest.id ? String(manifest.id) : "emkcloud.wallpaper-manager"
  }
  // Version from the injected manifest and the "name + version" label shown in
  // the themes and Setup hero metas.
  readonly property string pluginVersion: manifest && manifest.version
    ? String(manifest.version) : ""
  // Last path segment of the CDN base (e.g. "1.3.0"), shown in Setup.
  readonly property string cdnBaseVersion: {
    if (!pluginBase) return ""
    var parts = String(pluginBase).replace(/\/+$/, "").split("/")
    return parts.length > 0 ? parts[parts.length - 1] : ""
  }
  // Update check shown in Setup's "Check for updates" row: "idle" until run,
  // then "checking", "uptodate", "available" or "error". Omarchy installs the
  // update itself, so the plugin only reports the result.
  property string updateCheckState: "idle"
  property string updateRemoteVersion: ""

  function checkForUpdates() {
    if (updateCheckState === "checking") return
    updateCheckState = "checking"
    updateRemoteVersion = ""
    remoteVersionProc.running = true
  }

  // Open a URL in the browser and hide the overlay, like the hero actions.
  function openExternalUrl(url) {
    if (!url) return
    Qt.openUrlExternally(String(url))
    close()
  }
  readonly property string versionedName: pluginVersion !== ""
    ? "Wallpaper manager " + pluginVersion
    : "Wallpaper manager"
  property string detailImagePath: ""      // resolved local path
  property string detailImageSource: ""    // URL that path corresponds to
  property string pendingDetailUrl: ""     // latest URL queued for resolution
  property string previewImagePath: ""
  property string previewImageSource: ""
  property string pendingPreviewUrl: ""
  // url -> local cache path for the prewarmed neighbours, so navigating to one
  // loads the file already on disk instead of re-fetching the 2K remote image.
  // `imageCacheRevision` makes bindings (nextSource) re-read the plain object.
  property var imagePathByUrl: ({})
  property int imageCacheRevision: 0
  property var pendingPrefetch: []
  // Backdrop of the Favorites empty state: a random wallpaper of the open
  // theme, picked once (not on every render) and flushed behind the message.
  property string favoritesBackdrop: ""
  // "Download original": the URL queued and the folder chosen in the picker.
  property string pendingDownloadUrl: ""
  property string pendingDownloadDest: ""
  // Live progress is coalesced: `manager.sh` emits one line per wallpaper and
  // applying each one would re-evaluate the themes screen hundreds of times
  // during an install. Buffer the latest value and flush on a timer instead.
  property string pendingProgressTheme: ""
  property int pendingProgressInstalled: -1
  property int pendingProgressScopeTotal: -1

  // Cursor model (see Ui/CursorSurface.qml): mouse hover and keyboard share a
  // single cursor. Items derive their visuals from `hasCursor`, never from
  // `containsMouse`, so only one tile is ever highlighted.
  property bool cursorActive: true

  // Keyboard focus of the wallpapers filter row: -1 = the grid, 0 = collection
  // dropdown, 1 = search field, 2 = Select all, 3 = Clear. Mirrors the Setup
  // screen's focus model so the whole row is reachable without a mouse.
  property int filterFocus: -1

  // Keyboard focus of the themes detail action row: -1 = the theme list, else
  // the index into `themeActionKeys`. Tab switches between the list and the
  // action row, Left/Right walk the buttons, Enter/Space activate the focused
  // one, Down/Esc return to the list.
  property int themeFocus: -1

  // ---- custom install screen ------------------------------------------------
  // The theme the custom-install screen configures, captured on open so the
  // screen keeps its data even if the themes cursor moves underneath.
  property string customThemeName: ""
  property string customThemeCatalogUrl: ""
  property bool customThemePresent: false
  property bool customLoading: false
  // True while the catalog is being re-read after an install/remove (finished
  // or cancelled). The action overlay stays up for this window too: the UI is
  // still busy recomputing the card counts, so it must not look free.
  property bool customReloading: false
  // Last action caption, kept so the overlay can show the same "Downloading…"
  // while the counts are recomputed (no label swap, no blink).
  property string customBusyLabel: ""
  // True while the custom screen runs its closing random-default step (a single
  // file). The overlay reads "Finalizing…" instead of "Downloading 1…".
  property bool customFinalStep: false
  // True once the catalog has rows to build the option cards from. The screen
  // hides the list until then, so it never renders a partial set (just Full /
  // Shuffle / Select only) that then shifts under the cursor when the
  // collections stream in.
  readonly property bool customCatalogReady: customCatalogItems.length > 0
  // Cursor over the option rows (0..N-1) plus the trailing switch row (N).
  property int customSelection: 0
  // Bumped when the custom catalog (re)loads: `customRows` re-reads the model.
  property int customRevision: 0
  // Request stamp, so a superseded catalog load is discarded.
  property int customSerial: 0
  // Parsed catalog rows per theme (`theme -> rows[]`), filled by both the
  // wallpapers grid and the custom screen (and by the idle prefetch). The
  // catalogs are already cached on disk, so re-reading them through a process
  // is pure overhead: this keeps the last parse in memory and lets the custom
  // screen open instantly. Invalidated for a theme whenever an action touches
  // it, so the installed flags can never go stale.
  property var customCatalogCache: ({})
  // Theme queued for the idle catalog prefetch ("" = none).
  property string pendingCustomPrefetch: ""
  // Remaining themes to warm in the background, in order. Filled once after the
  // themes load (`prefetchAllCatalogs`), so Custom Install is instant whichever
  // theme the user picks instead of only the one under the cursor.
  property var customPrefetchQueue: []
  // Theme queued for a random default once a custom install finishes ("" = none).
  property string pendingCustomRandomDefault: ""

  // ---- theme tokens ---------------------------------------------------------
  // Overlay chrome follows the first-party overlays (menu / clipboard /
  // emojis): a single flat `Color.menu.*` surface, no per-region fills, and
  // borders built from the theme spec so Hyprland gradients survive.
  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color scrim: Color.menu.scrim
  readonly property color dim: Qt.darker(Color.menu.text, 1.4)
  // Border follows the same theme token as the bar flyouts/OSD
  // (`popups.border` -> the Hyprland active border), so the card outline is
  // theme-dynamic instead of the flat menu foreground.
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
  // Breathing room of the footer rows above their rule.
  readonly property int footerSpacing: Style.space(14)
  // The card's bottom padding is larger than the footer's own spacing, so the
  // footer is nudged past the content bottom by the difference: the gap below
  // the buttons then matches the one above them. Siblings anchored to the
  // footer (the preview image frame) compensate by the same amount.
  readonly property int footerOverlap: Math.max(0, root.contentMargin - root.footerSpacing)
  readonly property int minTileWidth: Style.space(190)
  // Themes are few and shown as a vertical master list.
  readonly property int themeRowHeight: Style.space(64)
  // Shared height so "Add remote source" and the detail action buttons line up
  // on both sides of the vertical rule.
  readonly property int actionButtonHeight: Style.space(36)
  readonly property int tileGap: Style.space(4)
  readonly property int tileInset: Math.max(1, Style.normalBorderWidth)
  readonly property string fontFamily: Style.font.menuFamily

  // Persistent settings shared with the Setup screen (see Settings.qml). Kept
  // here so destroying the Setup screen never loses the values.
  Settings {
    id: settings
    settingsPath: root.settingsPath
    settingsDir: root.settingsDir
    // The keyboard path (Setup → Rotate now) goes through the Settings signal;
    // the on-screen button emits the view's own signal.
    onRotateRequested: root.rotateWallpaper()
  }

  // Content width used to derive the side panes. The card width and its
  // padding are known here, so the pane widths no longer have to be read back
  // from the (now disposable) views.
  readonly property real cardContentWidth: Math.max(0,
    Math.min(Style.space(1180), panel.width - Style.gapsOut * 2) - contentMargin * 2)
  // Master-pane width of the themes/help/setup sidebars: 26% of the content,
  // min 210 — the same rule ThemeSelectionView uses internally.
  readonly property real themePaneWidth: Math.max(Style.space(210),
    Math.floor(cardContentWidth * 0.26))
  // Footer divider alignment for the custom-install previews pane (62% of the
  // content, min 260), expressed as the offset the footer expects.
  readonly property real customPaneWidth: Math.max(Style.space(260),
    Math.floor(cardContentWidth * 0.62))

  // The two heroes (grid / fullscreen preview) are pinned to the same height so
  // switching view — or a title that grows a resolution suffix — never shifts
  // the separator and the content below it. Both heroes share the same font and
  // insets, so their natural height is the same.
  readonly property int heroHeight: heroBar.implicitHeight

  // ---- live screen handles --------------------------------------------------
  // The screens live behind `contentLoader` / `previewLoader` and are destroyed
  // on every view switch, so the panel reaches them through these guarded
  // accessors instead of direct ids. Each returns null when the screen is not
  // mounted, which is exactly the case the guards need to tolerate.
  function themesView() { return root.view === "themes" ? contentLoader.item : null }
  function helpView() { return root.view === "help" ? contentLoader.item : null }
  function setupView() { return root.view === "setup" ? contentLoader.item : null }
  function wallpapersView() { return root.view === "wallpapers" ? contentLoader.item : null }
  function previewView() { return previewLoader.item }

  function themesList() {
    var v = themesView()
    return v ? v.listView : null
  }

  function wallpapersGrid() {
    var v = wallpapersView()
    return v ? v.grid : null
  }

  function wallpapersCollectionDropdown() {
    var v = wallpapersView()
    return v ? v.collectionDropdown : null
  }

  function wallpapersColumns() {
    var g = wallpapersGrid()
    return g ? g.colCount : 1
  }

  function wallpapersGridHeight() {
    var g = wallpapersGrid()
    return g ? g.height : 0
  }

  function wallpapersCellHeight() {
    var g = wallpapersGrid()
    return g ? g.cellHeight : 1
  }

  function themesListHeight() {
    var l = themesList()
    return l ? l.height : 0
  }

  // Position a view's scroll to its cursor row. Called after a screen is
  // mounted (a destroyed-and-rebuilt list starts at the top) and by the cursor
  // code whenever it needs to keep the selection in view. Safe while no screen
  // is mounted.
  function scrollToList(index, position) {
    var t = themesList()
    if (t) t.positionViewAtIndex(index, position)
  }

  function scrollToGrid(index, position) {
    var g = wallpapersGrid()
    if (g) g.positionViewAtIndex(index, position)
  }

  // Re-apply the scroll position of the screen that was just mounted.
  function restoreViewScroll() {
    Qt.callLater(function() {
      if (root.view === "themes") scrollToList(Math.max(0, root.selectedIndex), ListView.Contain)
      else if (root.view === "wallpapers")
        scrollToGrid(Math.max(0, root.selectedIndex), GridView.Contain)
    })
  }

  ListModel { id: themesModel }
  // Filtered view of `themesModel`, used by the left list only while a search
  // is active; with no filter the list reads `themesModel` directly so live
  // install progress keeps updating.
  ListModel { id: themesDisplayModel }
  ListModel { id: wallpapersModel }
  // Filtered view of `wallpapersModel`, used by the grid only while a wallpaper
  // search is active; with no filter the grid reads `wallpapersModel` directly
  // so live install progress keeps updating.
  ListModel { id: wallpapersDisplayModel }
  // Catalog of the theme being configured on the custom-install screen. Kept
  // separate from `wallpapersModel` so opening the screen never disturbs the
  // wallpapers grid's own load/scroll state. A plain JS array, not a ListModel:
  // assigning it is O(1), while a ListModel needed one `append` per row and
  // blocked the first paint of the screen for about a second on big themes.
  property var customCatalogItems: []

  // What the themes list and cursor read from.
  readonly property var activeThemesModel: filterText === "" ? themesModel : themesDisplayModel

  function rebuildThemeDisplay() {
    themesDisplayModel.clear()
    for (var i = 0; i < themesModel.count; i++) {
      var row = themesModel.get(i)
      if (Model.themeMatches(row, filterText)) themesDisplayModel.append(row)
    }
    // ListModel.get() is not a tracked dependency: bump so `selectedTheme`
    // (and the detail pane) re-read the rebuilt rows.
    themesRevision++
  }

  // What the wallpapers grid and cursor read from: the raw model while no
  // filter is active, else the rebuilt display model.
  readonly property var activeWallpapersModel:
    (wallpaperFilterText === "" && collectionFilter === "")
      ? wallpapersModel : wallpapersDisplayModel

  function rebuildWallpaperDisplay() {
    wallpapersDisplayModel.clear()
    for (var i = 0; i < wallpapersModel.count; i++) {
      var row = wallpapersModel.get(i)
      if (Model.wallpaperMatches(row, wallpaperFilterText, collectionFilter, settings.favorites))
        wallpapersDisplayModel.append(row)
    }
    wallpapersRevision++
  }

  // Collections present in the open theme, as Dropdown options ("All
  // collections" first, then "Favorites"). The Favorites entry is always
  // present: the filter can be selected before starring anything (showing its
  // empty state), and the label never falls back to the internal sentinel.
  // `wallpapersRevision` makes the binding re-read the rows after a catalog
  // reload (`ListModel.get()` is not tracked).
  readonly property var collectionOptions: {
    var rev = wallpapersRevision
    var rows = []
    for (var i = 0; i < wallpapersModel.count; i++) rows.push(wallpapersModel.get(i))
    var opts = Model.collectionOptions(rows)
    opts.splice(1, 0, { value: Model.favoritesFilter(), label: "Favorites" })
    return opts
  }

  // Pretty name of the active collection filter ("" when showing all), so the
  // hero title can read "Osaka-jade / Countries". Uses the pending filter too:
  // when entering the wallpapers screen from Custom Install the rows are still
  // loading, and the title must already show the target collection instead of
  // rendering the theme alone and then correcting itself.
  readonly property string collectionLabel: {
    var active = collectionFilter !== "" ? collectionFilter : pendingCollectionFilter
    if (active === "") return ""
    var opts = collectionOptions
    for (var i = 0; i < opts.length; i++)
      if (opts[i].value === active) return String(opts[i].label)
    return Model.ucfirst(active)
  }

  // Theme highlighted in the master-detail themes screen. Depends on
  // `themesRevision` because reading rows through `ListModel.get()` is not a
  // tracked QML dependency.
  readonly property var selectedTheme: {
    var rev = themesRevision
    if (selectedIndex < 0 || selectedIndex >= activeThemesModel.count) return null
    return activeThemesModel.get(selectedIndex)
  }

  // Whether the highlighted theme is actually installed in Omarchy. When it is
  // not, installing its wallpapers is impossible, so the detail pane swaps the
  // Install buttons for a "Theme not installed" hint.
  readonly property bool selectedThemePresent: {
    var theme = selectedTheme
    return theme ? String(theme.themePresent) !== "0" : false
  }

  // Bulk-action guards: "install all"/"random install" are pointless when every
  // wallpaper is already present, just like "remove all" with nothing on disk.
  readonly property bool selectedThemeFull: {
    var theme = selectedTheme
    return !!theme && (theme.count || 0) > 0 && (theme.installed || 0) >= (theme.count || 0)
  }
  readonly property bool selectedThemeEmpty: {
    var theme = selectedTheme
    return !theme || (theme.installed || 0) <= 0
  }

  // Whether the wallpaper open in the preview is installed. Drives the status
  // dot and whether Install / Uninstall are actionable. `wallpapersRevision`
  // forces a re-read after the catalog reloads (`ListModel.get()` is not a
  // tracked dependency on its own).
  readonly property bool currentInstalled: {
    var rev = wallpapersRevision
    var item = currentItem()
    return !!item && String(item.installed) === "1"
  }

  // Whether the open wallpaper is the open theme's default. For the running
  // Omarchy theme that is the catalog `isDefault`; for any other theme it is the
  // remembered per-theme default, because the live background is unrelated.
  readonly property bool currentIsDefault: {
    var rev = wallpapersRevision
    return isThemeDefault(currentItem())
  }

  // Whether the open wallpaper is starred (global favourites).
  readonly property bool currentIsFavorite: {
    var rev = wallpapersRevision
    var favRev = settings.favoritesRevision
    var item = currentItem()
    return !!item && Model.isFavorite(settings.favorites, item.filename)
  }

  // Gap around the preview overlays (path pill / filmstrip), set to the card's
  // own content padding so they line up with the footer controls and the grids
  // instead of hugging the border.
  readonly property real overlayInset: root.contentMargin
  // Fill opacity of both bottom overlays, so they read identically over the
  // image (higher = more solid).
  readonly property real overlayFillAlpha: 0.55

  // Real image info of the open wallpaper: "2K" and "2560x1440".
  readonly property string currentResolution: {
    var rev = wallpapersRevision
    var item = currentItem()
    return item ? String(item.resolution || "") : ""
  }
  readonly property string currentDimensions: {
    var rev = wallpapersRevision
    var item = currentItem()
    if (!item || !item.width || !item.height) return ""
    return item.width + "x" + item.height
  }
  // File size of the open wallpaper, e.g. "0.3 MB"; empty when unknown.
  readonly property string currentSize: {
    var rev = wallpapersRevision
    var item = currentItem()
    return item ? Model.formatSize(item.sizeBytes) : ""
  }
  // Longest file name shown in the preview header before middle-elision.
  readonly property int fileNameMaxChars: 48
  // Same for the full install path in the bottom-left pill.
  readonly property int pathMaxChars: 72

  // Caption of the running overlay: what the action is doing. On the preview it
  // names the wallpaper's size; on the themes screen `currentItem()` is null, so
  // it falls back to the bulk action and the running theme's wallpaper count.
  readonly property string actionLabel: {
    var rev = wallpapersRevision
    // Closing random-default step of a custom install: a single file, shown as
    // "Finalizing…" so the count never drops to "Downloading 1…".
    if (customFinalStep) return "Finalizing…"
    var item = currentItem()
    var cmd = lastAction.length > 0 ? String(lastAction[0]) : ""
    if (cmd === "remove") return "Removing…"
    if (cmd === "uninstall-default") return "Clearing default…"
    if (cmd === "set-default" && (!item || String(item.installed) === "1"))
      return "Setting default…"
    if (item) {
      var size = Model.formatSize(item.sizeBytes)
      return size !== "" ? "Downloading " + size + "…" : "Downloading…"
    }
    if (cmd === "random-install")
      return "Shuffling in " + settings.shuffleCount + " wallpapers…"
    // The caption always describes the running action's own scope, fixed when
    // the action started (`actionScopeTotal`). It never falls back to the
    // theme's whole size: that read "750" for a 250-wallpaper collection.
    if (actionRunning && actionScopeTotal > 0)
      return "Downloading " + actionScopeTotal + " wallpapers…"
    return "Downloading…"
  }

  // Where the open wallpaper lives (or will live) on disk, `~`-shortened.
  readonly property string currentInstallPath: {
    var rev = wallpapersRevision
    var item = currentItem()
    if (!item) return ""
    var base = backgroundsDir
    var home = Quickshell.env("HOME")
    if (home !== "" && base.indexOf(home) === 0) base = "~" + base.slice(home.length)
    return base + "/" + themeName + "/" + item.filename
  }

  // The theme open in the wallpaper list, looked up by name: on that view
  // `selectedIndex` is a wallpaper index, so `selectedTheme` does not apply.
  readonly property var currentTheme: themeByName(themeName)
  readonly property bool currentThemeFull: {
    var theme = currentTheme
    return !!theme && (theme.count || 0) > 0 && (theme.installed || 0) >= (theme.count || 0)
  }
  readonly property bool currentThemeEmpty: {
    var theme = currentTheme
    return !theme || (theme.installed || 0) <= 0
  }

  // Footer progress follows the theme the running action works on (if any), so
  // browsing another theme never hides the operation actually in progress.
  // Idle, it shows the highlighted theme on the themes view and the open theme
  // on the wallpapers view (where `selectedIndex` is a wallpaper, not a theme).
  readonly property var progressTheme: {
    if (actionRunning && actionTheme !== "") {
      var running = themeByName(actionTheme)
      if (running) return running
    }
    return (view === "wallpapers" || view === "preview") ? currentTheme : selectedTheme
  }

  // URL of the selected theme's big image ("" unless on the themes view).
  readonly property string detailTargetUrl: {
    if (view !== "themes") return ""
    var theme = selectedTheme
    if (!theme) return ""
    return (theme.image && theme.image !== "") ? theme.image : theme.preview
  }

  // Detail pane sources. `detailImageShown` is the front frame (the cached
  // file once resolved); `detailBackdrop` is the previous frame, kept visible
  // underneath while the next one decodes so switching themes never flashes
  // black. Both are plain properties (not bindings) so a new selection can wait
  // for its cached file instead of dropping to the small remote preview.
  property string detailImageShown: ""
  property string detailBackdrop: ""

  // URL of the fullscreen preview's image ("" when installed or off-view).
  readonly property string previewTargetUrl: {
    if (view !== "preview" && view !== "wallpapers") return ""
    var item = currentItem()
    if (!item || String(item.installed) === "1") return ""
    return item.url
  }

  // "N installed · M available" summary shown in the themes footer.
  readonly property var themeCounts: {
    var rev = themesRevision
    var installed = 0
    var available = 0
    for (var i = 0; i < themesModel.count; i++) {
      if ((themesModel.get(i).installed || 0) > 0) installed++
      else available++
    }
    return { "installed": installed, "available": available }
  }

  // Global store across every theme: total wallpapers and how many are
  // installed locally. Shown as a pill in the hero, before Refresh.
  readonly property var globalCounts: {
    var rev = themesRevision
    var favRev = settings.favoritesRevision
    var wallpapers = 0
    var installed = 0
    for (var i = 0; i < themesModel.count; i++) {
      var theme = themesModel.get(i)
      wallpapers += (theme.count || 0)
      installed += (theme.installed || 0)
    }
    var favorites = 0
    for (var key in settings.favorites) if (settings.favorites[key]) favorites++
    return { "wallpapers": wallpapers, "installed": installed, "favorites": favorites }
  }

  // Status colors follow the Omarchy theme accent (Color.accent) instead of a
  // fixed brand color, so they adapt to the active theme. Installed reads at
  // full accent, installing/partial at a dimmer tint, available stays neutral.
  readonly property color statusInstalled: root.accent
  readonly property color statusInstalling: Util.alpha(root.accent, 0.55)

  // ---- lifecycle ------------------------------------------------------------
  // Set by `open()`: the next themes load lands the cursor on the active
  // Omarchy theme instead of the first row. Refreshes leave the selection be.
  property bool pendingThemeSelect: false
  // True once the active theme has been selected for this shell session, so
  // reopening the overlay keeps the theme the user last left selected. It
  // resets on a shell restart, when we re-land on the active theme once.
  property bool themesInitialized: false
  // Last cursor position on the themes list, tracked while that view is shown
  // so closing from another screen still reopens on the right theme.
  property int themesCursorIndex: 0

  function open(payload) {
    opened = true
    view = "themes"
    cursorActive = true
    // Only the first open of this shell session lands on the active theme;
    // afterwards reopening keeps the theme the user last selected.
    if (!themesInitialized) {
      selectedIndex = 0
      pendingThemeSelect = true
    } else {
      pendingThemeSelect = false
      selectedIndex = Math.max(0,
        Math.min(activeThemesModel.count - 1, themesCursorIndex))
    }
    statusText = ""
    filterText = ""
    wallpaperFilterText = ""
    collectionFilter = ""
    searching = false
    filterFocus = -1
    themeFocus = -1
    actionTheme = ""
    actionCancelled = false
    actionRunning = false
    actionClearsChecks = false
    clearWallpaperSelection()
    addSourceSoon = false
    customThemeName = ""
    customSelection = 0
    pendingCustomRandomDefault = ""
    wallpaperReturnCustom = false
    // While the first-run cache warm-up is still running, do not start a
    // competing `manager.sh themes` (its `ensure_datasets` would download the
    // same files): show the "Initiating…" overlay and let the warm trigger the
    // load when it finishes.
    if (warming) {
      themesPending = true
      busy = true
      setStatus("Initiating…")
    } else {
      loadThemes()
    }
  }

  function close() {
    // A dropdown popup is a separate window and would outlive the overlay.
    if (wallpapersCollectionDropdown() && wallpapersCollectionDropdown().popupOpen)
      wallpapersCollectionDropdown().close()
    opened = false
  }

  // Global close from any screen (`q` and `x`/`X`). Ignored while an action
  // runs, matching the hero Close button: Esc is what cancels a running task.
  function requestClose() {
    if (actionRunning) return
    close()
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { keys.forceActiveFocus() })

  // manager.sh keys its caches (datasets + images) from WALLPAPER_MANAGER_ID, so
  // the official and developer installs never share files, and reads the
  // install parallelism (WALLPAPER_MANAGER_PARALLEL) and the bulk-install file
  // cap (WALLPAPER_MANAGER_MAX_FILES) from Setup → Download. `/usr/bin/env`
  // passes them without relying on Process.environment's QVariantHash type.
  function scriptCmd(args) {
    return ["/usr/bin/env",
      "WALLPAPER_MANAGER_ID=" + pluginId,
      "WALLPAPER_MANAGER_PARALLEL=" + settings.parallelDownloads,
      "WALLPAPER_MANAGER_MAX_FILES=" + settings.maxLocalFiles,
      "WALLPAPER_MANAGER_MAX_DISK_GB=" + settings.maxDiskGb,
      scriptPath].concat(args)
  }

  function setStatus(text) {
    statusText = String(text || "")
  }

  function loadThemes() {
    busy = true
    setStatus("Loading themes…")
    themesProc.running = true
    loadLimits()
  }

  // Refresh the local usage used by `storageLimitReached`.
  function loadLimits() {
    limitsProc.running = true
  }

  // Row of the active Omarchy theme, or the first row when it is not part of
  // the collection (or unknown).
  function activeThemeIndex() {
    var target = Model.normalizeSlug(activeThemeSlug)
    if (target === "") return 0
    for (var i = 0; i < activeThemesModel.count; i++) {
      if (Model.normalizeSlug(activeThemesModel.get(i).name) === target) return i
    }
    return 0
  }

  // ---- search ---------------------------------------------------------------
  // The filter of the view being searched, so the shared key handler can read
  // and edit it without branching on the view everywhere.
  function currentFilter() {
    return view === "themes" ? filterText : wallpaperFilterText
  }

  function applyFilter(text) {
    if (view === "themes") setThemeFilter(text)
    else setWallpaperFilter(text)
  }

  function clearFilter() {
    applyFilter("")
  }

  function startSearch() {
    if (actionRunning) return
    if ((view !== "themes" && view !== "wallpapers") || searching) return
    if (view === "wallpapers") filterFocus = 1
    searching = true
  }

  // Leave the search editor but keep the filter, so Tab can cycle back in/out.
  function stopSearch() {
    searching = false
    if (view === "wallpapers") filterFocus = -1
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // ---- filter row focus -----------------------------------------------------
  // The wallpapers filter row (collection dropdown, search, Select all, Clear)
  // is a focusable strip like the Setup screen's: arrows / Tab move between the
  // four controls, Enter / Space activate the focused one, Down returns to the
  // wallpapersView.grid. `searching` is implied by the search field owning focus, so landing
  // on it starts editing and leaving it stops.
  readonly property bool filterRowFocused: view === "wallpapers" && filterFocus >= 0

  function focusFilterField(index) {
    if (view !== "wallpapers") return
    filterFocus = Math.max(0, Math.min(3, index))
    searching = filterFocus === 1
  }

  // Enter the row from the grid (Up on the first row, `/` or Tab). The search
  // field is the natural landing spot, editing straight away.
  function enterFilterRow(index) {
    if (view !== "wallpapers") return
    focusFilterField(index === undefined ? 1 : index)
  }

  // Back to the grid, keeping any active filter.
  function leaveFilterRow() {
    filterFocus = -1
    searching = false
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // Move between the row controls (clamped at both ends). Landing on the
  // search field opens the editor; leaving it closes the editor.
  function moveFilterField(dir) {
    if (!filterRowFocused) return
    var next = Math.max(0, Math.min(3, filterFocus + dir))
    if (next === filterFocus) return
    filterFocus = next
    searching = next === 1
    if (searching) Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // ---- themes action-row focus ----------------------------------------------
  // The themes screen is a master-detail: Tab moves the focus from the theme
  // list into the detail action row and back. Once in the row, Left/Right walk
  // the buttons, Enter/Space activate the focused one, Down/Esc/Tab return to
  // the list. Mirrors the wallpapers filter-row model, so the bulk actions need
  // no mouse and no memorised letter shortcuts.
  // Actions reachable with the keyboard on the themes detail row, in visual
  // order. Buttons that cannot run (absent theme, already full, storage cap,
  // nothing installed) are skipped so Tab/arrows never land on a dead control.
  readonly property var themeActionKeys: {
    var all = selectedThemePresent
      ? ["browse", "install", "shuffle", "uninstall", "custom"]
      : ["browse", "custom"]
    var out = []
    for (var i = 0; i < all.length; i++)
      if (themeActionEnabled(all[i])) out.push(all[i])
    return out
  }

  function themeActionEnabled(key) {
    if (key === "browse" || key === "custom") return true
    if (!selectedThemePresent || actionRunning) return false
    if (key === "install" || key === "shuffle")
      return !selectedThemeFull && !storageLimitReached
    if (key === "uninstall") return !selectedThemeEmpty
    return false
  }

  function themeActionKeyAt(index) {
    var keys = themeActionKeys
    return (index >= 0 && index < keys.length) ? keys[index] : ""
  }

  function themeActionFocused(key) {
    return view === "themes" && themeFocus >= 0 && themeActionKeyAt(themeFocus) === key
  }

  function enterThemeActions() {
    if (view !== "themes") return
    themeFocus = Math.max(0, Math.min(themeFocus, themeActionKeys.length - 1))
  }

  function leaveThemeActions() {
    themeFocus = -1
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function moveThemeAction(dir) {
    if (view !== "themes" || themeFocus < 0) return
    themeFocus = Math.max(0, Math.min(themeActionKeys.length - 1, themeFocus + dir))
  }

  function activateThemeAction() {
    if (view !== "themes" || themeFocus < 0) return
    switch (themeActionKeyAt(themeFocus)) {
    case "browse": selectTheme(selectedIndex); return
    case "install":
      if (selectedThemePresent && !selectedThemeFull && !storageLimitReached)
        actionInstallTheme()
      return
    case "shuffle":
      if (selectedThemePresent && !selectedThemeFull && !storageLimitReached)
        actionRandomInstall()
      return
    case "uninstall":
      if (selectedThemePresent && !selectedThemeEmpty) actionRemoveThemeAll()
      return
    case "custom": openCustomInstall(); return
    }
  }

  // ---- custom install screen ------------------------------------------------
  // The option rows of the custom screen, in visual order: the whole theme
  // first, then the favourites available here, then one per collection, then
  // the random sample and "select only". `customRevision` makes the binding
  // re-read the ListModel; `settings.favoritesRevision` makes the Favorites row
  // follow star changes.
  readonly property var customRows: {
    var rev = customRevision
    var favRev = settings.favoritesRevision
    var items = customCatalogItems
    var totals = Model.wallpaperTotals(items)
    var rows = [{
      kind: "full",
      label: "Full collections",
      hint: "Every wallpaper of the theme",
      count: totals.count,
      installed: totals.installed,
      sizeBytes: totals.sizeBytes,
      resolution: totals.resolution
    }]
    var fav = Model.favoritesSummary(items, settings.favorites)
    if (fav.count > 0) {
      rows.push({
        kind: "favorites",
        label: "Favorites",
        hint: "Your starred wallpapers available in this theme",
        count: fav.count,
        installed: fav.installed,
        sizeBytes: fav.sizeBytes,
        resolution: fav.resolution,
        filenames: fav.filenames
      })
    }
    var collections = Model.collectionSummary(items)
    for (var j = 0; j < collections.length; j++) {
      var c = collections[j]
      rows.push({
        kind: "collection",
        collection: c.name,
        label: "Full " + c.label,
        hint: "Every wallpaper in the collection",
        count: c.count,
        installed: c.installed,
        sizeBytes: c.sizeBytes,
        resolution: c.resolution
      })
    }
    rows.push({
      kind: "shuffle",
      label: "Shuffle (" + settings.shuffleCount + ")",
      hint: "Random sample, same as the themes screen",
      count: settings.shuffleCount,
      installed: 0,
      sizeBytes: 0,
      resolution: totals.resolution
    })
    rows.push({
      kind: "selectOnly",
      label: "Select only",
      hint: "Go to the grid and choose by hand",
      count: 0,
      installed: 0,
      sizeBytes: 0,
      resolution: ""
    })
    return rows
  }

  // The switch is the row right after the options.
  readonly property int customSwitchRow: customRows.length

  // The highlighted option row (null on the switch row).
  readonly property var customSelectedRow:
    (customSelection >= 0 && customSelection < customRows.length)
      ? customRows[customSelection] : null

  // Footer Install is enabled only for the bulk rows that still have something
  // to install: Full collections, Favorites, a collection, or Shuffle. Select
  // only and the switch row keep it disabled, as does a fully-installed scope.
  readonly property bool customCanInstall: {
    var row = customSelectedRow
    if (!row || !customThemePresent || actionRunning) return false
    if (row.kind === "selectOnly") return false
    var full = customRows.length > 0 ? customRows[0] : null
    if (row.kind === "shuffle")
      return !!full && (full.count || 0) > (full.installed || 0)
    return (row.count || 0) > (row.installed || 0)
  }

  // Footer Uninstall is enabled only for Full collections / Favorites / a
  // collection that actually has files on disk.
  readonly property bool customCanRemove: {
    var row = customSelectedRow
    if (!row || !customThemePresent || actionRunning) return false
    if (row.kind !== "full" && row.kind !== "collection" && row.kind !== "favorites")
      return false
    return (row.installed || 0) > 0
  }

  // Theme object being configured, and the first nine preview URLs for the 3x3
  // grid. `customRevision` makes both re-read the model.
  readonly property var customTheme: themeByName(customThemeName)
  // True when the configured theme is the one Omarchy is currently running, so
  // the end-of-install random default may touch the live background.
  readonly property bool customThemeIsActive: customThemeName !== ""
    && root.activeThemeSlug !== ""
    && Model.normalizeSlug(customThemeName) === Model.normalizeSlug(root.activeThemeSlug)
  // Preview URLs for the 3x3 grid, resolved once when the catalog loads
  // (preferring an already-prewarmed local file). A plain property, not a live
  // binding: swapping the source mid-render made the first open flash as all
  // nine images re-rendered.
  property var customPreviews: []

  // Warm the 3x3 previews into the disk cache (best-effort), so reopening the
  // screen — or restarting the shell — loads them from disk instead of the
  // network. Skips what is already cached and never competes with an action.
  function prefetchCustomPreviews() {
    if (actionRunning) return
    var urls = []
    for (var i = 0; i < customCatalogItems.length && urls.length < 9; i++) {
      var row = customCatalogItems[i]
      if (!row || !row.preview) continue
      var url = String(row.preview)
      if (url.indexOf("http") !== 0) continue
      if (cachedImagePath(url) === "") urls.push(url)
    }
    if (urls.length === 0) return
    if (prewarmProc.running) {
      pendingPrefetch = urls
      return
    }
    startPrewarm(urls)
  }
  // Setup's default resolution, indicated on the cards (not enforced yet).
  readonly property string setupResolution: settings.resolution
  readonly property bool randomDefaultOnInstall: settings.randomDefaultOnInstall

  function takeCustomCursor(index) {
    if (view !== "custom") return
    customSelection = index
  }

  function toggleRandomDefaultOnInstall() {
    if (view !== "custom") return
    settings.randomDefaultOnInstall = !settings.randomDefaultOnInstall
  }

  function customRowFocused(index) {
    return view === "custom" && customSelection === index
  }

  function openCustomInstall() {
    var theme = selectedTheme
    if (!theme) return
    customThemeName = theme.name
    customThemeCatalogUrl = theme.catalogUrl
    customThemePresent = selectedThemePresent
    customSelection = 0
    customLoading = true
    // Clear before switching the view: otherwise the screen briefly renders the
    // previous theme's cards (ready = true) before the data empties.
    customCatalogItems = []
    customPreviews = []
    customRevision++
    view = "custom"
    cursorActive = true
    themeFocus = -1
    setStatus("")
    // Serve the cached parse when we have it (the common case: the grid or the
    // idle prefetch already read this theme); only a cold theme spawns the
    // process, so a cached open has no "Loading catalog…" flash.
    var cached = customCatalogCache[theme.name]
    if (cached) applyCustomCatalog(theme.name, cached)
    else loadCustomCatalog()
  }

  function closeCustomInstall() {
    view = "themes"
    cursorActive = true
    setStatus("")
  }

  function loadCustomCatalog(silent) {
    if (customThemeName === "") { customReloading = false; return }
    // A silent reload (after a cancelled action) refreshes the counts without
    // raising the visible "Loading catalog…" overlay: the user stopped an
    // install and must not see it flash open again on its own.
    if (!silent) customLoading = true
    customSerial++
    customCatalogProc.requestedSerial = customSerial
    customCatalogProc.requestedTheme = customThemeName
    customCatalogProc.command = scriptCmd(["catalog", customThemeName, customThemeCatalogUrl])
    customCatalogProc.running = true
  }

  // Fill the model and the 3x3 previews from a parsed catalog, and remember it
  // in `customCatalogCache`. Shared by the process path and the cache-hit path,
  // so the model and its derived state are built in exactly one place.
  function applyCustomCatalog(theme, rows) {
    if (theme === "") return
    customCatalogCache[theme] = rows
    if (theme !== customThemeName) return
    // Assign the whole array at once (O(1)) instead of one model append per row.
    customCatalogItems = rows
    customRevision++
    customLoading = false
    // Resolve the 3x3 previews once, now, so they are not swapped later.
    var previews = []
    for (var k = 0; k < rows.length && previews.length < 9; k++) {
      var prow = rows[k]
      if (!prow || !prow.preview) continue
      var purl = String(prow.preview)
      var plocal = imagePathByUrl[purl]
      previews.push(plocal ? String(plocal) : purl)
    }
    customPreviews = previews
    prefetchCustomPreviews()
  }

  // Idle prefetch: read a theme's catalog into the in-memory cache before the
  // user opens Custom Install, so the screen has nothing to load. One process
  // at a time; the last requested theme wins via `pendingCustomPrefetch`.
  function prefetchCustomCatalog(theme) {
    if (theme === "" || customCatalogCache[theme]) return
    var t = themeByName(theme)
    if (!t || !String(t.catalogUrl)) return
    if (catalogPrefetchProc.running) {
      pendingCustomPrefetch = theme
      return
    }
    catalogPrefetchProc.requestedTheme = theme
    catalogPrefetchProc.command = scriptCmd(["catalog", theme, t.catalogUrl])
    catalogPrefetchProc.running = true
  }

  // Warm every theme's catalog once, in the given priority order (the selected
  // theme first), so the in-memory cache covers them all and Custom Install
  // never waits on a `manager.sh catalog` read.
  function prefetchAllCatalogs() {
    var queue = []
    if (selectedIndex >= 0 && selectedIndex < activeThemesModel.count)
      queue.push(activeThemesModel.get(selectedIndex).name)
    for (var i = 0; i < activeThemesModel.count; i++) {
      var name = activeThemesModel.get(i).name
      if (queue.indexOf(name) < 0) queue.push(name)
    }
    customPrefetchQueue = queue
    advanceCustomPrefetch()
  }

  // Keep the one-at-a-time prefetch fed from the queue.
  function advanceCustomPrefetch() {
    if (catalogPrefetchProc.running) return
    while (customPrefetchQueue.length > 0) {
      var next = customPrefetchQueue[0]
      customPrefetchQueue = customPrefetchQueue.slice(1)
      if (!customCatalogCache[next]) { prefetchCustomCatalog(next); return }
    }
  }

  function moveCustomCursor(dir) {
    if (view !== "custom") return
    customSelection = Math.max(0, Math.min(customSwitchRow, customSelection + dir))
  }

  function activateCustom() {
    if (view !== "custom") return
    if (customSelection >= customSwitchRow) {
      settings.randomDefaultOnInstall = !settings.randomDefaultOnInstall
      return
    }
    var row = customRows[customSelection]
    if (!row) return
    if (row.kind === "selectOnly") { selectCustomTheme(); return }
    // Same gate as the footer button: a fully-installed scope must not start a
    // download from Enter either.
    if (!customCanInstall) return
    executeCustomRow(row)
  }

  function executeCustomRow(row) {
    if (actionRunning) return
    var theme = customThemeName
    if (theme === "") return
    // The switch remembers whether to pick a random default once the install
    // finishes; the chain is applied in `actionProc.onExited`.
    pendingCustomRandomDefault = settings.randomDefaultOnInstall ? theme : ""
    if (row.kind === "full") runAction(["install", theme])
    else if (row.kind === "favorites")
      runAction(["install", theme, "--bulk"].concat(row.filenames || []))
    else if (row.kind === "collection")
      runAction(["install", theme, "--collection", String(row.collection)])
    else if (row.kind === "shuffle")
      runAction(["random-install", theme, String(settings.shuffleCount)])
  }

  // Footer "Install": runs the highlighted choice (same as Enter on the card).
  function executeCustomInstall() {
    if (view !== "custom" || actionRunning) return
    if (customSelection >= customSwitchRow) return
    var row = customRows[customSelection]
    if (!row) return
    if (row.kind === "selectOnly") { selectCustomTheme(); return }
    if (!customCanInstall) return
    executeCustomRow(row)
  }

  // Footer "Uninstall": removes the highlighted scope — the whole theme on Full
  // collections, just the collection otherwise.
  function executeCustomRemove() {
    if (view !== "custom" || actionRunning) return
    if (!customCanRemove) return
    var row = customSelectedRow
    if (!row || customThemeName === "") return
    busy = true
    if (row.kind === "collection") {
      setStatus("Removing " + row.label + "…")
      runAction(["remove", customThemeName, "--collection", String(row.collection)])
    } else if (row.kind === "favorites") {
      setStatus("Removing " + row.label + "…")
      runAction(["remove", customThemeName].concat(row.filenames || []))
    } else {
      setStatus("Removing all of " + customThemeName + "…")
      runAction(["remove", customThemeName])
    }
  }

  // End-of-install random default (the custom screen's switch). Only the
  // configured theme is touched: when it is the running one the background is
  // set live, otherwise the pick is remembered per theme and the file is made
  // sure to land on disk — exactly like `actionToggleDefault`, so a random
  // default on another theme never replaces the current desktop background.
  function applyCustomRandomDefault(theme) {
    if (theme === "" || customCatalogItems.length === 0) return
    // Pick among the wallpapers already installed for this theme, not the whole
    // catalogue: the closing default must be a file the install just put on
    // disk. Picking from the full catalogue could download an extra wallpaper
    // the user never asked for, which then showed up as the installed count
    // climbing by one only after a reopen.
    var installed = []
    for (var i = 0; i < customCatalogItems.length; i++) {
      if (String(customCatalogItems[i].installed) === "1") installed.push(customCatalogItems[i])
    }
    if (installed.length === 0) return
    var item = installed[Math.floor(Math.random() * installed.length)]
    if (!item) return
    // Closing step: the overlay reads "Finalizing…", never "Downloading 1…".
    customFinalStep = true
    if (customThemeIsActive) {
      busy = true
      setStatus("Setting a random default for " + Model.ucfirst(theme) + "…")
      runAction(["set-default", theme, item.filename, item.url])
      return
    }
    settings.setThemeDefault(theme, item.filename, imageRelativePath(item.url))
    if (String(item.installed) !== "1") {
      busy = true
      setStatus("Installing " + item.name + "…")
      runAction(["install", theme, item.filename])
    } else {
      setStatus("Default for " + Model.ucfirst(theme)
        + " set — applies when you switch to it")
      customFinalStep = false
    }
  }

  // "Select only": leave for the wallpapers grid of the configured theme.
  function selectCustomTheme() {
    for (var i = 0; i < activeThemesModel.count; i++) {
      if (activeThemesModel.get(i).name === customThemeName) {
        selectTheme(i)
        // Esc from the grid must come back here, state preserved.
        wallpaperReturnCustom = true
        return
      }
    }
  }

  // `b`: like Select only, but when a collection card is highlighted the grid
  // opens already narrowed to that collection. The Favorites card narrows to
  // the Favorites filter instead, like picking it from the collection dropdown.
  function browseCustom() {
    if (view !== "custom" || actionRunning) return
    var row = customSelectedRow
    var collection = ""
    if (row && row.kind === "collection") collection = String(row.collection)
    else if (row && row.kind === "favorites") collection = Model.favoritesFilter()
    for (var i = 0; i < activeThemesModel.count; i++) {
      if (activeThemesModel.get(i).name === customThemeName) {
        selectTheme(i)
        // Set AFTER selecting: the catalog loads asynchronously, so the filter
        // is read with the rows and the dropdown never shows the raw value
        // first. `selectTheme` clears the live filter but not this pending one.
        pendingCollectionFilter = collection
        wallpaperReturnCustom = true
        return
      }
    }
  }

  // Apply the filter and rebuild the visible list. The index resets to the top
  // so the cursor always sits on a valid row.
  function setThemeFilter(text) {
    var next = String(text || "")
    if (next === filterText) return
    filterText = next
    if (filterText !== "") rebuildThemeDisplay()
    selectedIndex = 0
    cursorActive = true
    refreshDetailShown()
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { scrollToList(0, ListView.Beginning) })
  }

  function setWallpaperFilter(text) {
    var next = String(text || "")
    if (next === wallpaperFilterText) return
    wallpaperFilterText = next
    if (wallpaperFilterText !== "" || collectionFilter !== "") rebuildWallpaperDisplay()
    selectedIndex = 0
    cursorActive = true
    if (activeWallpapersModel.count > 0)
      Qt.callLater(function() { scrollToGrid(0, GridView.Beginning) })
  }

  // Narrow the grid to one collection ("" = all). Shares the rebuild/cursor
  // reset with the text filter so the two compose.
  function setCollectionFilter(value) {
    var next = String(value || "")
    if (next === collectionFilter) return
    collectionFilter = next
    if (wallpaperFilterText !== "" || collectionFilter !== "") rebuildWallpaperDisplay()
    if (next === Model.favoritesFilter()) pickFavoritesBackdrop()
    selectedIndex = 0
    cursorActive = true
    if (activeWallpapersModel.count > 0)
      Qt.callLater(function() { scrollToGrid(0, GridView.Beginning) })
  }

  // The dataset carries a readable `title` ("Tokyo Night"); the tiles show it
  // uppercased. Fallback for older datasets: normalize the slug. See Model.js.
  function selectTheme(index) {
    if (index < 0 || index >= activeThemesModel.count) return
    var item = activeThemesModel.get(index)
    lastThemeIndex = index
    // Entered from the theme list: Esc goes back there (not to custom install).
    wallpaperReturnCustom = false
    // Drop the previous theme's rows first: the wallpapers GridView delegates
    // survive the trip through the themes view, so leaving them alive while
    // `themeName` changes makes them re-resolve their local file path against
    // the new theme and log a pile of "Cannot open" warnings.
    wallpapersModel.clear()
    wallpaperFilterText = ""
    collectionFilter = ""
    // Cleared unless the caller set it right after (Browse from Custom Install).
    pendingCollectionFilter = ""
    filterFocus = -1
    themeFocus = -1
    // Checks belong to the theme being left.
    clearWallpaperSelection()
    themeName = item.name
    themeCatalogUrl = item.catalogUrl
    view = "wallpapers"
    var remembered = wallpaperCursorByTheme[item.name]
    pendingWallpaperIndex = (remembered === undefined || remembered === null)
      ? 0 : remembered
    pendingWallpaperSelect = true
    selectedIndex = pendingWallpaperIndex
    loadWallpapers()
  }

  function loadWallpapers() {
    // Invalidate any in-flight result first: the user may have switched theme,
    // and a stale catalog must never populate this theme's model (bug #8).
    catalogSerial++
    if (catalogProc.running) {
      catalogPending = true
      return
    }
    startCatalog()
  }

  // Start the request for the current theme. Only called while `catalogProc` is
  // idle, so the `command` assignment is accepted.
  function startCatalog() {
    catalogProc.requestedSerial = catalogSerial
    catalogProc.requestedTheme = themeName
    busy = true
    setStatus("Loading wallpapers of " + themeName + "…")
    wallpapersModel.clear()
    wallpapersRevision++
    catalogProc.command = scriptCmd(["catalog", themeName, themeCatalogUrl])
    catalogProc.running = true
  }

  function goBack() {
    // Remember the wallpaper cursor so re-entering this theme resumes here.
    if (themeName !== "") wallpaperCursorByTheme[themeName] = selectedIndex
    filterFocus = -1
    themeFocus = -1
    searching = false
    // Entered from the custom-install screen ("Select only"): go back there with
    // its state intact, restoring the theme cursor it had.
    if (wallpaperReturnCustom) {
      wallpaperReturnCustom = false
      selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, lastThemeIndex))
      cursorActive = true
      view = "custom"
      setStatus("")
      return
    }
    view = "themes"
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, lastThemeIndex))
    cursorActive = true
    setStatus("")
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { scrollToList(root.selectedIndex, ListView.Contain) })
  }

  // Leaf screens (Help / Setup) open from any screen and Esc / Back retraces
  // every step. A stack, not a single "return view": two single properties could
  // point at each other (Help opened from Setup and Setup opened from Help) and
  // loop Esc forever. Each leaf records where it came from.
  property var leafReturnStack: []

  function pushLeafReturn() {
    // A leaf opened from a base screen starts a fresh path; opened from the
    // sibling leaf it extends the current one.
    leafReturnStack = (view === "help" || view === "setup")
      ? leafReturnStack.concat([view])
      : [view]
  }

  function popLeafReturn() {
    var stack = leafReturnStack
    var target = stack.length > 0 ? stack[stack.length - 1] : "themes"
    leafReturnStack = stack.slice(0, Math.max(0, stack.length - 1))
    return target
  }

  // Go to a retraced view, with the cursor handling the leaves used to inline
  // (themes keeps the cursor, wallpapers re-scrolls to it).
  function applyLeafReturn(target) {
    cursorActive = true
    setStatus("")
    if (target === "themes") {
      view = "themes"
      selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, selectedIndex))
      if (activeThemesModel.count > 0)
        Qt.callLater(function() { scrollToList(root.selectedIndex, ListView.Contain) })
      return
    }
    view = target
    if (target === "wallpapers")
      Qt.callLater(function() { scrollToGrid(root.selectedIndex, GridView.Contain) })
  }

  function openHelp() {
    if (view === "help") return
    pushLeafReturn()
    view = "help"
    cursorActive = true
    setStatus("")
  }

  // Open Help on a specific topic file (used by the Favorites empty state).
  // Falls back to the default topic when the file is unknown.
  function openHelpTopic(file) {
    var items = Model.helpFlatItems(root.helpIndex)
    for (var i = 0; i < items.length; i++) {
      if (items[i].file === file) {
        settings.setupHelpSelectedFlat = i
        settings.setupHelpSelectedFile = file
        break
      }
    }
    openHelp()
  }

  function closeHelp() {
    applyLeafReturn(popLeafReturn())
  }

  // Setup screen: a placeholder screen like Help but empty. Reached with `s`
  // on any screen or from the setup buttons; Esc / Back returns to the origin.
  function openSetup() {
    if (view === "setup") return
    pushLeafReturn()
    view = "setup"
    cursorActive = true
    setStatus("")
  }

  function closeSetup() {
    settings.commitSetupEdit()
    applyLeafReturn(popLeafReturn())
  }

  // Open Setup on the Download section: the storage-limit banner links here.
  function openSetupDownload() {
    if (view !== "setup") openSetup()
    settings.selectSetupSection("download")
  }

  // Hero "Wallpaper manager" button on Help: jump straight to the theme list
  // from anywhere in the guide (unlike closeHelp, which retraces the origin).
  function showThemes() {
    var origin = leafReturnStack.length > 0 ? leafReturnStack[0] : "themes"
    leafReturnStack = []
    view = "themes"
    cursorActive = true
    themeFocus = -1
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1,
      origin === "themes" ? selectedIndex : lastThemeIndex))
    setStatus("")
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { scrollToList(root.selectedIndex, ListView.Contain) })
  }

  function refresh() {
    if (actionRunning) return
    if (view === "themes") loadThemes()
    else if (view === "wallpapers" || view === "preview") loadWallpapers()
    else if (view === "custom") loadCustomCatalog()
  }

  // ---- cursor state machine -------------------------------------------------
  // Ui/PanelKeyCatcher.qml turns raw keys into semantic signals; the panel
  // keeps the state machine. The themes screen is a vertical ListView, the
  // wallpapers screen a GridView (which has no `columns` in Qt 6, so the column
  // count is computed by hand — see docs/DEVELOPMENT.md).
  function activeCount() {
    return view === "themes" ? activeThemesModel.count : activeWallpapersModel.count
  }

  function positionActive(index) {
    if (view === "themes") scrollToList(index, ListView.Contain)
    else scrollToGrid(index, GridView.Contain)
  }

  function stepCursor(step) {
    var count = activeCount()
    if (count === 0) return

    cursorActive = true
    selectedIndex = Model.stepIndex(selectedIndex, step, count)
    positionActive(selectedIndex)
    // Warm the catalog of the theme under the cursor, so Custom Install opens
    // without a load.
    if (view === "themes" && selectedIndex < activeThemesModel.count)
      prefetchCustomCatalog(activeThemesModel.get(selectedIndex).name)
  }

  function moveCursor(dx, dy) {
    // While an action runs the UI is frozen: only Esc is accepted (it cancels),
    // so arrows/h/j/k must not move the cursor on any screen.
    if (actionRunning) return
    if (view === "setup") {
      settings.moveSetupCursor(dx, dy)
      return
    }
    if (view === "help") {
      helpMoveSelection(dy !== 0 ? dy : dx)
      return
    }
    if (view === "preview") {
      previewNext(dx !== 0 ? dx : dy)
      return
    }
    if (view === "custom") {
      moveCustomCursor(dy !== 0 ? dy : dx)
      return
    }
    if (view === "themes") {
      // The action row owns Left/Right; Up/Down leave it for the list.
      if (themeFocus >= 0) {
        if (dx !== 0) moveThemeAction(dx > 0 ? 1 : -1)
        else if (dy !== 0) leaveThemeActions()
        return
      }
      var step = dy !== 0 ? dy : dx
      // Up from the first row moves the focus into the search field.
      if (step < 0 && selectedIndex === 0) {
        startSearch()
        return
      }
      stepCursor(step)
      return
    }

    // The filter row owns the arrows while it is focused (and not typing — the
    // search editor handles its own keys through the card fallback): Left/Right
    // walk the controls, Down drops back to the wallpapers grid.
    if (filterRowFocused && !searching) {
      if (dx !== 0) {
        moveFilterField(dx > 0 ? 1 : -1)
        return
      }
      if (dy > 0) leaveFilterRow()
      return
    }

    // Up from the first row moves the focus into the filter row (search field).
    if (dy < 0 && selectedIndex < wallpapersColumns()) {
      enterFilterRow(1)
      return
    }
    stepCursor(dx !== 0 ? dx : dy * wallpapersColumns())
  }

  // PageUp/PageDown: jump a whole visible page of tiles (rows on screen ×
  // columns; rows only on the themes list). PanelKeyCatcher does not map these
  // keys, so they bubble up to the card's Keys.onPressed fallback.
  function pageCursor(dir) {
    if (actionRunning) return
    // Setup: page between sections (clamped at the ends).
    if (view === "setup") {
      settings.pageSetupSection(dir)
      return
    }
    // Help: page through the central topic content.
    if (view === "help") {
      // Scrolling the topic body only needs the built view.
      if (helpView()) helpView().scrollPage(dir)
      return
    }
    if (view === "preview") {
      previewNext(dir)
      return
    }
    if (view === "custom") {
      moveCustomCursor(dir * 3)
      return
    }
    if (view === "themes") {
      var rows = Math.max(1, Math.floor(themesListHeight() / root.themeRowHeight))
      stepCursor(dir * rows)
      return
    }

    var visibleRows = Math.max(1, Math.floor(wallpapersGridHeight() / wallpapersCellHeight()))
    stepCursor(dir * visibleRows * wallpapersColumns())
  }

  // Setup screen keyboard hooks: all the navigation state lives in `settings`,
  // but two actions need the live view (the interval popup it owns and the
  // rotate-now signal). Guarded so they are safe while the screen is not built.
  function setupActivateCursor() {
    // Interval time is a dropdown: open its real list, exactly like a click.
    if (settings.setupNavArea !== "content") return
    var row = settings.setupNavRows[settings.setupContentRow]
    if (row === "interval") {
      if (settings.activateSetupCursor) settings.activateSetupCursor()
      return
    }
    if (settings.setupEditing) { settings.commitSetupEdit(); return }
    if (settings.setupAdjustableRows.indexOf(row) >= 0) {
      settings.startSetupEdit(); return
    }
    // The Updates rows are plain panel-owned actions.
    if (settings.setupSection === "version") {
      if (row === "changelog") { openExternalUrl(root.pluginReleasesUrl); return }
      if (row === "cdnChangelog") { openExternalUrl(root.wallpapersReleasesUrl); return }
      if (row === "security") { openExternalUrl(root.marketplaceUrl); return }
      if (row === "proposeFeature") { openExternalUrl(root.pluginIssuesUrl); return }
      if (row === "checkVersion") { checkForUpdates(); return }
    }
    settings.activateSetupRow()
  }

  function setupSetRotateBusy(busy) {
    settings.rotateBusy = busy
  }

  // Help screen keyboard hooks. The cursor state lives in `settings`, so the
  // move/activate actions are computed from it and the view only mirrors it
  // back for scrolling; only the URL opening needs the built view.
  function helpMoveSelection(delta) {
    var target = settings.setupHelpSelectedFlat + delta
    helpSelectFlat(target)
  }

  function helpSelectFlat(target) {
    var total = helpNavTotal()
    if (target < 0 || target >= total) return
    settings.setupHelpSelectedFlat = target
    // A resource keeps the last topic on screen; only topics load content.
    var topics = Model.helpFlatItems(root.helpIndex).length
    if (target >= topics) return
    settings.setupHelpContentTopic = target
    var item = Model.helpFlatItems(root.helpIndex)[target]
    if (item && settings.setupHelpSelectedFile !== item.file)
      settings.setupHelpSelectedFile = item.file
  }

  function helpNavTotal() {
    var topics = Model.helpFlatItems(root.helpIndex).length
    var resources = root.helpIndex && root.helpIndex.resources
      ? root.helpIndex.resources.length : 0
    return topics + resources
  }

  function helpActivateSelection() {
    var topics = Model.helpFlatItems(root.helpIndex).length
    if (settings.setupHelpSelectedFlat >= topics) {
      if (helpView()) helpView().activateSelection()
      return
    }
    helpSelectFlat(settings.setupHelpSelectedFlat)
  }

  // Resolve a Help resource/feature entry to a URL, so `p` / `d` do not need
  // the built Help view (only opening the browser window does).
  function helperLinkUrl(entry) {
    if (!entry) return ""
    var l = root.pluginLinks
    if (entry.link) {
      if (entry.link === "repo") return l.repo || ""
      if (entry.link === "donation") return l.donation || ""
      if (entry.link === "issues") return l.issues || ""
      if (entry.link === "releases") return l.releases || ""
      if (entry.link === "database") return root.pluginDatabaseUrl || ""
    }
    return String(entry.url || "")
  }

  function openHelpUrl(url) {
    if (!url) return
    Qt.openUrlExternally(String(url))
    // The overlay sits above a normal browser window: hide it so the page is
    // not trapped behind the panel.
    close()
  }

  function helperFeatureUrl() {
    var feature = root.helpIndex ? root.helpIndex.feature : null
    openHelpUrl(helperLinkUrl(feature))
  }

  function helperDatabaseUrl() {
    openHelpUrl(root.pluginDatabaseUrl || "")
  }

  function activateCursor() {
    // While an action runs Esc is the only command (it stops the process).
    if (actionRunning) return
    if (view === "setup") {
      setupActivateCursor()
      return
    }
    if (view === "help") helpActivateSelection()
    else if (view === "themes") {
      if (themeFocus >= 0) activateThemeAction()
      else selectTheme(selectedIndex)
    }
    else if (view === "custom") activateCustom()
    else if (view === "wallpapers") {
      if (filterRowFocused && !searching) {
        if (filterFocus === 0 && wallpapersCollectionDropdown()) wallpapersCollectionDropdown().open()
        else if (filterFocus === 1) searching = true
        else if (filterFocus === 2) selectAllWallpapers()
        else if (filterFocus === 3) clearWallpaperSelection()
        return
      }
      showPreview()
    }
    else actionInstall()
  }

  // Space: on the wallpapers screen it checks/unchecks the cursor tile; on the
  // other screens it behaves like Enter.
  function spaceCursor() {
    if (actionRunning) return
    if (view === "wallpapers") {
      // The filter row: Space activates the focused control, like Enter.
      if (filterRowFocused && !searching) {
        activateCursor()
        return
      }
      var item = currentItem()
      if (item) toggleWallpaperCheck(item.filename)
      return
    }
    activateCursor()
  }

  function dismissCursor() {
    // The custom screen is recomputing the counts after an install/remove:
    // the overlay is up and the work is not done, so ignore Esc here. The
    // first Esc already switched the caption to "Stopping…".
    if (customReloading) return
    // While an action runs, Esc stops it instead of navigating away; a second
    // Esc then closes/backs out.
    if (actionRunning) {
      cancelAction()
      return
    }
    // Setup and Help are leaf screens: Esc / Back retraces the origin. While a
    // row is in edit mode Esc cancels it instead (reverts the value).
    if (view === "setup") {
      if (settings.setupEditing) {
        settings.cancelSetupEdit()
        return
      }
      closeSetup()
      return
    }
    if (view === "help") {
      closeHelp()
      return
    }
    // Custom install is a leaf screen: Esc returns to the theme list.
    if (view === "custom") {
      closeCustomInstall()
      return
    }
    // The themes action row is a lateral area (Tab), not a nested level, so Esc
    // means the same as on the list: clear an active filter, else close. Tab /
    // Down return to the list.
    // The filter row is a step back to the grid (the filter is kept); the
    // search editor handles its own Esc through the card fallback.
    if (filterRowFocused) {
      leaveFilterRow()
      return
    }
    // An active filter swallows the first Esc (clear, stay put).
    if (view !== "preview" && currentFilter() !== "") {
      clearFilter()
      return
    }
    if (view === "preview") closePreview()
    else if (view === "wallpapers") goBack()
    else close()
  }

  // Stop the running manager.sh action (install/remove/set-default). The script
  // traps TERM and kills its own downloads, so cancellation is immediate. The
  // UI flag is cleared right away so the buttons re-enable without waiting for
  // the process to actually die.
  function cancelAction() {
    if (!actionRunning) return
    actionCancelled = true
    // On the custom screen the overlay must not blink off: `actionProc.onExited`
    // raises `customReloading` before clearing `actionRunning`, recomputes the
    // counts, then leaves the user on the screen (Esc only stopped the install).
    // Swap the caption to "Stopping…" right away so the first Esc is visibly
    // acknowledged; further Esc presses are ignored while the overlay is up.
    if (view === "custom") customBusyLabel = "Stopping…"
    else actionRunning = false
    actionProc.running = false
  }

  function handleTextKey(text) {
    // Global close, on every screen. While a search field is active the
    // catcher is blocked and `q` types into the filter instead, so it never
    // reaches here in that case.
    if (text === "q" || text === "Q") {
      requestClose()
      return
    }
    // Global Setup, on every screen. Ignored while an action runs, like the
    // rest of the navigation.
    if (text === "s" || text === "S") {
      if (!actionRunning) openSetup()
      return
    }
    // Global Help (`?`), on every screen. Ignored while an action runs, like
    // the Help button.
    if (text === "?") {
      if (!actionRunning) openHelp()
      return
    }
    // The setup screen: `d` restores the defaults; everything else is ignored.
    if (view === "setup") {
      if (text === "d" || text === "D") settings.restoreDefaults()
      return
    }
    // The help screen: `p` proposes a feature, `d` opens the version dataset;
    // Enter/Space pick a topic, Esc goes back, everything else is ignored.
    if (view === "help") {
      if (text === "p" || text === "P") helperFeatureUrl()
      else if (text === "d" || text === "D") helperDatabaseUrl()
      return
    }
    // The custom-install screen is driven by the cursor state machine
    // (arrows/Enter/Tab); `i` runs the highlighted choice like Enter, `u`
    // removes the highlighted scope like the footer Uninstall (a no-op when the
    // row has nothing installed), `b` browses the theme's grid (narrowed to the
    // highlighted collection).
    if (view === "custom") {
      if (text === "i" || text === "I") executeCustomInstall()
      else if (text === "u" || text === "U") executeCustomRemove()
      else if (text === "b" || text === "B") browseCustom()
      return
    }
    if (view === "themes") {
      var themeAction = Model.themeTextAction(text)
      if (themeAction === "browse") {
        selectTheme(selectedIndex)
        return
      }
      // The "Add remote source" placeholder is a no-op message, so it stays
      // available even while an operation runs.
      if (themeAction === "add") {
        triggerAddSource()
        return
      }
      // Custom Install opens the dedicated screen.
      if (themeAction === "custom") {
        openCustomInstall()
        return
      }
      if (themeAction === "help") {
        openHelp()
        return
      }
      // Same rule as the buttons: no bulk task while one is running, and the
      // letter keys honour the same enabled gate as the button they mirror, so
      // `u` on a theme with nothing installed is a no-op like the greyed button.
      if (actionRunning) return
      if (themeAction === "install" && themeActionEnabled("install")) actionInstallTheme()
      else if (themeAction === "uninstall" && themeActionEnabled("uninstall")) actionRemoveThemeAll()
      else if (themeAction === "shuffle" && themeActionEnabled("shuffle")) actionRandomInstall()
      else if (themeAction === "refresh") refresh()
      return
    }
    // Wallpapers/preview: while an action runs only Esc is accepted (it stops
    // the process via `dismissCursor`).
    if (actionRunning) return
    var action = Model.textAction(text)
    if (action === "default") actionToggleDefault()
    else if (action === "refresh") refresh()
    else if (action === "install") actionInstall()
    else if (action === "uninstall") actionRemove()
    else if (action === "favorite") toggleFavoriteTargets()
  }

  function takeCursor(index) {
    cursorActive = true
    // Mouse back on the grid drops the filter-row focus (never while typing:
    // hovering a tile must not steal the search editor).
    if (filterFocus >= 0 && !searching) filterFocus = -1
    // Same for the themes action row: hovering a theme row returns to the list.
    if (view === "themes") themeFocus = -1
    selectedIndex = index
    // Hovering a theme row warms its catalog for Custom Install.
    if (view === "themes" && index < activeThemesModel.count)
      prefetchCustomCatalog(activeThemesModel.get(index).name)
  }

  // "Add remote source" placeholder: a click or the `a` key flashes the COMING
  // SOON label for 3s, then it reverts.
  function triggerAddSource() {
    addSourceSoon = true
    addSourceReset.restart()
  }

  // ---- wallpaper multi-select ----------------------------------------------
  // The checks are keyed by filename. Reading `selectionRevision` inside the
  // helpers is what makes the plain-object map re-evaluate the tile bindings.
  function isWallpaperChecked(filename) {
    var rev = selectionRevision
    return checkedWallpapers[String(filename)] === true
  }

  function toggleWallpaperCheck(filename) {
    var key = String(filename)
    if (checkedWallpapers[key]) delete checkedWallpapers[key]
    else checkedWallpapers[key] = true
    selectionRevision++
  }

  function checkedFilenames() {
    var rev = selectionRevision
    var out = []
    for (var key in checkedWallpapers) {
      if (checkedWallpapers[key]) out.push(key)
    }
    return out
  }

  // The single filename under the cursor, as a one-element list, so the action
  // gates can treat "no checks" and "one check" the same way.
  function cursorFilenames() {
    var item = currentItem()
    return item ? [String(item.filename)] : []
  }

  // Check every row the grid is currently showing (so an active filter narrows
  // "Select all" to the visible results).
  function selectAllWallpapers() {
    for (var i = 0; i < activeWallpapersModel.count; i++) {
      var row = activeWallpapersModel.get(i)
      if (row) checkedWallpapers[String(row.filename)] = true
    }
    selectionRevision++
  }

  function clearWallpaperSelection() {
    checkedWallpapers = ({})
    selectionRevision++
  }

  // "Download original": ask for a destination folder with Omarchy's own file
  // chooser (`omarchy-file-select`, portal-backed) and save the full-res file
  // there. The chooser is a normal window, so the overlay is hidden first.
  function actionDownloadOriginal() {
    var item = currentItem()
    if (!item || item.url === "") return
    pendingDownloadUrl = item.url
    pendingDownloadDest = ""
    close()
    folderProc.running = true
  }

  function startDownload() {
    if (pendingDownloadUrl === "" || pendingDownloadDest === "") return
    downloadProc.requestedUrl = pendingDownloadUrl
    downloadProc.command = scriptCmd(["download", pendingDownloadUrl, pendingDownloadDest])
    downloadProc.running = true
  }

  // Footer key hint: the key in bold foreground, the action in dim, matching
  // the kit's "click select / shift+click range" caption style.
  function keyHint(key, label) {
    return "<font color=\"" + root.foreground + "\"><b>" + key + "</b></font>"
      + " <font color=\"" + root.dim + "\">" + label + "</font>"
  }

  // ---- actions --------------------------------------------------------------
  // Theme row by slug, or null. Reads `themesRevision` because ListModel.get()
  // is not a tracked QML dependency on its own.
  function themeByName(name) {
    var rev = themesRevision
    if (!name) return null
    for (var i = 0; i < themesModel.count; i++) {
      if (themesModel.get(i).name === name) return themesModel.get(i)
    }
    return null
  }

  // True when the open theme is the one Omarchy is currently running. Only then
  // does "set default" change the live background directly; on any other theme
  // the choice is remembered per theme and applied when the user switches.
  readonly property bool browsingActiveTheme: themeName !== ""
    && root.activeThemeSlug !== ""
    && Model.normalizeSlug(themeName) === Model.normalizeSlug(root.activeThemeSlug)

  // Whether `model` is the default of the open theme (live for the running
  // theme, remembered otherwise).
  function isThemeDefault(model) {
    if (!model) return false
    if (browsingActiveTheme) return String(model.isDefault) === "1"
    var rev = settings.themeDefaultsRevision
    var d = settings.themeDefault(themeName)
    return !!d && String(d.filename) === String(model.filename)
  }

  // ---- favourites -----------------------------------------------------------
  // Whether a wallpaper is starred (global, across themes).
  function isWallpaperFavorite(filename) {
    var rev = settings.favoritesRevision
    return Model.isFavorite(settings.favorites, filename)
  }

  // The wallpapers a star toggle acts on: every checked tile when a selection
  // exists, else just the one under the cursor. Rows come from the full
  // `wallpapersModel` (not the filtered view), so a checked tile hidden by the
  // active filter still keeps its name/code when starred.
  function favoriteTargets() {
    var names = checkedFilenames()
    if (names.length === 0) {
      var item = currentItem()
      return item ? [item] : []
    }
    var lookup = {}
    for (var i = 0; i < wallpapersModel.count; i++) {
      var row = wallpapersModel.get(i)
      if (row) lookup[String(row.filename)] = row
    }
    var out = []
    for (var n = 0; n < names.length; n++) {
      var key = String(names[n])
      out.push(lookup[key] || { filename: key })
    }
    return out
  }

  // Star/unstar the target group. When every target is already starred the
  // whole group is cleared; otherwise the whole group is starred. With no
  // selection this is just the cursor tile.
  function toggleFavoriteTargets() {
    if (actionRunning) return
    // A star toggle driven by the checks consumes them, like an install does:
    // the user selected a set, acted on it, and starts fresh.
    var hadSelection = checkedFilenames().length > 0
    var targets = favoriteTargets()
    if (targets.length === 0) return
    var names = []
    for (var i = 0; i < targets.length; i++) names.push(targets[i].filename)
    var on = Model.favoriteToggleOn(settings.favorites, names)
    settings.setFavorites(targets, on)
    if (hadSelection) clearWallpaperSelection()
    if (targets.length === 1)
      setStatus((on ? "Added to favorites: " : "Removed from favorites: ")
        + Model.titleCase(targets[0].name))
    else
      setStatus((on ? "Added " + targets.length + " wallpapers to favorites"
        : "Removed " + targets.length + " wallpapers from favorites"))
    // A tile that just lost its star must leave the "★ Favorites" grid now;
    // clamp the cursor so it cannot point past the shrunken model.
    if (collectionFilter === Model.favoritesFilter()) {
      rebuildWallpaperDisplay()
      selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex))
    }
  }

  // Pick the Favorites empty-state backdrop: a random wallpaper of the open
  // theme, from files already on disk only (installed full-res, else a cached
  // preview). Never a remote URL: the Image is drawn synchronously, and a
  // network fetch would leave the area blank for the duration.
  function pickFavoritesBackdrop() {
    var installed = []
    var cached = []
    for (var i = 0; i < wallpapersModel.count; i++) {
      var row = wallpapersModel.get(i)
      if (!row) continue
      if (String(row.installed) === "1" && themeName !== "")
        installed.push(Util.fileUrl(backgroundsDir + "/" + themeName + "/" + row.filename))
      var prev = String(row.preview || "")
      if (prev !== "" && imagePathByUrl[prev] !== undefined)
        cached.push(String(imagePathByUrl[prev]))
    }
    var pool = installed.length > 0 ? installed : cached
    favoritesBackdrop = pool.length > 0
      ? pool[Math.floor(Math.random() * pool.length)] : ""
  }

  function currentItem() {
    if ((view !== "wallpapers" && view !== "preview")
        || selectedIndex < 0 || selectedIndex >= activeWallpapersModel.count)
      return null
    return activeWallpapersModel.get(selectedIndex)
  }

  function showPreview() {
    if (activeWallpapersModel.count === 0) return
    filterFocus = -1
    searching = false
    view = "preview"
  }

  function closePreview() {
    view = "wallpapers"
    cursorActive = true
    filterFocus = -1
    selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex))
    // Deferred: the GridView only becomes visible on the view change, so
    // scrolling in the same frame reads stale geometry and lands nowhere.
    Qt.callLater(function() { scrollToGrid(root.selectedIndex, GridView.Contain) })
  }

  function previewNext(delta) {
    if (activeWallpapersModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex + delta))
  }

  function actionInstall() {
    if (actionRunning) return
    // Same gate as the footer button: nothing to install in the selection.
    if (view === "wallpapers" && !wallpapersCanInstall) return
    // Any checked wallpaper wins on the grid: install the whole selection (the
    // checks are cleared once it completes). With none checked, install the
    // cursor tile. The preview always acts on its own wallpaper.
    var checks = view === "wallpapers" ? checkedFilenames() : []
    if (checks.length > 0) {
      // More than one checked wallpaper is a bulk install: blocked once a
      // storage cap is reached, exactly like Install all / Shuffle. A single
      // checked/cursor wallpaper stays allowed.
      if (storageLimitReached && checks.length > 1) return
      busy = true
      setStatus("Installing " + checks.length + " wallpaper(s)…")
      actionClearsChecks = true
      runAction(["install", themeName].concat(checks))
      return
    }
    var item = currentItem()
    // Already installed: nothing to do (button and `i` are no-ops).
    if (!item || String(item.installed) === "1") return
    busy = true
    setStatus("Installing " + item.name + "…")
    actionClearsChecks = false
    runAction(["install", themeName, item.filename])
  }

  function actionRemove() {
    if (actionRunning) return
    // Same gate as the footer button: nothing to remove in the selection.
    if (view === "wallpapers" && !wallpapersCanRemove) return
    var checks = view === "wallpapers" ? checkedFilenames() : []
    if (checks.length > 0) {
      busy = true
      setStatus("Uninstalling " + checks.length + " wallpaper(s)…")
      actionClearsChecks = true
      runAction(["remove", themeName].concat(checks))
      return
    }
    var item = currentItem()
    // Not installed: nothing to remove.
    if (!item || String(item.installed) !== "1") return
    busy = true
    setStatus("Removing " + item.name + "…")
    actionClearsChecks = false
    runAction(["remove", themeName, item.filename])
  }

  // `d` / double click: a switch. Not the default → set it (manager.sh installs
  // the file first if missing); already the default → clear it back to the
  // theme's own background.
  //
  // On the running Omarchy theme the change is live. On any other theme it is
  // remembered for that theme and applied when the user switches to it, so
  // choosing a matte-black default while on tokyo-night never replaces the
  // current desktop background.
  function actionToggleDefault() {
    if (actionRunning) return
    var item = currentItem()
    if (!item) return
    if (browsingActiveTheme) {
      busy = true
      if (String(item.isDefault) === "1") {
        settings.clearThemeDefault(themeName)
        setStatus("Clearing default: " + item.name + "…")
        runAction(["unset-default", themeName, item.filename])
      } else {
        settings.setThemeDefault(themeName, item.filename, imageRelativePath(item.url))
        setStatus("Setting default: " + item.name + "…")
        runAction(["set-default", themeName, item.filename, item.url])
      }
      return
    }
    // Another theme: remember the choice (making sure the file lands on disk)
    // and leave the current background untouched.
    var remembered = settings.themeDefault(themeName)
    if (remembered && String(remembered.filename) === String(item.filename)) {
      settings.clearThemeDefault(themeName)
      setStatus("Default cleared for " + Model.ucfirst(themeName))
      return
    }
    settings.setThemeDefault(themeName, item.filename, imageRelativePath(item.url))
    if (String(item.installed) !== "1") {
      busy = true
      setStatus("Installing " + item.name + "…")
      runAction(["install", themeName, item.filename])
    } else {
      setStatus("Default for " + Model.ucfirst(themeName)
        + " set — applies when you switch to it")
    }
  }

  function actionInstallAll() {
    busy = true
    setStatus("Installing all of theme " + themeName + "…")
    runAction(["install", themeName])
  }

  // Bulk install straight from the themes screen: no need to open the theme.
  // Blocked while a storage cap is reached (the banner flags it).
  function actionInstallTheme() {
    var theme = selectedTheme
    if (!theme || storageLimitReached) return
    busy = true
    setStatus("Installing all of " + theme.name + "…")
    runAction(["install", theme.name])
  }

  // Install a shuffled sample of the selected theme's wallpapers. The count
  // comes from Setup (default 5, range 1-50).
  function actionRandomInstall() {
    var theme = selectedTheme
    if (!theme || storageLimitReached) return
    var count = Math.max(1, Math.min(50, settings.shuffleCount))
    busy = true
    setStatus("Shuffling in " + count + " wallpapers of " + theme.name + "…")
    runAction(["random-install", theme.name, String(count)])
  }

  function actionRemoveAll() {
    busy = true
    setStatus("Removing all of theme " + themeName + "…")
    runAction(["remove", themeName])
  }

  // Remove every installed wallpaper of the highlighted theme (themes screen).
  function actionRemoveThemeAll() {
    var theme = selectedTheme
    if (!theme) return
    busy = true
    setStatus("Removing all of " + theme.name + "…")
    runAction(["remove", theme.name])
  }

  function runAction(args) {
    // One action at a time: ignore new tasks while one runs (the UI disables
    // them, but Enter/keys could still try). Re-enabled on exit/cancel.
    if (actionRunning) return
    // Every command takes the theme as its first argument, so the running theme
    // is recorded centrally for the row badge and the footer.
    actionTheme = args.length > 1 ? String(args[1]) : ""
    actionScopeTotal = 0
    lastAction = args
    actionRunning = true
    actionProc.command = scriptCmd(args)
    actionProc.running = true
  }

  // ---- automatic rotation ---------------------------------------------------
  // Ask `manager.sh rotate` for the next wallpaper of the CURRENT Omarchy theme
  // and set it as the background. Only files already on disk are used, so this
  // never downloads. Driven by the Setup settings; the "Rotate now" action calls
  // it directly too, so it works even with rotation switched off.
  function rotateWallpaper() {
    if (rotationProc.running) return
    var args = ["rotate"]
    if (settings.rotationAllTheme) args.push("--all")
    if (settings.rotationRandom) args.push("--random")
    rotationProc.command = scriptCmd(args)
    rotationProc.running = true
  }

  // Restart the automatic-rotation countdown after a wallpaper is set (a
  // rotation, or the restore on a theme switch), so the next automatic change
  // waits a full interval instead of firing right after the manual one.
  function resetRotationTimer() {
    if (settings.rotationEnabled) rotationTimer.restart()
  }

  // ---- restore the wallpaper on an Omarchy theme switch ----------------------
  // `omarchy-theme-set` writes `theme.name` *before* it picks the new theme's
  // background, and its own picker falls back to the first file when the current
  // background does not belong to the new theme. Wait for the switch to settle,
  // then restore the wallpaper the theme had the last time it was shown (the
  // script's rotation state), so switching never restarts from the first. The
  // stored per-theme default is only a fallback, and only when its file is
  // already installed: a theme with nothing installed must stay empty instead of
  // downloading a wallpaper on its own.
  property string pendingThemeDefaultTheme: ""

  function scheduleThemeDefaultApply(theme) {
    pendingThemeDefaultTheme = theme
    themeDefaultApplyTimer.restart()
  }

  // Strip the current CDN base (or a `/wallpapers/<version>/` segment from an
  // older snapshot) off an image URL, leaving the base-relative path. That path
  // is what `themeDefaults` stores, so a version bump keeps the entry valid.
  function imageRelativePath(url) {
    var s = String(url || "")
    if (s === "") return ""
    var base = String(pluginBase || "").replace(/\/+$/, "")
    if (base !== "" && s.indexOf(base + "/") === 0)
      return s.slice(base.length + 1)
    var m = s.match(/\/wallpapers\/[^/]+\/(.*)$/)
    if (m) return m[1]
    return ""
  }

  function applyThemeDefault(theme) {
    if (theme === "") return
    if (themeDefaultProc.running) {
      pendingThemeDefaultTheme = theme
      themeDefaultApplyTimer.restart()
      return
    }
    // `resume` re-applies the theme's last wallpaper; the stored default is only
    // a fallback (and is dropped when its file is no longer installed, exit 3).
    var d = settings.themeDefault(theme)
    var args = ["resume", theme]
    if (d && d.filename) args.push(d.filename)
    themeDefaultProc.applyTheme = theme
    themeDefaultProc.command = scriptCmd(args)
    themeDefaultProc.running = true
  }

  Timer {
    id: themeDefaultApplyTimer
    interval: 1500
    repeat: false
    onTriggered: root.applyThemeDefault(root.pendingThemeDefaultTheme)
  }

  Process {
    id: themeDefaultProc
    property string applyTheme: ""
    property string resumedFile: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        themeDefaultProc.resumedFile = line.indexOf("ROTATE\t") === 0
          ? line.substring(7).split("/").pop() : ""
      }
    }
    onExited: function(exitCode) {
      // A theme switch just set (or left Omarchy's) background: give the next
      // automatic rotation a full interval from here.
      root.resetRotationTimer()
      // Exit 3: the fallback default points to a wallpaper no longer installed,
      // so drop that dead entry for the theme.
      if (exitCode === 3 && themeDefaultProc.applyTheme !== "") {
        settings.clearThemeDefault(themeDefaultProc.applyTheme)
        return
      }
      root.loadLimits()
      // A restored wallpaper may have touched the theme's files: drop its cached
      // parse so the next Custom Install open reads fresh flags.
      if (themeDefaultProc.applyTheme !== "")
        delete root.customCatalogCache[themeDefaultProc.applyTheme]
      // The plugin may be open on the theme that just became active: reflect the
      // restored wallpaper (and its installed file) without a full reload.
      if (themeDefaultProc.resumedFile !== "" && root.themeName !== ""
            && Model.normalizeSlug(root.themeName) === Model.normalizeSlug(themeDefaultProc.applyTheme)) {
        root.setWallpaperInstalled(themeDefaultProc.resumedFile, "1")
        root.setWallpaperDefault(themeDefaultProc.resumedFile)
      }
      themeDefaultProc.resumedFile = ""
    }
  }

  // Apply the finished action to the in-memory catalog instead of reloading it:
  // a full reload resets the grid/strip scroll and lags the whole UI. Only the
  // rows that changed (and the bindings that read them) are touched; the theme
  // counts are already kept live by the `PROGRESS` lines.
  function applyActionResult() {
    var args = lastAction
    if (!args || args.length < 2) return
    var cmd = String(args[0])
    // The in-memory catalog belongs to `themeName`: skip actions on other themes.
    if (String(args[1]) !== themeName) return
    if (cmd === "install") {
      if (args.length > 2 && String(args[2]) === "--collection") {
        // Bulk collection install: the custom-install screen reloads its own
        // catalog, so there is no per-filename patch to apply here.
      } else if (args.length > 2) {
        for (var i = 2; i < args.length; i++) setWallpaperInstalled(String(args[i]), "1")
      } else setAllWallpapersInstalled("1")
    } else if (cmd === "remove") {
      if (args.length > 2 && String(args[2]) === "--collection") {
        // Bulk collection remove: the custom-install screen reloads its own
        // catalog, so there is no per-filename patch to apply here.
      } else if (args.length > 2) {
        for (var j = 2; j < args.length; j++) setWallpaperInstalled(String(args[j]), "0")
      } else setAllWallpapersInstalled("0")
    } else if (cmd === "set-default") {
      if (args.length > 2) {
        // manager.sh installs the file first when missing.
        setWallpaperInstalled(String(args[2]), "1")
        setWallpaperDefault(String(args[2]))
      }
    } else if (cmd === "unset-default") {
      setWallpaperDefault("")
    } else if (cmd === "random-install") {
      // Which files were picked is unknown: reload only this catalog.
      if (view === "wallpapers" || view === "preview") loadWallpapers()
    }
  }

  // Patch the custom-install model in place after an action, instead of
  // re-reading the whole catalog with `manager.sh catalog` (which was the slow
  // path: the data was already in memory). Only the `installed` flag can change.
  // `random-install` picks unknown files, so that one still reloads.
  function applyCustomActionResult() {
    var args = lastAction
    // Unknown files (random sample): the only case that still needs a re-read.
    var cmd = (args && args.length > 0) ? String(args[0]) : ""
    var theme = (args && args.length > 1) ? String(args[1]) : ""
    if (cmd === "random-install" && theme === customThemeName) {
      customReloading = true
      loadCustomCatalog(true)
      return
    }
    // Everything else is patched in place below; release the overlay now.
    customReloading = false
    if (!args || args.length < 2) return
    if (theme !== customThemeName) return
    var collection = ""
    var filenames = []
    if (cmd === "install" || cmd === "remove") {
      if (args.length > 2 && String(args[2]) === "--collection")
        collection = String(args[3])
      else if (args.length > 2)
        filenames = args.slice(2).map(function(x) { return String(x) })
    } else if (cmd === "set-default" || cmd === "uninstall-default") {
      if (args.length > 2) filenames = [String(args[2])]
    } else {
      return
    }
    var installedValue = (cmd === "remove") ? "0" : "1"
    var changed = false
    var items = customCatalogItems.slice()
    for (var i = 0; i < items.length; i++) {
      var row = items[i]
      var hit = false
      if (collection !== "") hit = String(row.collection) === collection
      else if (filenames.length > 0) hit = filenames.indexOf(String(row.filename)) >= 0
      else hit = true
      if (hit && String(row.installed) !== installedValue) {
        row.installed = installedValue
        changed = true
      }
    }
    if (changed) {
      // Reassign so the `customRevision`-driven bindings re-read the array.
      customCatalogItems = items
      customRevision++
    }
    // Keep the cache in sync so the next open of this screen is instant too.
    var cached = customCatalogCache[theme]
    if (cached) {
      for (var k = 0; k < cached.length; k++) {
        var crow = cached[k]
        var chit = false
        if (collection !== "") chit = String(crow.collection) === collection
        else if (filenames.length > 0) chit = filenames.indexOf(String(crow.filename)) >= 0
        else chit = true
        if (chit) crow.installed = installedValue
      }
    }
    if (changed) customRevision++
  }

  function setWallpaperInstalled(filename, value) {
    for (var i = 0; i < wallpapersModel.count; i++) {
      if (wallpapersModel.get(i).filename === filename) {
        wallpapersModel.setProperty(i, "installed", value)
        break
      }
    }
    for (var j = 0; j < wallpapersDisplayModel.count; j++) {
      if (wallpapersDisplayModel.get(j).filename === filename) {
        wallpapersDisplayModel.setProperty(j, "installed", value)
        break
      }
    }
    wallpapersRevision++
  }

  function setAllWallpapersInstalled(value) {
    for (var i = 0; i < wallpapersModel.count; i++)
      wallpapersModel.setProperty(i, "installed", value)
    for (var j = 0; j < wallpapersDisplayModel.count; j++)
      wallpapersDisplayModel.setProperty(j, "installed", value)
    wallpapersRevision++
  }

  function setWallpaperDefault(filename) {
    for (var i = 0; i < wallpapersModel.count; i++)
      wallpapersModel.setProperty(i, "isDefault",
        wallpapersModel.get(i).filename === filename ? "1" : "0")
    for (var j = 0; j < wallpapersDisplayModel.count; j++)
      wallpapersDisplayModel.setProperty(j, "isDefault",
        wallpapersDisplayModel.get(j).filename === filename ? "1" : "0")
    wallpapersRevision++
  }

  // Live progress from `manager.sh` (`PROGRESS` TSV lines): buffer the latest
  // count and flush it on a timer, so a bulk install does not re-evaluate the
  // whole screen on every downloaded file. `onExited` refreshes from the source
  // of truth once the operation is over.
  function applyProgress(name, installed, scopeTotal) {
    if (!name || !isFinite(installed)) return
    pendingProgressTheme = name
    pendingProgressInstalled = installed
    pendingProgressScopeTotal = isFinite(scopeTotal) ? scopeTotal : -1
    // Throttle, do not debounce: a fast local remove emits every PROGRESS line
    // back-to-back, so a `restart()` here would keep postponing the flush until
    // the process exits (which then drops the buffered value). Start the timer
    // only if it is idle, so the latest count is applied at most every 120ms.
    if (!progressTimer.running) progressTimer.start()
  }

  function flushProgress() {
    var name = pendingProgressTheme
    var installed = pendingProgressInstalled
    var scopeTotal = pendingProgressScopeTotal
    pendingProgressTheme = ""
    pendingProgressInstalled = -1
    pendingProgressScopeTotal = -1
    if (name === "" || installed < 0) return
    // Freeze the caption on the first scope reported for this action: the script
    // can emit a trailing single-file phase after the bulk download, and the
    // caption must not jump from "250 wallpapers" to "1" (or drift to the
    // theme total) mid-action.
    if (scopeTotal > 0 && actionScopeTotal === 0) actionScopeTotal = scopeTotal
    for (var i = 0; i < themesModel.count; i++) {
      if (themesModel.get(i).name === name) {
        if ((themesModel.get(i).installed || 0) !== installed) {
          themesModel.setProperty(i, "installed", installed)
          themesRevision++
        }
        return
      }
    }
  }

  // Alias kept for the image-cache call sites; `scriptCmd` already carries the
  // plugin id.
  function cachedCmd(args) {
    return scriptCmd(args)
  }

  // ---- image cache resolution ----------------------------------------------
  // Ask `manager.sh image` for a local path; a result only applies if its URL is
  // still the wanted one, so fast navigation keeps the latest request only.
  function resolveDetailImage() {
    var url = detailTargetUrl
    if (url === "" || url.indexOf("http") !== 0) {
      pendingDetailUrl = ""
      return
    }
    if (url === detailImageSource) {
      // Already cached: drop any in-flight request for another theme so its
      // result cannot overwrite this one.
      pendingDetailUrl = ""
      return
    }
    // Already prewarmed: use the local file without spawning a process.
    if (root.cachedImagePath(url) !== "") {
      pendingDetailUrl = ""
      return
    }
    if (url === pendingDetailUrl) return
    pendingDetailUrl = url
    startDetailResolution()
  }

  // Detail pane source: the cached file once resolved, the small preview only
  // on the very first paint, otherwise keep the previous frame. The backdrop
  // layer holds that previous frame while the next one decodes.
  function refreshDetailShown() {
    var url = detailTargetUrl
    if (url === "") return
    if (detailImagePath !== "" && detailImageSource === url) {
      var path = Util.fileUrl(detailImagePath)
      if (detailImageShown !== path) detailImageShown = path
      return
    }
    var cached = root.cachedImagePath(url)
    if (cached !== "") {
      var cachedUrl = Util.fileUrl(cached)
      if (detailImageShown !== cachedUrl) detailImageShown = cachedUrl
      return
    }
    if (detailImageShown === "" && selectedTheme)
      detailImageShown = selectedTheme.preview ? selectedTheme.preview : ""
  }

  function startDetailResolution() {
    if (detailImageProc.running || pendingDetailUrl === "") return
    detailImageProc.requestedUrl = pendingDetailUrl
    detailImageProc.command = cachedCmd(["image", pendingDetailUrl])
    detailImageProc.running = true
  }

  function resolvePreviewImage() {
    var url = previewTargetUrl
    if (url === "" || url.indexOf("http") !== 0) {
      pendingPreviewUrl = ""
      return
    }
    if (url === previewImageSource) {
      pendingPreviewUrl = ""
      return
    }
    // Already prewarmed: the local file is good enough, skip the process.
    if (root.cachedImagePath(url) !== "") {
      pendingPreviewUrl = ""
      return
    }
    if (url === pendingPreviewUrl) return
    pendingPreviewUrl = url
    startPreviewResolution()
  }

  function startPreviewResolution() {
    if (previewImageProc.running || pendingPreviewUrl === "") return
    previewImageProc.requestedUrl = pendingPreviewUrl
    previewImageProc.command = cachedCmd(["image", pendingPreviewUrl])
    previewImageProc.running = true
  }

  // Local cache path for a remote URL, if the current item was resolved or a
  // neighbour was prewarmed. Reads `imageCacheRevision` because the map is a
  // plain object, not a tracked QML property.
  function cachedImagePath(url) {
    if (!url) return ""
    if (previewImageSource === url && previewImagePath !== "") return previewImagePath
    var rev = imageCacheRevision
    var path = imagePathByUrl[url]
    return path ? String(path) : ""
  }

  // Warm the cache for the neighbours of the selection so moving through the
  // list finds the images already on disk. Fire-and-forget, debounced. Never
  // while an install/remove runs: the extra downloads would compete with it and
  // make the UI stutter.
  function prefetchNeighbours() {
    if (busy || actionRunning) return
    var urls = []
    var model
    if (view === "themes") model = activeThemesModel
    else if (view === "wallpapers" || view === "preview") model = activeWallpapersModel
    else return
    var lo = Math.max(0, selectedIndex - 3)
    var hi = Math.min(model.count - 1, selectedIndex + 3)
    for (var i = lo; i <= hi; i++) {
      var row = model.get(i)
      if (!row) continue
      if (view === "themes") {
        var themeUrl = row.image ? row.image : row.preview
        if (themeUrl && themeUrl.indexOf("http") === 0) urls.push(themeUrl)
      } else if (String(row.installed) !== "1" && row.url && row.url.indexOf("http") === 0) {
        urls.push(row.url)
      }
    }
    // Only warm what is not already cached, and queue if a warm-up is running.
    var missing = []
    for (var j = 0; j < urls.length; j++) {
      if (root.cachedImagePath(urls[j]) === "") missing.push(urls[j])
    }
    if (missing.length === 0) return
    if (prewarmProc.running) {
      pendingPrefetch = missing
      return
    }
    startPrewarm(missing)
  }

  function startPrewarm(urls) {
    prewarmProc.command = cachedCmd(["prewarm"].concat(urls))
    prewarmProc.running = true
  }

  onDetailTargetUrlChanged: {
    resolveDetailImage()
    refreshDetailShown()
  }
  onPreviewTargetUrlChanged: resolvePreviewImage()
  onSelectedIndexChanged: {
    prefetchTimer.restart()
    // Remember the themes-screen cursor so reopening the overlay lands back on
    // the theme the user left selected (other screens reuse `selectedIndex` for
    // their own cursor, so only track it while on the themes list).
    if (view === "themes") themesCursorIndex = selectedIndex
  }
  onViewChanged: {
    refreshDetailShown()
    hoverArmed = false
    hoverGate.restart()
    // Popups are top-level overlays and would outlive a screen switch: the
    // view is destroyed right after this, so close anything open first.
    if (wallpapersCollectionDropdown() && wallpapersCollectionDropdown().popupOpen)
      wallpapersCollectionDropdown().close()
    if (view !== "setup" && settings.setupDropdownOpen && setupView())
      setupView().closeDropdown()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }
  // A prewarmed neighbour may make the full image available: upgrade the detail
  // pane from the small preview without waiting for the next selection.
  onImageCacheRevisionChanged: refreshDetailShown()

  // ---- cache warm-up --------------------------------------------------------
  // At plugin start, fetch datasets.json and every theme catalog from the CDN
  // once (the script reuses them until the configured base changes). After this
  // every screen reads catalogs from the on-disk cache, so opening Custom
  // Install never waits on the network. Best effort: a failure is silent and
  // `ensure_catalog` still retries on demand.
  Process {
    id: warmProc
    command: root.scriptCmd(["warm"])
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        // `url<TAB>path` lines come from the preview prewarm: record them so
        // those previews load from disk the first time the screen opens.
        var parts = s.split("\t")
        if (parts.length >= 2 && parts[0].indexOf("http") === 0 && parts[1] !== "") {
          root.imagePathByUrl[parts[0]] = parts[1]
          root.imageCacheRevision++
        }
      }
    }
    onExited: {
      // The catalogs are on disk now: drop the in-memory cache so the next
      // reads come straight from the warmed files, then re-warm the queue.
      root.customCatalogCache = ({})
      if (root.activeThemesModel.count > 0) root.prefetchAllCatalogs()
      // The warm-up is done: release the "Initiating…" state and, if the overlay
      // was opened while it ran, load the themes now.
      root.warming = false
      if (root.opened && root.themesPending) {
        root.themesPending = false
        root.loadThemes()
      }
    }
  }

  Component.onCompleted: warmProc.running = true

  // ---- local usage ----------------------------------------------------------
  // `manager.sh limits` -> `LIMITS\t<files>\t<bytes>`, feeding the storage-cap
  // flag. Best effort: a failure leaves the previous values in place.
  Process {
    id: limitsProc
    command: root.scriptCmd(["limits"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        if (line.indexOf("LIMITS\t") !== 0) return
        var parts = line.split("\t")
        if (parts.length < 3) return
        root.localFileCount = parseInt(parts[1], 10) || 0
        root.localBytes = parseFloat(parts[2]) || 0
      }
    }
  }

  // `manager.sh remote-version` -> the version published on main, or nothing on
  // failure. The Setup "Check for updates" row compares it with the installed
  // `pluginVersion`; the plugin never installs the update itself.
  Process {
    id: remoteVersionProc
    command: root.scriptCmd(["remote-version"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var remote = String(text || "").trim()
        if (remote === "") { root.updateCheckState = "error"; return }
        root.updateRemoteVersion = remote
        root.updateCheckState = Model.compareVersions(remote, root.pluginVersion) > 0
          ? "available" : "uptodate"
      }
    }
    onExited: {
      if (root.updateCheckState === "checking") root.updateCheckState = "error"
    }
  }

  // Automatic rotation: print the picked file as `ROTATE<TAB><path>`; keep the
  // open grid's DEFAULT pill in sync when the rotated wallpaper belongs to the
  // theme currently being browsed (rotation follows the Omarchy theme, which may
  // differ from the theme open in the plugin).
  Process {
    id: rotationProc
    onRunningChanged: root.setupSetRotateBusy(running)
    // The tick is done: start the next interval from here, not from when this
    // one fired, so a slow rotation never causes a burst of changes.
    onExited: root.resetRotationTimer()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        if (line.indexOf("ROTATE\t") !== 0) return
        var path = line.substring(7)
        var base = path.substring(path.lastIndexOf("/") + 1)
        if ((root.view === "wallpapers" || root.view === "preview")
            && Model.normalizeSlug(root.themeName) === Model.normalizeSlug(root.activeThemeSlug))
          root.setWallpaperDefault(base)
      }
    }
  }

  // ---- theme loading --------------------------------------------------------
  Process {
    id: themesProc
    command: root.scriptCmd(["themes"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        themesModel.clear()
        var rows = Model.parseThemes(text)
        for (var i = 0; i < rows.length; i++) themesModel.append(rows[i])
        root.themesRevision++
        if (root.filterText !== "") root.rebuildThemeDisplay()
        if (root.pendingThemeSelect) {
          root.pendingThemeSelect = false
          root.selectedIndex = root.activeThemeIndex()
          // The active theme has been picked once for this session; later opens
          // keep whatever the user selected.
          root.themesInitialized = true
          root.refreshDetailShown()
        } else if (root.selectedIndex >= root.activeThemesModel.count) {
          root.selectedIndex = Math.max(0, root.activeThemesModel.count - 1)
        }
        root.busy = false
        root.setStatus(Model.themesStatus(themesModel.count))
        if (root.activeThemesModel.count > 0)
          Qt.callLater(function() { scrollToList(root.selectedIndex, ListView.Contain) })
        // Warm every theme's catalog in the background, one at a time, so
        // Custom Install opens instantly whichever theme the user picks. The
        // selected theme first (most likely next), then the rest.
        if (root.activeThemesModel.count > 0)
          root.prefetchAllCatalogs()
      }
    }
    onExited: {
      if (root.busy) {
        root.busy = false
        root.setStatus(themesModel.count > 0
          ? Model.themesStatus(themesModel.count)
          : "Error loading themes")
      }
    }
  }

  // ---- catalog loading ------------------------------------------------------
  Process {
    id: catalogProc
    // Stamp of the request this run belongs to; checked against `root` before
    // the rows are applied, so a superseded theme is discarded.
    property int requestedSerial: 0
    property string requestedTheme: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The user has already switched theme: drop the rows entirely; the
        // pending request is picked up in `onExited` (bug #8).
        if (catalogProc.requestedSerial !== root.catalogSerial
            || catalogProc.requestedTheme !== root.themeName)
          return
        wallpapersModel.clear()
        var rows = Model.parseCatalog(text)
        // Share the parse with the custom-install screen: opening it for a
        // theme the user just browsed must not spawn manager.sh again.
        root.customCatalogCache[catalogProc.requestedTheme] = rows
        for (var i = 0; i < rows.length; i++) wallpapersModel.append(rows[i])
        // Apply a collection requested before the rows existed (Browse from
        // Custom Install). Done here, with the model populated, so the dropdown
        // options already contain it and the label never shows a raw value.
        if (root.pendingCollectionFilter !== "") {
          root.collectionFilter = root.pendingCollectionFilter
          root.pendingCollectionFilter = ""
        }
        if (root.wallpaperFilterText !== "" || root.collectionFilter !== "")
          root.rebuildWallpaperDisplay()
        root.wallpapersRevision++
        // The Favorites empty state flushes a random theme wallpaper behind it.
        if (root.collectionFilter === Model.favoritesFilter())
          root.pickFavoritesBackdrop()
        // Land the cursor on the entry target (first tile, or the remembered
        // one). Applied here, after the model is populated, so a hover event
        // fired while the grid was being built cannot override it; the hover
        // gate is re-armed for the same reason.
        if (root.pendingWallpaperSelect) {
          root.pendingWallpaperSelect = false
          root.selectedIndex = Math.max(0,
            Math.min(root.activeWallpapersModel.count - 1, root.pendingWallpaperIndex))
        } else if (root.selectedIndex >= root.activeWallpapersModel.count) {
          root.selectedIndex = Math.max(0, root.activeWallpapersModel.count - 1)
        }
        root.hoverArmed = false
        hoverGate.restart()
        root.busy = false
        root.setStatus(Model.catalogStatus(wallpapersModel.count, root.themeName))
        if (root.activeWallpapersModel.count > 0)
          Qt.callLater(function() { scrollToGrid(root.selectedIndex, GridView.Contain) })
      }
    }
    onExited: {
      // A request was queued (or this run belonged to a theme the user has
      // left): load the current theme now that the process is free.
      if (root.catalogPending || catalogProc.requestedTheme !== root.themeName) {
        root.catalogPending = false
        root.startCatalog()
        return
      }
      if (root.busy) {
        root.busy = false
        root.setStatus(wallpapersModel.count > 0
          ? Model.catalogStatus(wallpapersModel.count, root.themeName)
          : "Error loading catalog")
      }
    }
  }

  // ---- custom install catalog -----------------------------------------------
  // Same request-stamp pattern as `catalogProc`, on its own model so the
  // custom-install screen never touches the wallpapers grid.
  Process {
    id: customCatalogProc
    property int requestedSerial: 0
    property string requestedTheme: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (customCatalogProc.requestedSerial !== root.customSerial
            || customCatalogProc.requestedTheme !== root.customThemeName)
          return
        root.applyCustomCatalog(customCatalogProc.requestedTheme,
          Model.parseCatalog(text))
      }
    }
    onExited: {
      if (root.customLoading) root.customLoading = false
      // The post-action recompute is done: release the action overlay and stay
      // on the custom screen (Esc only stopped the running install).
      root.customReloading = false
    }
  }

  // Idle catalog prefetch (one theme at a time): parse a theme into the
  // in-memory cache without touching the visible model, so Custom Install opens
  // without spawning manager.sh. The last requested theme wins.
  Process {
    id: catalogPrefetchProc
    property string requestedTheme: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var theme = catalogPrefetchProc.requestedTheme
        if (theme === "" || root.customCatalogCache[theme]) return
        root.customCatalogCache[theme] = Model.parseCatalog(text)
      }
    }
    onExited: {
      var next = root.pendingCustomPrefetch
      root.pendingCustomPrefetch = ""
      if (next !== "") root.prefetchCustomCatalog(next)
      // Continue draining the whole-theme warm-up queue.
      root.advanceCustomPrefetch()
    }
  }

  // ---- action result --------------------------------------------------------
  Process {
    id: actionProc
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("PROGRESS\t") !== 0) return
        var parts = line.split("\t")
        if (parts.length < 3) return
        root.applyProgress(parts[1], parseInt(parts[2], 10),
          parts.length > 3 ? parseInt(parts[3], 10) : NaN)
      }
    }
    onExited: {
      var cancelled = root.actionCancelled
      // The closing random-default step is over (whether it ran or not).
      root.customFinalStep = false
      // Captured before the reset below: the action changed this theme's
      // on-disk state, so its cached parse must be dropped.
      var actedTheme = root.actionTheme
      // Raise the post-action overlay BEFORE clearing `actionRunning`, so the
      // custom-install spinner never blinks off between the two flags: it reads
      // `actionRunning || customReloading`.
      var willReloadCustom = (root.view === "custom")
      if (willReloadCustom) {
        // Caption during the recompute: the action is done, so do not keep the
        // stale download count ("Downloading 250…" jumping to 1 on re-read).
        // Cancelled already says "Stopping…" (set by cancelAction); a finished
        // action reads "Updating…".
        if (!cancelled) root.customBusyLabel = "Finalizing…"
        root.customReloading = true
      }
      root.actionCancelled = false
      root.busy = false
      root.actionRunning = false
      // Apply the last buffered progress before dropping it: a fast local
      // remove can finish before the throttle timer ever fires, so the themes
      // list would otherwise stay at the pre-action count until a reload.
      root.flushProgress()
      progressTimer.stop()
      root.setStatus(cancelled ? "Operation cancelled" : "Operation completed")
      // Update the in-memory catalog in place; no full reload (see docs/DEVELOPMENT.md).
      if (!cancelled) root.applyActionResult()
      // Custom install: refresh the option counts in place from the in-memory
      // catalog (no slow `manager.sh catalog` re-read — the data is already
      // here, from the grid/prefetch or the last load), then release the
      // overlay. `applyCustomActionResult` keeps the overlay up for the rare
      // unknown-file case (random install) by reloading.
      if (willReloadCustom) root.applyCustomActionResult()
      else root.customReloading = false
      // Refresh the storage-cap flag after the on-disk state changed.
      root.loadLimits()
      // A selection-based install/remove clears the checks when it is done.
      if (root.actionClearsChecks) {
        root.actionClearsChecks = false
        root.clearWallpaperSelection()
      }
      root.actionTheme = ""
      root.lastAction = []
      // The switch applies after an install that finished; a stopped install
      // must not chain a fresh random-default download, or Esc would appear to
      // reopen the overlay by itself.
      var randomDefaultTheme = root.pendingCustomRandomDefault
      root.pendingCustomRandomDefault = ""
      if (!cancelled && randomDefaultTheme !== "")
        root.applyCustomRandomDefault(randomDefaultTheme)
    }
  }

  // ---- image cache processes ------------------------------------------------
  // One in-flight request each for the detail pane and the fullscreen preview;
  // the manifest id rides along so manager.sh picks the right cache directory.
  Process {
    id: detailImageProc

    property string requestedUrl: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "" && detailImageProc.requestedUrl === root.pendingDetailUrl) {
          root.detailImageSource = detailImageProc.requestedUrl
          root.detailImagePath = path
          root.pendingDetailUrl = ""
          root.refreshDetailShown()
        }
      }
    }
    onExited: Qt.callLater(root.startDetailResolution)
  }

  Process {
    id: previewImageProc

    property string requestedUrl: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "" && previewImageProc.requestedUrl === root.pendingPreviewUrl) {
          root.previewImageSource = previewImageProc.requestedUrl
          root.previewImagePath = path
          root.pendingPreviewUrl = ""
        }
      }
    }
    onExited: Qt.callLater(root.startPreviewResolution)
  }

  // Neighbour warm-up: collects `url<TAB>path` lines and records them so the
  // preview can load the local file as soon as the user navigates.
  Process {
    id: prewarmProc

    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split("\t")
        if (parts.length < 2 || parts[1] === "") return
        root.imagePathByUrl[parts[0]] = parts[1]
        root.imageCacheRevision++
      }
    }
    onExited: {
      if (root.pendingPrefetch.length > 0) {
        var next = root.pendingPrefetch
        root.pendingPrefetch = []
        root.startPrewarm(next)
      }
    }
  }

  // "Download original": Omarchy's portal file chooser for the folder, then the
  // original file is copied there by manager.sh. The overlay is closed while the
  // chooser runs (it is a normal window, hidden behind an overlay layer).
  Process {
    id: folderProc

    command: ["omarchy-file-select", "--directory", "--title", "Save wallpaper to…"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var dir = String(text || "").trim().split("\n")[0]
        if (dir === "") {
          root.opened = true
        } else {
          root.pendingDownloadDest = dir
          root.startDownload()
        }
      }
    }
  }

  Process {
    id: downloadProc

    property string requestedUrl: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "") {
          Quickshell.execDetached(["omarchy-notification-send",
            "Wallpaper saved", path])
        } else {
          Quickshell.execDetached(["omarchy-notification-send", "-u", "normal",
            "Download failed", downloadProc.requestedUrl])
        }
        root.pendingDownloadUrl = ""
        root.pendingDownloadDest = ""
        // Bring the overlay back to where the user was.
        root.opened = true
      }
    }
  }

  // Debounce: fast list navigation issues one prewarm for the final position.
  Timer {
    id: prefetchTimer
    interval: 150
    onTriggered: root.prefetchNeighbours()
  }

  // Re-arms hover selection after a view switch (see `hoverArmed`).
  Timer {
    id: hoverGate
    interval: 250
    onTriggered: root.hoverArmed = true
  }

  // Automatic rotation tick. `keepLoaded` keeps this overlay mounted from shell
  // start, so the timer runs even with the overlay closed; it follows the Setup
  // settings live. The first change lands one full interval after enabling
  // (`triggeredOnStart` stays false), and `rotateWallpaper()` skips a tick when
  // the previous one is still running.
  Timer {
    id: rotationTimer
    interval: Math.max(1, settings.rotationInterval) * 60000
    running: settings.rotationEnabled
    repeat: true
    onTriggered: root.rotateWallpaper()
  }

  // Coalesce bulk progress into ~8 updates/s instead of one per wallpaper.
  Timer {
    id: progressTimer
    interval: 120
    onTriggered: root.flushProgress()
  }

  // ===========================================================================
  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wallpaper-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    // Single flat card, exactly like the first-party overlays: no header or
    // footer fills, separation comes from spacing and Ui/PanelSeparator.
    BorderSurface {
      id: card

      visible: root.opened
      anchors.centerIn: parent
      width: Math.min(Style.space(1180), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), parent.height - Style.gapsOut * 2)
      color: root.background
      radius: Style.cornerRadius
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Delete is not part of the canonical key set (PanelKeyCatcher maps x/X
      // to `deleteRequested`, the global close); PageUp/PageDown and F1 are not
      // mapped either. All bubble up here. Backspace is handled only inside a
      // search (filter editing); outside one it does nothing. While a search is
      // active the catcher is blocked and this handler owns every key.
      Keys.onPressed: function(event) {
        if (root.searching) {
          if (event.key === Qt.Key_Escape) {
            if (root.currentFilter() !== "") root.clearFilter()
            else root.stopSearch()
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            // Move focus between the filter-row controls (dropdown / search /
            // Select all / Clear), like the Setup screen's content area.
            root.moveFilterField(event.key === Qt.Key_Right ? 1 : -1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (root.view === "wallpapers")
              root.moveFilterField(event.key === Qt.Key_Backtab ? -1 : 1)
            else
              root.stopSearch()
            event.accepted = true
          } else if (Util.editsFilter(event, root.currentFilter())) {
            root.applyFilter(Util.editedFilter(event, root.currentFilter()))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveCursor(0, -1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            // Empty field: Down leaves the search and returns focus to the
            // list; with an active filter it keeps navigating the results.
            if (root.currentFilter() === "") root.stopSearch()
            else root.moveCursor(0, 1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.pageCursor(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.pageCursor(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateCursor()
            root.stopSearch()
            event.accepted = true
          } else if (event.text && event.text.length === 1
              && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
              && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.applyFilter(root.currentFilter() + event.text)
            event.accepted = true
          }
          return
        }
        if (event.key === Qt.Key_F1) {
          // GUI habit: F1 is the classic Help key. Same target as `?`, ignored
          // while an action runs.
          if (!root.actionRunning) root.openHelp()
          event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          root.actionRemove()
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.pageCursor(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.pageCursor(-1)
          event.accepted = true
        } else if ((root.view === "themes" || root.view === "wallpapers")
            && event.text === "/") {
          // The catcher forwards `/` as a text key without accepting it, so it
          // reaches this handler: open the search without the slash landing in
          // its own filter.
          root.startSearch()
          event.accepted = true
        }
      }

      PanelKeyCatcher {
        id: keys

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // Search owns the keyboard entirely: let the card's fallback handle it.
        // Same while a dropdown popup is open (Setup interval / collections),
        // so its list gets the arrows / Enter / Esc.
        blocked: root.searching || settings.setupDropdownOpen
          || (wallpapersCollectionDropdown() && wallpapersCollectionDropdown().popupOpen)

        onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
        // Enter also fires `activateRequested`, so the flag drops that second
        // call and Space keeps its own meaning (see `enterHandled`).
        onReturnRequested: {
          root.enterHandled = true
          root.activateCursor()
        }
        onActivateRequested: {
          if (root.enterHandled) {
            root.enterHandled = false
            return
          }
          root.spaceCursor()
        }
        onCloseRequested: root.dismissCursor()
        // `x`/`X`: a second global close shortcut (PanelKeyCatcher emits
        // `deleteRequested` for both).
        onDeleteRequested: root.requestClose()
        onTextKey: function(text) { root.handleTextKey(text) }
        onTabRequested: function(direction) {
          // Only Esc is accepted while an action runs.
          if (root.actionRunning) return
          if (root.view === "setup") settings.cycleSetupArea(direction)
          else if (root.view === "themes") {
            // Tab toggles between the theme list and the detail action row.
            if (root.themeFocus < 0) root.enterThemeActions()
            else root.leaveThemeActions()
          }
          else if (root.view === "custom") {
            // Tab jumps between the option list and the trailing switch.
            root.customSelection = root.customSelection >= root.customSwitchRow
              ? 0 : root.customSwitchRow
          }
          else if (root.filterRowFocused) root.moveFilterField(direction)
          else if (root.view === "wallpapers" && !root.searching) root.startSearch()
        }

        // ---- hero -----------------------------------------------------------
        HeroBar {
          id: heroBar

          visible: root.view !== "preview"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.heroHeight
          view: root.view
          themeName: root.themeName
          collectionLabel: root.collectionLabel
          versionedName: root.versionedName
          logoPath: root.logoPath
          dev: root.dev
          actionRunning: root.actionRunning
          saved: settings.saved
          wallpapers: root.globalCounts.wallpapers
          installed: root.globalCounts.installed
          favorites: root.globalCounts.favorites
          storageLimitReached: root.storageLimitReached
          storageLimitReason: root.storageLimitReason
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onRefreshRequested: root.refresh()
          onBackRequested: root.view === "help"
            ? root.closeHelp()
            : (root.view === "setup"
              ? root.closeSetup()
              : (root.view === "custom" ? root.closeCustomInstall() : root.goBack()))
          onCloseRequested: root.close()
          onHelpRequested: root.openHelp()
          onReleasesRequested: {
            Qt.openUrlExternally(root.pluginLinks.releases)
            root.close()
          }
          onGithubRequested: {
            Qt.openUrlExternally(root.pluginRepoUrl)
            root.close()
          }
          onShowThemesRequested: root.showThemes()
          onLimitRequested: root.openSetupDownload()
        }

        PanelSeparator {
          id: heroRule
          visible: root.view !== "preview"
          anchors.top: heroBar.bottom
          anchors.topMargin: Style.space(14)
          // Full card width: cancel the content padding so the rule reaches the
          // border on both sides.
          anchors.left: parent.left
          anchors.leftMargin: -card.leftPadding
          width: card.width - card.borderLeft - card.borderRight
          foreground: root.foreground
        }

        // ---- content: one screen at a time ----------------------------------
        // A single Loader mounts only the active screen, so leaving it destroys
        // the previous one: no background screen can hold focus, take clicks or
        // leak a popup over the next screen. Navigation state lives in `root`
        // and `settings`, so destroying and rebuilding loses nothing.
        Loader {
          id: contentLoader

          anchors.top: heroRule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: actionFooter.top
          // Custom Install's previews are full-bleed on the left and the themes
          // detail image on the right: pull the loader itself (not the loaded
          // item, which the Loader resizes, so its own anchors are ignored) so
          // each reaches the card border. The views compensate their pane split
          // for the bleed (see leftBleed / rightBleed).
          anchors.leftMargin: root.view === "custom" ? -card.leftPadding : 0
          anchors.rightMargin: root.view === "themes" ? -card.rightPadding : 0
          sourceComponent: root.view === "themes" ? themesComponent
            : root.view === "custom" ? customComponent
            : root.view === "help" ? helpComponent
            : root.view === "setup" ? setupComponent
            : root.view === "wallpapers" ? wallpapersComponent
            : null
          onLoaded: {
            if (item) item.forceActiveFocus()
            root.restoreViewScroll()
          }
        }

        // ---- first-run warm-up overlay --------------------------------------
        // Covers the body while `manager.sh warm` fetches the datasets and
        // catalogs for the first time, so opening the overlay before it finishes
        // shows "Initiating…" instead of an empty theme list.
        RunningOverlay {
          anchors.top: heroRule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: actionFooter.top
          z: 8
          running: root.opened && root.warming && themesModel.count === 0
          label: "Initiating…"
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
        }

        Component {
          id: themesComponent

          ThemeSelectionView {
            manager: root
            shuffleCount: settings.shuffleCount
            // Full-bleed on the right: the loader is pulled past the content
            // padding (above); the view compensates its pane split so the
            // master list and its divider keep their margins.
            rightBleed: card.rightPadding
          }
        }

        Component {
          id: customComponent

          CustomInstallView {
            manager: root
            // The loader is pulled left by the card padding, so the view
            // compensates its pane split to keep the right side in place.
            leftBleed: card.leftPadding
          }
        }

        Component {
          id: helpComponent

          HelpView {
            helpRoot: root.helpRoot
            settings: settings
            links: {
              var l = root.pluginLinks
              return {
                repo: l.repo,
                donation: l.donation,
                issues: l.issues,
                releases: l.releases,
                database: root.pluginDatabaseUrl
              }
            }
            roadmap: root.roadmapData
            index: root.helpIndex
            // Same master-pane width as the themes screen, so the two sidebars
            // line up exactly.
            sidebarWidth: root.themePaneWidth
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            // A link opens a normal browser window under the overlay: hide the
            // panel so the page is visible.
            onLinkOpened: root.close()
          }
        }

        Component {
          id: setupComponent

          SetupView {
            settings: settings
            localFileCount: root.localFileCount
            localBytes: root.localBytes
            rotateBusy: settings.rotateBusy
            pluginVersion: root.pluginVersion
            cdnVersion: root.cdnBaseVersion
            securityUrl: root.marketplaceUrl
            changelogUrl: root.pluginReleasesUrl
            cdnChangelogUrl: root.wallpapersReleasesUrl
            issuesUrl: root.pluginIssuesUrl
            updateState: root.updateCheckState
            updateRemoteVersion: root.updateRemoteVersion
            roadmap: root.roadmapData
            featureLabel: root.helpIndex && root.helpIndex.feature
              ? root.helpIndex.feature.title : ""
            sidebarWidth: root.themePaneWidth
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            onFeatureClicked: {
              if (root.helpFeatureUrl !== "") {
                Qt.openUrlExternally(root.helpFeatureUrl)
                root.close()
              }
            }
            onRotateRequested: root.rotateWallpaper()
            onSecurityRequested: root.openExternalUrl(root.marketplaceUrl)
            onChangelogRequested: root.openExternalUrl(root.pluginReleasesUrl)
            onCdnChangelogRequested: root.openExternalUrl(root.wallpapersReleasesUrl)
            onProposeFeatureRequested: root.openExternalUrl(root.pluginIssuesUrl)
            onCheckRequested: root.checkForUpdates()
            // The interval popup lives in the view; wire it into the shared
            // keyboard state while the screen is mounted.
            Component.onCompleted: settings.activateSetupCursor = openIntervalDropdown
            Component.onDestruction: settings.activateSetupCursor = null
          }
        }

        Component {
          id: wallpapersComponent

          WallpapersView {
            manager: root
            ruleX: -card.leftPadding
            ruleWidth: card.width - card.borderLeft - card.borderRight
          }
        }

        // ---- footer: actions + status ---------------------------------------
        // No footer bar: a separator, borderless controls on the flat surface
        // and a dim caption for status, as in the first-party panels.
        ActionFooter {
          id: actionFooter

          visible: true
          // Kept above `previewView` (z: 10) so its controls stay clickable on
          // the fullscreen preview.
          z: 11
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: -root.footerOverlap
          view: root.view
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          statusInstalled: root.statusInstalled
          fontFamily: root.fontFamily
          actionRunning: root.actionRunning
          installedCount: root.themeCounts.installed
          availableCount: root.themeCounts.available
          progressTheme: root.progressTheme
          checkedCount: root.checkedCount
          wallpapersInstallEnabled: root.wallpapersCanInstall
          wallpapersRemoveEnabled: root.wallpapersCanRemove
          wallpapersFavoriteEnabled: root.wallpapersCanFavorite
          storageLimitReached: root.storageLimitReached
          currentInstalled: root.currentInstalled
          sidebarWidth: root.themePaneWidth
          customPaneWidth: root.customPaneWidth
          customInstallEnabled: root.customCanInstall
          customRemoveEnabled: root.customCanRemove
          ruleX: -card.leftPadding
          ruleWidth: card.width - card.borderLeft - card.borderRight
          setupDropdownOpen: settings.setupDropdownOpen
          setupEditing: settings.setupEditing
          footerSpacing: root.footerSpacing
          onInstallRequested: root.actionInstall()
          onRemoveRequested: root.actionRemove()
          onFavoriteRequested: root.toggleFavoriteTargets()
          onHelpRequested: root.openHelp()
          onSetupRequested: root.openSetup()
          onDatabaseRequested: root.helperDatabaseUrl()
          onCustomInstallRequested: root.executeCustomInstall()
          onCustomRemoveRequested: root.executeCustomRemove()
          onOpenRepoRequested: {
            Qt.openUrlExternally(root.pluginRepoUrl)
            root.close()
          }
        }

        // ---- fullscreen preview ---------------------------------------------
        Loader {
          id: previewLoader

          anchors.fill: parent
          z: 10
          active: root.view === "preview"
          sourceComponent: previewComponent
        }

        Component {
          id: previewComponent

          PreviewView {
            manager: root
            cardLeftPadding: card.leftPadding
            cardRightPadding: card.rightPadding
            ruleWidth: card.width - card.borderLeft - card.borderRight
            footerHeight: actionFooter.height
          }
        }
      }
    }
  }
}
