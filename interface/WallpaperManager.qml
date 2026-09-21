import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
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
  readonly property string pluginRepoUrl: pluginLinks.repo
    ? String(pluginLinks.repo) : "https://github.com/emkcloud/omarchy-wallpapers-plugin"

  // Setup screen settings: persisted per plugin id under the user config, so
  // the official and developer installs never share them.
  readonly property string settingsDir: Quickshell.env("HOME") + "/.config/omarchy/" + pluginId
  // Empty until the manifest is injected: the fallback id would point at the
  // official settings file and its (failed) load would lock the Setup defaults
  // before the real developer path is known.
  readonly property string settingsPath: manifest && manifest.id
    ? settingsDir + "/settings.json" : ""

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  property string view: "themes"          // "themes" | "wallpapers" | "preview" | "help" | "setup"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  // Themes-screen cursor to restore when leaving a theme (goBack): browsing a
  // theme must not lose which row was open.
  property int lastThemeIndex: 0
  // Wallpaper cursor per theme (`themeName` -> index), so re-entering a theme
  // resumes where it was left instead of jumping back to the first tile.
  property var wallpaperCursorByTheme: ({})
  property int pendingWallpaperIndex: 0
  property bool pendingWallpaperSelect: false
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
  onCollectionFilterChanged: if (collectionDropdown) collectionDropdown.value = collectionFilter
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
  // Arguments of the running/last action, so `onExited` can apply its effect to
  // the in-memory catalog instead of reloading the whole thing.
  property var lastAction: []
  // "Add remote source" placeholder: shows a COMING SOON label for 3s on click.
  property bool addSourceSoon: false
  // Custom Install placeholder: same COMING SOON feedback, always clickable.
  property bool setupSoon: false
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
  readonly property real maxDiskBytes: setupSettings.maxDiskGb * 1073741824
  // A small headroom: the bulk installer stops when the remaining budget is
  // below the smallest wallpaper, so the used size can sit just under the cap
  // while nothing else fits.
  readonly property real diskLimitSlack: 8 * 1024 * 1024
  readonly property bool storageLimitReached: localFileCount >= setupSettings.maxLocalFiles
    || localBytes + diskLimitSlack >= maxDiskBytes
  // Which cap triggered it, with its value, so the banner is self-explanatory
  // ("Storage limit 1000" vs "Storage limit 3 GB").
  readonly property string storageLimitReason: {
    var fileHit = localFileCount >= setupSettings.maxLocalFiles
    var diskHit = localBytes + diskLimitSlack >= maxDiskBytes
    if (fileHit && diskHit)
      return "Storage limit " + setupSettings.maxLocalFiles + " · " + setupSettings.maxDiskGb + " GB"
    if (fileHit) return "Storage limit " + setupSettings.maxLocalFiles
    if (diskHit) return "Storage limit " + setupSettings.maxDiskGb + " GB"
    return ""
  }

  // ---- image cache ----------------------------------------------------------
  // Big remote images are downloaded once by `manager.sh image` into
  // ~/.cache/omarchy/<pluginId>/ and then loaded from disk, so switching
  // selection never re-downloads or re-decodes the 2K original. The id comes
  // from the injected manifest, so the official and developer installs keep
  // separate caches.
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "emkcloud.wallpaper-manager"
  // Version from the injected manifest and the "name + version" label shown in
  // the themes and Setup hero metas.
  readonly property string pluginVersion: manifest && manifest.version
    ? String(manifest.version) : ""
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
  // "Download original": the URL queued and the folder chosen in the picker.
  property string pendingDownloadUrl: ""
  property string pendingDownloadDest: ""
  // Live progress is coalesced: `manager.sh` emits one line per wallpaper and
  // applying each one would re-evaluate the themes screen hundreds of times
  // during an install. Buffer the latest value and flush on a timer instead.
  property string pendingProgressTheme: ""
  property int pendingProgressInstalled: -1

  // Cursor model (see Ui/CursorSurface.qml): mouse hover and keyboard share a
  // single cursor. Items derive their visuals from `hasCursor`, never from
  // `containsMouse`, so only one tile is ever highlighted.
  property bool cursorActive: true

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

  // The two heroes (grid / fullscreen preview) are pinned to the same height so
  // switching view — or a title that grows a resolution suffix — never shifts
  // the separator and the content below it.
  readonly property int heroHeight: Math.max(hero.implicitHeight, previewHero.implicitHeight)

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
      if (Model.wallpaperMatches(row, wallpaperFilterText, collectionFilter))
        wallpapersDisplayModel.append(row)
    }
    wallpapersRevision++
  }

  // Collections present in the open theme, as Dropdown options ("All
  // collections" first). `wallpapersRevision` makes the binding re-read the
  // rows after a catalog reload (`ListModel.get()` is not tracked).
  readonly property var collectionOptions: {
    var rev = wallpapersRevision
    var rows = []
    for (var i = 0; i < wallpapersModel.count; i++) rows.push(wallpapersModel.get(i))
    return Model.collectionOptions(rows)
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
    var item = currentItem()
    var cmd = lastAction.length > 0 ? String(lastAction[0]) : ""
    if (cmd === "remove") return "Removing…"
    if (cmd === "uninstall-default") return "Clearing default…"
    if (cmd === "set-default" && item && String(item.installed) === "1")
      return "Setting default…"
    if (item) {
      var size = Model.formatSize(item.sizeBytes)
      return size !== "" ? "Downloading " + size + "…" : "Downloading…"
    }
    if (cmd === "random-install")
      return "Shuffling in " + setupSettings.shuffleCount + " wallpapers…"
    var theme = actionTheme !== "" ? themeByName(actionTheme) : selectedTheme
    var count = theme ? (theme.count || 0) : 0
    return count > 0 ? "Downloading " + count + " wallpapers…" : "Downloading…"
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
    var wallpapers = 0
    var installed = 0
    for (var i = 0; i < themesModel.count; i++) {
      var theme = themesModel.get(i)
      wallpapers += (theme.count || 0)
      installed += (theme.installed || 0)
    }
    return { "wallpapers": wallpapers, "installed": installed }
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
    actionTheme = ""
    actionCancelled = false
    actionRunning = false
    actionClearsChecks = false
    clearWallpaperSelection()
    addSourceSoon = false
    setupSoon = false
    loadThemes()
  }

  function close() {
    // A dropdown popup is a separate window and would outlive the overlay.
    if (collectionDropdown && collectionDropdown.popupOpen) collectionDropdown.close()
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
      "WALLPAPER_MANAGER_PARALLEL=" + setupSettings.parallelDownloads,
      "WALLPAPER_MANAGER_MAX_FILES=" + setupSettings.maxLocalFiles,
      "WALLPAPER_MANAGER_MAX_DISK_GB=" + setupSettings.maxDiskGb,
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
    searching = true
  }

  // Leave the search editor but keep the filter, so Tab can cycle back in/out.
  function stopSearch() {
    searching = false
    Qt.callLater(function() { keys.forceActiveFocus() })
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
      Qt.callLater(function() { themesList.positionViewAtIndex(0, ListView.Beginning) })
  }

  function setWallpaperFilter(text) {
    var next = String(text || "")
    if (next === wallpaperFilterText) return
    wallpaperFilterText = next
    if (wallpaperFilterText !== "" || collectionFilter !== "") rebuildWallpaperDisplay()
    selectedIndex = 0
    cursorActive = true
    if (activeWallpapersModel.count > 0)
      Qt.callLater(function() { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  // Narrow the grid to one collection ("" = all). Shares the rebuild/cursor
  // reset with the text filter so the two compose.
  function setCollectionFilter(value) {
    var next = String(value || "")
    if (next === collectionFilter) return
    collectionFilter = next
    if (wallpaperFilterText !== "" || collectionFilter !== "") rebuildWallpaperDisplay()
    selectedIndex = 0
    cursorActive = true
    if (activeWallpapersModel.count > 0)
      Qt.callLater(function() { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  // The dataset carries a readable `title` ("Tokyo Night"); the tiles show it
  // uppercased. Fallback for older datasets: normalize the slug. See Model.js.
  function selectTheme(index) {
    if (index < 0 || index >= activeThemesModel.count) return
    var item = activeThemesModel.get(index)
    lastThemeIndex = index
    // Drop the previous theme's rows first: the wallpapers GridView delegates
    // survive the trip through the themes view, so leaving them alive while
    // `themeName` changes makes them re-resolve their local file path against
    // the new theme and log a pile of "Cannot open" warnings.
    wallpapersModel.clear()
    wallpaperFilterText = ""
    collectionFilter = ""
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
    view = "themes"
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, lastThemeIndex))
    cursorActive = true
    setStatus("")
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { themesList.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
  }

  // Help screen: opened from the hero Help button on any screen (or `?` on the
  // themes list). Esc / Back returns to where it was opened from; the topic
  // cursor lives in HelpView.
  property string helpReturnView: "themes"
  // Setup screen: opened with `s` on any screen (or the hero Setup / footer
  // buttons). It is a leaf like Help, so Esc / Back retraces the origin.
  property string setupReturnView: "themes"

  function openHelp() {
    helpReturnView = (view === "wallpapers" || view === "preview") ? view : "themes"
    view = "help"
    cursorActive = true
    setStatus("")
  }

  function closeHelp() {
    if (helpReturnView === "preview" || helpReturnView === "wallpapers") {
      view = helpReturnView
      cursorActive = true
      setStatus("")
      if (helpReturnView === "wallpapers")
        Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
      return
    }
    // Coming back from the themes list: keep the cursor exactly where it was
    // (not `lastThemeIndex`, which is the last theme that was *opened*).
    view = "themes"
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, selectedIndex))
    setStatus("")
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { themesList.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
  }

  // Setup screen: a placeholder screen like Help but empty. Reached with `s`
  // on any screen or from the setup buttons; Esc / Back returns to the origin.
  function openSetup() {
    if (view === "setup") return
    setupReturnView = (view === "wallpapers" || view === "preview" || view === "help")
      ? view : "themes"
    view = "setup"
    cursorActive = true
    setStatus("")
  }

  function closeSetup() {
    setupSettings.commitEdit()
    view = setupReturnView
    cursorActive = true
    setStatus("")
    if (setupReturnView === "wallpapers")
      Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
  }

  // Open Setup on the Download section: the storage-limit banner links here.
  function openSetupDownload() {
    if (view !== "setup") openSetup()
    setupSettings.selectSection("download")
  }

  // Hero "Wallpaper manager" button on Help: jump straight to the theme list
  // from anywhere in the guide (unlike closeHelp, which retraces the origin).
  function showThemes() {
    view = "themes"
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1,
      helpReturnView === "themes" ? selectedIndex : lastThemeIndex))
    setStatus("")
    if (activeThemesModel.count > 0)
      Qt.callLater(function() { themesList.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
  }

  function refresh() {
    if (actionRunning) return
    if (view === "themes") loadThemes()
    else if (view === "wallpapers" || view === "preview") loadWallpapers()
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
    if (view === "themes") themesList.positionViewAtIndex(index, ListView.Contain)
    else grid.positionViewAtIndex(index, GridView.Contain)
  }

  function stepCursor(step) {
    var count = activeCount()
    if (count === 0) return

    cursorActive = true
    selectedIndex = Model.stepIndex(selectedIndex, step, count)
    positionActive(selectedIndex)
  }

  function moveCursor(dx, dy) {
    // While an action runs the UI is frozen: only Esc is accepted (it cancels),
    // so arrows/h/j/k must not move the cursor on any screen.
    if (actionRunning) return
    if (view === "setup") {
      setupSettings.moveCursor(dx, dy)
      return
    }
    if (view === "help") {
      helpView.moveSelection(dy !== 0 ? dy : dx)
      return
    }
    if (view === "preview") {
      previewNext(dx !== 0 ? dx : dy)
      return
    }
    if (view === "themes") {
      var step = dy !== 0 ? dy : dx
      // Up from the first row moves the focus into the search field.
      if (step < 0 && selectedIndex === 0) {
        startSearch()
        return
      }
      stepCursor(step)
      return
    }

    // Up from the first row moves the focus into the search field.
    if (dy < 0 && selectedIndex < grid.colCount) {
      startSearch()
      return
    }
    stepCursor(dx !== 0 ? dx : dy * grid.colCount)
  }

  // PageUp/PageDown: jump a whole visible page of tiles (rows on screen ×
  // columns; rows only on the themes list). PanelKeyCatcher does not map these
  // keys, so they bubble up to the card's Keys.onPressed fallback.
  function pageCursor(dir) {
    if (actionRunning) return
    // Setup: page between sections (clamped at the ends).
    if (view === "setup") {
      setupSettings.pageSection(dir)
      return
    }
    // Help: page through the central topic content.
    if (view === "help") {
      helpView.scrollPage(dir)
      return
    }
    if (view === "preview") {
      previewNext(dir)
      return
    }
    if (view === "themes") {
      var rows = Math.max(1, Math.floor(themesList.height / root.themeRowHeight))
      stepCursor(dir * rows)
      return
    }

    var g = grid
    var visibleRows = Math.max(1, Math.floor(g.height / g.cellHeight))
    stepCursor(dir * visibleRows * g.colCount)
  }

  function activateCursor() {
    // While an action runs Esc is the only command (it stops the process).
    if (actionRunning) return
    if (view === "setup") {
      setupSettings.activateCursor()
      return
    }
    if (view === "help") helpView.activateSelection()
    else if (view === "themes") selectTheme(selectedIndex)
    else if (view === "wallpapers") showPreview()
    else actionInstall()
  }

  // Space: on the wallpapers screen it checks/unchecks the cursor tile; on the
  // other screens it behaves like Enter.
  function spaceCursor() {
    if (actionRunning) return
    if (view === "wallpapers") {
      var item = currentItem()
      if (item) toggleWallpaperCheck(item.filename)
      return
    }
    activateCursor()
  }

  function dismissCursor() {
    // While an action runs, Esc stops it instead of navigating away; a second
    // Esc then closes/backs out.
    if (actionRunning) {
      cancelAction()
      return
    }
    // Setup and Help are leaf screens: Esc / Back retraces the origin. While a
    // row is in edit mode Esc cancels it instead (reverts the value).
    if (view === "setup") {
      if (setupSettings.editing) {
        setupSettings.cancelEdit()
        return
      }
      closeSetup()
      return
    }
    if (view === "help") {
      closeHelp()
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
    actionRunning = false
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
      if (text === "d" || text === "D") setupSettings.restoreDefaults()
      return
    }
    // The help screen: `p` proposes a feature, `d` opens the version dataset;
    // Enter/Space pick a topic, Esc goes back, everything else is ignored.
    if (view === "help") {
      if (text === "p" || text === "P") helpView.openFeature()
      else if (text === "d" || text === "D") helpView.openDatabase()
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
      // Custom Install is always active, like its button.
      if (themeAction === "custom") {
        triggerSetup()
        return
      }
      if (themeAction === "help") {
        openHelp()
        return
      }
      // Same rule as the buttons: no bulk task while one is running.
      if (actionRunning) return
      if (themeAction === "install") actionInstallTheme()
      else if (themeAction === "uninstall") actionRemoveThemeAll()
      else if (themeAction === "shuffle") actionRandomInstall()
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
  }

  function takeCursor(index) {
    cursorActive = true
    selectedIndex = index
  }

  // "Add remote source" placeholder: a click or the `a` key flashes the COMING
  // SOON label for 3s, then it reverts.
  function triggerAddSource() {
    addSourceSoon = true
    addSourceReset.restart()
  }

  // Custom Install placeholder: same 3s COMING SOON feedback. Kept clickable
  // even while an operation runs.
  function triggerSetup() {
    setupSoon = true
    setupReset.restart()
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
    var rev = setupSettings.themeDefaultsRevision
    var d = setupSettings.themeDefault(themeName)
    return !!d && String(d.filename) === String(model.filename)
  }

  function currentItem() {
    if ((view !== "wallpapers" && view !== "preview")
        || selectedIndex < 0 || selectedIndex >= activeWallpapersModel.count)
      return null
    return activeWallpapersModel.get(selectedIndex)
  }

  function showPreview() {
    if (activeWallpapersModel.count === 0) return
    view = "preview"
  }

  function closePreview() {
    view = "wallpapers"
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex))
    // Deferred: the GridView only becomes visible on the view change, so
    // scrolling in the same frame reads stale geometry and lands nowhere.
    Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
  }

  function previewNext(delta) {
    if (activeWallpapersModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex + delta))
  }

  function actionInstall() {
    if (actionRunning) return
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
        setupSettings.clearThemeDefault(themeName)
        setStatus("Clearing default: " + item.name + "…")
        runAction(["unset-default", themeName, item.filename])
      } else {
        setupSettings.setThemeDefault(themeName, item.filename, item.url)
        setStatus("Setting default: " + item.name + "…")
        runAction(["set-default", themeName, item.filename, item.url])
      }
      return
    }
    // Another theme: remember the choice (making sure the file lands on disk)
    // and leave the current background untouched.
    var remembered = setupSettings.themeDefault(themeName)
    if (remembered && String(remembered.filename) === String(item.filename)) {
      setupSettings.clearThemeDefault(themeName)
      setStatus("Default cleared for " + Model.ucfirst(themeName))
      return
    }
    setupSettings.setThemeDefault(themeName, item.filename, item.url)
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

  function actionRandomDefault() {
    var theme = selectedTheme
    if (!theme) return
    busy = true
    setStatus("Setting a random default for " + theme.name + "…")
    runAction(["random-default", theme.name])
  }

  // Install a shuffled sample of the selected theme's wallpapers. The count
  // comes from Setup (default 5, range 1-50).
  function actionRandomInstall() {
    var theme = selectedTheme
    if (!theme || storageLimitReached) return
    var count = Math.max(1, Math.min(50, setupSettings.shuffleCount))
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
    if (setupSettings.rotationAllTheme) args.push("--all")
    if (setupSettings.rotationRandom) args.push("--random")
    rotationProc.command = scriptCmd(args)
    rotationProc.running = true
  }

  // ---- per-theme default apply on switch ------------------------------------
  // `omarchy-theme-set` writes `theme.name` *before* it picks the new theme's
  // background, so wait for the switch to settle, then apply the default the
  // user remembered for the newly active theme (downloading it if needed).
  property string pendingThemeDefaultTheme: ""

  function scheduleThemeDefaultApply(theme) {
    pendingThemeDefaultTheme = theme
    themeDefaultApplyTimer.restart()
  }

  function applyThemeDefault(theme) {
    var d = setupSettings.themeDefault(theme)
    if (!d || !d.filename) return
    if (themeDefaultProc.running) {
      pendingThemeDefaultTheme = theme
      themeDefaultApplyTimer.restart()
      return
    }
    themeDefaultProc.applyTheme = theme
    themeDefaultProc.applyFilename = d.filename
    themeDefaultProc.command = scriptCmd(["set-default", theme, d.filename, d.url])
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
    property string applyFilename: ""
    onExited: {
      root.loadLimits()
      // The plugin may be open on the theme that just became active: reflect
      // the applied default (and its installed file) without a full reload.
      if (root.themeName !== "" && Model.normalizeSlug(root.themeName)
            === Model.normalizeSlug(themeDefaultProc.applyTheme)) {
        root.setWallpaperInstalled(themeDefaultProc.applyFilename, "1")
        root.setWallpaperDefault(themeDefaultProc.applyFilename)
      }
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
      if (args.length > 2) {
        for (var i = 2; i < args.length; i++) setWallpaperInstalled(String(args[i]), "1")
      } else setAllWallpapersInstalled("1")
    } else if (cmd === "remove") {
      if (args.length > 2) {
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
  function applyProgress(name, installed) {
    if (!name || !isFinite(installed)) return
    pendingProgressTheme = name
    pendingProgressInstalled = installed
    // Throttle, do not debounce: a fast local remove emits every PROGRESS line
    // back-to-back, so a `restart()` here would keep postponing the flush until
    // the process exits (which then drops the buffered value). Start the timer
    // only if it is idle, so the latest count is applied at most every 120ms.
    if (!progressTimer.running) progressTimer.start()
  }

  function flushProgress() {
    var name = pendingProgressTheme
    var installed = pendingProgressInstalled
    pendingProgressTheme = ""
    pendingProgressInstalled = -1
    if (name === "" || installed < 0) return
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
    // The collection popup is a separate window: close it when the wallpapers
    // screen is left, or it would stay floating over the other views.
    if (view !== "wallpapers" && collectionDropdown && collectionDropdown.popupOpen)
      collectionDropdown.close()
  }
  // A prewarmed neighbour may make the full image available: upgrade the detail
  // pane from the small preview without waiting for the next selection.
  onImageCacheRevisionChanged: refreshDetailShown()

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

  // Automatic rotation: print the picked file as `ROTATE<TAB><path>`; keep the
  // open grid's DEFAULT pill in sync when the rotated wallpaper belongs to the
  // theme currently being browsed (rotation follows the Omarchy theme, which may
  // differ from the theme open in the plugin).
  Process {
    id: rotationProc
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
          Qt.callLater(function() { themesList.positionViewAtIndex(root.selectedIndex, ListView.Contain) })
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
        for (var i = 0; i < rows.length; i++) wallpapersModel.append(rows[i])
        if (root.wallpaperFilterText !== "" || root.collectionFilter !== "")
          root.rebuildWallpaperDisplay()
        root.wallpapersRevision++
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
          Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
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

  // ---- action result --------------------------------------------------------
  Process {
    id: actionProc
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("PROGRESS\t") !== 0) return
        var parts = line.split("\t")
        if (parts.length < 3) return
        root.applyProgress(parts[1], parseInt(parts[2], 10))
      }
    }
    onExited: {
      var cancelled = root.actionCancelled
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
      // Refresh the storage-cap flag after the on-disk state changed.
      root.loadLimits()
      // A selection-based install/remove clears the checks when it is done.
      if (root.actionClearsChecks) {
        root.actionClearsChecks = false
        root.clearWallpaperSelection()
      }
      root.actionTheme = ""
      root.lastAction = []
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
    interval: Math.max(1, setupSettings.rotationInterval) * 60000
    running: setupSettings.rotationEnabled
    repeat: true
    onTriggered: root.rotateWallpaper()
  }

  // Coalesce bulk progress into ~8 updates/s instead of one per wallpaper.
  Timer {
    id: progressTimer
    interval: 120
    onTriggered: root.flushProgress()
  }

  // Reverts the custom "Custom Install" button's COMING SOON label.
  Timer {
    id: setupReset
    interval: 3000
    onTriggered: root.setupSoon = false
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
      // to `deleteRequested`, the global close); PageUp/PageDown are not mapped
      // either. Both bubble up here. Backspace is handled only inside a search
      // (filter editing); outside one it does nothing. While a search is active
      // the catcher is blocked and this handler owns every key.
      Keys.onPressed: function(event) {
        if (root.searching) {
          if (event.key === Qt.Key_Escape) {
            if (root.currentFilter() !== "") root.clearFilter()
            else root.stopSearch()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
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
        if (event.key === Qt.Key_Delete) {
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
        blocked: root.searching || setupSettings.dropdownOpen
          || collectionDropdown.popupOpen

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
          if (root.view === "setup") setupSettings.cycleArea(direction)
          else if ((root.view === "themes" || root.view === "wallpapers")
            && !root.searching) root.startSearch()
        }

        // ---- hero -----------------------------------------------------------
        Component {
          id: heroIcon

          HeroLogo {
            glyph: root.view === "themes" ? "󰸌"
              : (root.view === "help" ? "󰘥"
                : (root.view === "setup" ? "󰒓" : ""))
            source: root.logoPath
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        Component {
          id: heroActions

          Row {
            spacing: Style.spacing.controlGap

            Button {
              visible: root.dev
              text: "DEV"
              iconText: "\uf121"
              bordered: true
              foreground: root.accent
              accent: root.accent
              fontFamily: root.fontFamily
            }

            // Auto-save feedback: first in the row so showing/hiding it never
            // shifts the pill and the buttons that follow.
            Rectangle {
              visible: root.view === "setup" && setupSettings.saved
              width: savedHeroText.implicitWidth + Style.space(24)
              height: refreshButton.implicitHeight
              radius: Style.cornerRadius
              color: Util.alpha(root.accent, 0.16)

              Text {
                id: savedHeroText

                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Saved"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Global store: total wallpapers and installed count across every
            // theme. Also shown in the preview header (see `previewActions`).
            StorePill {
              visible: root.view !== "help"
              controlHeight: refreshButton.implicitHeight
              wallpapers: root.globalCounts.wallpapers
              installed: root.globalCounts.installed
              limitReason: root.storageLimitReached && root.view !== "setup"
                ? root.storageLimitReason : ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onLimitActivated: root.openSetupDownload()
            }

            Button {
              visible: root.view === "themes"
              // Frozen while an action runs, like the preview's actions.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Help"
              iconText: "󰘥"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.openHelp()
            }

            // On Help: jump straight back to the theme list, before GitHub.
            Button {
              visible: root.view === "help"
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Wallpaper manager"
              iconText: "󰸌"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.showThemes()
            }

            Button {
              visible: root.view === "themes" || root.view === "help"
                || root.view === "setup"
              // Frozen while an action runs, like the preview's actions.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "GitHub"
              iconText: "\uf09b"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              // Hide the overlay so the browser does not open behind it.
              onClicked: { Qt.openUrlExternally(root.pluginRepoUrl); root.close() }
            }

            // Releases: same target as the Help "Changelog" resource
            // (config.links.releases). Help screen only.
            Button {
              visible: root.view === "help"
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Releases"
              iconText: "󰓹"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: { Qt.openUrlExternally(root.pluginLinks.releases); root.close() }
            }

            Button {
              id: refreshButton

              visible: root.view !== "help" && root.view !== "setup"
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Refresh"
              iconText: "󰑓"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }

            Button {
              visible: root.view === "wallpapers" || root.view === "help"
                || root.view === "setup"
              // Frozen while an action runs, like the preview's actions.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Back"
              iconText: "󰁍"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.view === "help"
                ? root.closeHelp()
                : (root.view === "setup" ? root.closeSetup() : root.goBack())
            }

            Button {
              // Frozen while an action runs, like the preview's actions.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Close"
              iconText: "✕"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.close()
            }
          }
        }

        PanelHero {
          id: hero

          visible: root.view !== "preview"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.heroHeight
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: heroIcon
          trailingControl: heroActions
          title: (root.view === "help"
            ? "Guide & support"
            : (root.view === "setup"
              ? "Setup & options"
              : (root.view === "themes"
                ? "Theme selection"
                : ("Theme / " + Model.ucfirst(root.themeName))))).toUpperCase()
          detail: ""
          meta: root.view === "help"
            ? root.versionedName
            : (root.view === "setup"
              ? root.versionedName
              : (root.view === "themes"
                ? root.versionedName
                : "browse and manage wallpapers"))
        }

        PanelSeparator {
          id: heroRule
          visible: root.view !== "preview"
          anchors.top: hero.bottom
          anchors.topMargin: Style.space(14)
          // Full card width: cancel the content padding so the rule reaches the
          // border on both sides.
          anchors.left: parent.left
          anchors.leftMargin: -card.leftPadding
          width: card.width - card.borderLeft - card.borderRight
          foreground: root.foreground
        }

        // ---- themes view (master-detail) ------------------------------------
        // Left: vertical list of themes. Right: large preview with the theme
        // palette, description and bulk actions. One `selectedIndex` drives the
        // list highlight and the detail pane for mouse and keyboard alike.
        Item {
          id: themesView

          visible: root.view === "themes"
          anchors.top: heroRule.bottom
          anchors.left: parent.left
          // Full-bleed on the right: cancel the content padding so the detail
          // image touches the border (the master list keeps its own margins).
          anchors.right: parent.right
          anchors.rightMargin: -card.rightPadding
          anchors.bottom: footer.top

          Row {
            id: themesRow

            anchors.fill: parent
            spacing: 0

            // ---- master: theme list
            Item {
              id: themeListPane

              width: Math.max(Style.space(210),
                Math.floor((themesRow.width - themesRow.spacing) * 0.26))
              height: parent.height

              SearchField {
                id: searchBar

                anchors.top: parent.top
                anchors.topMargin: Style.space(12)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.contentMargin
                text: root.filterText
                placeholder: "Search themes…"
                active: root.searching
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onActivated: root.startSearch()
                onCleared: root.setThemeFilter("")
              }

              ListView {
                id: themesList

                anchors.top: searchBar.bottom
                anchors.topMargin: Style.space(10)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.contentMargin
                anchors.bottom: addSource.top
                anchors.bottomMargin: root.contentSpacing
                clip: true
                spacing: Style.space(4)
                model: root.activeThemesModel

                delegate: Item {
                  id: themeRow
                  required property int index
                  required property var model

                  // Mouse hover only lights the plate up; it never moves the
                  // current theme. Clicking confirms the selection.
                  property bool hovered: false

                  width: themesList.width
                  height: root.themeRowHeight

                  // Dark row plate, slightly lifted off the card, as in the
                  // mockup. The CursorSurface paints the cursor/selected fill on
                  // top of it.
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    // Hover lightens the plate only; the CursorSurface still
                    // paints the actual cursor/selected fill on top.
                    color: themeRow.hovered
                      ? Style.hoverFillFor(root.foreground, root.accent)
                      : Util.alpha(root.foreground, 0.05)
                  }

                  CursorSurface {
                    id: themeRowCard

                    anchors.fill: parent
                    foreground: root.foreground
                    accent: root.accent
                    hasCursor: root.cursorActive && root.view === "themes"
                      && root.selectedIndex === themeRow.index

                    RoundedImage {
                      id: themeRowThumb

                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(72)
                      height: Style.space(48)
                      inset: Style.space(2)
                      source: themeRow.model.preview
                    }

                    Column {
                      anchors.left: themeRowThumb.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: themeDot.left
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: Model.themeLabel(themeRow.model)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                        font.letterSpacing: 1.2
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: Model.themeStatusLabel(themeRow.model)
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                    }

                    Rectangle {
                      id: themeDot

                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(9)
                      height: width
                      radius: width / 2
                      color: {
                        if (root.busy && root.actionTheme === themeRow.model.name)
                          return root.statusInstalling
                        var state = Model.themeState(themeRow.model)
                        if (state === "installed") return root.statusInstalled
                        if (state === "partial") return root.statusInstalling
                        return Util.alpha(root.foreground, 0.25)
                      }
                    }

                    // Accent ring on the selected row: same treatment as the
                    // wallpaper tiles (the kit's cursor border reads faint).
                    BorderSurface {
                      anchors.fill: parent
                      color: "transparent"
                      radius: Style.cornerRadius
                      borderSpec: themeRowCard.hasCursor
                        ? Border.flat(root.accent, Style.space(2))
                        : Border.none()
                    }

                    HoverHandler {
                      cursorShape: Qt.PointingHandCursor
                      onHoveredChanged: themeRow.hovered = hovered
                    }

                    // Click confirms the current theme; hover only lights the
                    // row up. Double click enters the wallpaper grid, same as
                    // Enter/Space or the detail "Browse" button.
                    TapHandler {
                      onTapped: root.takeCursor(themeRow.index)
                      onDoubleTapped: {
                        root.takeCursor(themeRow.index)
                        root.selectTheme(themeRow.index)
                      }
                    }
                  }
                }
              }

              Text {
                anchors.top: searchBar.bottom
                anchors.topMargin: Style.space(24)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.contentMargin
                visible: root.filterText !== "" && root.activeThemesModel.count === 0
                textFormat: Text.PlainText
                text: "No matches for “" + root.filterText + "”"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }

              // Placeholder for multiple remote sources; wired when the script
              // learns to manage more than the single configured repo.
              Item {
                id: addSource

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.contentMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(24)
                height: root.actionButtonHeight

                // Dotted rounded outline (Rectangle borders cannot dash).
                Shape {
                  id: addSourceOutline
                  anchors.fill: parent

                  readonly property real r: Math.max(0, Style.cornerRadius)
                  readonly property real w: width - addSourceOutlinePath.strokeWidth
                  readonly property real h: height - addSourceOutlinePath.strokeWidth
                  readonly property real inset: addSourceOutlinePath.strokeWidth / 2

                  ShapePath {
                    id: addSourceOutlinePath
                    strokeColor: root.dim
                    strokeWidth: 1
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [3, 3]
                    capStyle: ShapePath.FlatCap

                    startX: addSourceOutline.inset + addSourceOutline.r
                    startY: addSourceOutline.inset
                    PathLine {
                      x: addSourceOutline.inset + addSourceOutline.w - addSourceOutline.r
                      y: addSourceOutline.inset
                    }
                    PathArc {
                      x: addSourceOutline.inset + addSourceOutline.w
                      y: addSourceOutline.inset + addSourceOutline.r
                      radiusX: addSourceOutline.r
                      radiusY: addSourceOutline.r
                    }
                    PathLine {
                      x: addSourceOutline.inset + addSourceOutline.w
                      y: addSourceOutline.inset + addSourceOutline.h - addSourceOutline.r
                    }
                    PathArc {
                      x: addSourceOutline.inset + addSourceOutline.w - addSourceOutline.r
                      y: addSourceOutline.inset + addSourceOutline.h
                      radiusX: addSourceOutline.r
                      radiusY: addSourceOutline.r
                    }
                    PathLine {
                      x: addSourceOutline.inset + addSourceOutline.r
                      y: addSourceOutline.inset + addSourceOutline.h
                    }
                    PathArc {
                      x: addSourceOutline.inset
                      y: addSourceOutline.inset + addSourceOutline.h - addSourceOutline.r
                      radiusX: addSourceOutline.r
                      radiusY: addSourceOutline.r
                    }
                    PathLine {
                      x: addSourceOutline.inset
                      y: addSourceOutline.inset + addSourceOutline.r
                    }
                    PathArc {
                      x: addSourceOutline.inset + addSourceOutline.r
                      y: addSourceOutline.inset
                      radiusX: addSourceOutline.r
                      radiusY: addSourceOutline.r
                    }
                  }
                }

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.addSourceSoon ? "COMING SOON (◕‿◕)" : "+ Add remote source"
                  color: root.addSourceSoon ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                  onTapped: root.triggerAddSource()
                }

                Timer {
                  id: addSourceReset
                  interval: 3000
                  onTriggered: root.addSourceSoon = false
                }
              }

              // Right rule of the master column, with the content padded off it.
              Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 1
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              }
            }

              // ---- detail: preview + palette + actions
            Item {
              id: themeDetail

              width: themesRow.width - themeListPane.width - themesRow.spacing
              height: parent.height
              clip: true

              // Double click on the large preview opens the theme's wallpapers,
              // exactly like the "Browse" button.
              TapHandler {
                onDoubleTapped: root.selectTheme(root.selectedIndex)
              }

              // Full-bleed preview: no radius, no padding, the whole cell is
              // the image (the cell edges are the section rules). Two layers:
              // the backdrop keeps the previous frame visible while the front
              // one decodes, so moving through themes never flashes black.
              Image {
                id: detailImageBack

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                source: root.detailBackdrop
                sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)),
                  Math.max(1, Math.ceil(height * 2)))
              }

              Image {
                id: detailImage

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // Cached local file once resolved (small remote `preview` only
                // on the first paint). `sourceSize` caps the decode to ~2× the
                // pane, so the pixmap cache is not evicted by a full 2K frame.
                source: root.detailImageShown
                sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)),
                  Math.max(1, Math.ceil(height * 2)))
                onStatusChanged: if (status === Image.Ready && source !== "")
                  root.detailBackdrop = source
              }

              // Dark gradient so the palette, name and description stay legible
              // over the wallpaper.
              Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Util.alpha(root.background, 0.0) }
                  GradientStop { position: 0.45; color: Util.alpha(root.background, 0.3) }
                  GradientStop { position: 0.75; color: Util.alpha(root.background, 0.85) }
                  GradientStop { position: 1.0; color: root.background }
                }
              }

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.space(22)
                anchors.rightMargin: Style.space(22)
                anchors.bottomMargin: Style.space(24)
                spacing: Style.space(22)

                // Exact ink boxes: `TextMetrics.tightBoundingRect` gives the real
                // glyph extents, so each block is trimmed to what is actually
                // drawn. Every gap in the column is then exactly `spacing` — a
                // flex `space-y`, independent of font bearings.
                FontMetrics { id: titleMetrics; font: titleText.font }
                FontMetrics { id: bodyMetrics; font: descriptionText.font }
                TextMetrics { id: titleInk; font: titleText.font; text: titleText.text }
                TextMetrics { id: descInk; font: descriptionText.font; text: descriptionText.text }

                Row {
                  id: paletteRow
                  spacing: Style.space(6)
                  // No palette in the dataset -> no swatches and no gap.
                  visible: paletteRepeater.count > 0

                  Repeater {
                    id: paletteRepeater
                    model: Model.paletteList(root.selectedTheme)

                    delegate: Rectangle {
                      width: Style.space(26)
                      height: width
                      radius: Math.max(2, Style.cornerRadius - Style.space(2))
                      color: modelData
                      // subtle outline so the theme's dark neutrals (background,
                      // muted) stay visible on the wallpaper/scrim.
                      border.width: Math.max(1, Style.normalBorderWidth)
                      border.color: Util.alpha(root.foreground, 0.25)
                    }
                  }
                }

                Item {
                  id: titleBlock
                  width: parent.width
                  height: titleInk.tightBoundingRect.height

                  Text {
                    id: titleText
                    width: parent.width
                    // pull the line box up so the ink top sits at the block top
                    y: -(titleMetrics.ascent + titleInk.tightBoundingRect.y)
                    textFormat: Text.PlainText
                    text: Model.themeLabel(root.selectedTheme)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                    font.bold: true
                    elide: Text.ElideRight
                    lineHeightMode: Text.FixedHeight
                    lineHeight: titleMetrics.ascent + titleMetrics.descent
                  }
                }

                Item {
                  id: descriptionBlock

                  width: parent.width
                  // Internal line pitch stays comfortable (1.4×); the block is
                  // trimmed to the real ink, so the outer half-leading is gone.
                  readonly property real lineBox: Math.round(Style.font.body * 1.4)
                  readonly property real leading: lineBox - (bodyMetrics.ascent + bodyMetrics.descent)
                  readonly property real lineCount: descriptionText.lineCount
                  height: Math.max(0, (lineCount - 1) * lineBox + descInk.tightBoundingRect.height)

                  Text {
                    id: descriptionText

                    // pull the line box up so the first line's ink top sits at
                    // the block top
                    y: -(bodyMetrics.ascent + descriptionBlock.leading / 2
                      + descInk.tightBoundingRect.y)
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      var theme = root.selectedTheme
                      if (!theme) return ""
                      var bits = []
                      if (theme.description) bits.push(theme.description)
                      bits.push(theme.collections
                        + (theme.collections === 1 ? " collection" : " collections"))
                      bits.push(theme.count
                        + (theme.count === 1 ? " wallpaper" : " wallpapers"))
                      bits.push(theme.installed + " installed locally")
                      return bits.join(" · ")
                    }
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    lineHeightMode: Text.FixedHeight
                    lineHeight: descriptionBlock.lineBox
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }
                }

                Item {
                  width: parent.width
                  height: detailActions.height

                  Row {
                    id: detailActions
                    anchors.left: parent.left
                    anchors.top: parent.top
                    spacing: Style.spacing.controlGap

                    Button {
                      text: "Browse " + (root.selectedTheme ? root.selectedTheme.count : "")
                      iconText: "󰉖"
                      height: root.actionButtonHeight
                      bordered: false
                      background: Util.alpha(root.foreground, 0.12)
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: root.selectTheme(root.selectedIndex)
                    }

                    Button {
                      visible: root.selectedThemePresent
                      enabled: !root.actionRunning && !root.selectedThemeFull
                        && !root.storageLimitReached
                      opacity: enabled ? 1 : 0.4
                      text: "Install (ALL)"
                      iconText: "󰮏"
                      height: root.actionButtonHeight
                      bordered: true
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: root.actionInstallTheme()
                    }

                    Button {
                      visible: root.selectedThemePresent
                      enabled: !root.actionRunning && !root.selectedThemeFull
                        && !root.storageLimitReached
                      opacity: enabled ? 1 : 0.4
                      text: "Shuffle (" + setupSettings.shuffleCount + ")"
                      iconText: "󰮏"
                      height: root.actionButtonHeight
                      bordered: true
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: root.actionRandomInstall()
                    }

                    Button {
                      visible: root.selectedThemePresent
                      enabled: !root.actionRunning && !root.selectedThemeEmpty
                      opacity: enabled ? 1 : 0.4
                      text: "Uninstall"
                      iconText: "󰱢"
                      height: root.actionButtonHeight
                      bordered: true
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: root.actionRemoveThemeAll()
                    }

                    // Custom Install placeholder for the current theme, always
                    // clickable (also while an operation runs): for now it only
                    // flashes COMING SOON.
                    Button {
                      text: root.setupSoon ? "COMING SOON (◕‿◕)" : "Custom Install"
                      iconText: "󰒓"
                      height: root.actionButtonHeight
                      bordered: true
                      foreground: root.setupSoon ? root.accent : root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onClicked: root.triggerSetup()
                    }

                    // The Omarchy theme is not installed: installing its
                    // wallpapers is impossible, so show a non-interactive
                    // info badge (no hover, no tooltip, no action).
                    BorderSurface {
                      visible: !root.selectedThemePresent
                      width: badgeRow.implicitWidth + leftPadding + rightPadding
                      height: root.actionButtonHeight
                      radius: Style.cornerRadius
                      color: "transparent"
                      borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                      leftPadding: Style.spacing.controlPaddingX
                      rightPadding: Style.spacing.controlPaddingX

                      Row {
                        id: badgeRow
                        anchors.centerIn: parent
                        spacing: Style.spacing.controlGap

                        Text {
                          textFormat: Text.PlainText
                          text: "󰀪"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.icon
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: "Theme not found"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Running overlay: covers the whole themes body (sidebar + detail) so
          // a running bulk install/remove freezes navigation; only Esc cancels.
          RunningOverlay {
            anchors.fill: parent
            z: 6
            running: root.actionRunning
            label: root.actionLabel
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
          }
        }

        // ---- help view ------------------------------------------------------
        // Index + resources on the left, the selected topic in the centre and
        // the roadmap on the right. Data lives under `help/` (index.json,
        // roadmap.json, one Markdown file per topic). Esc / Back go back to the
        // themes list.
        HelpView {
          id: helpView

          visible: root.view === "help"
          anchors.top: heroRule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          helpRoot: root.helpRoot
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
          sidebarWidth: themeListPane.width
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
          // A link opens a normal browser window under the overlay: hide the
          // panel so the page is visible.
          onLinkOpened: root.close()
        }

        // ---- setup view -----------------------------------------------------
        // Settings screen, reachable with `s` on any screen or from the setup
        // buttons: sections sidebar on the left (same width as the Help/themes
        // sidebars), the selected section on the right.
        Item {
          id: setupView

          visible: root.view === "setup"
          anchors.top: heroRule.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top

          SetupView {
            id: setupSettings

            anchors.fill: parent
            settingsPath: root.settingsPath
            settingsDir: root.settingsDir
            localFileCount: root.localFileCount
            localBytes: root.localBytes
            rotateBusy: rotationProc.running
            roadmap: root.roadmapData
            featureLabel: root.helpIndex && root.helpIndex.feature
              ? root.helpIndex.feature.title : ""
            sidebarWidth: themeListPane.width
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
          }
        }

        // ---- wallpapers view: search + grid ---------------------------------
        Item {
          id: wallpapersSearchRow

          visible: root.view === "wallpapers"
          anchors.top: heroRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(wallpapersSearch.height, selectionActions.implicitHeight,
            collectionDropdown.height)

          // Collection picker: narrows the grid to one collection of the open
          // theme, "All collections" by default.
          Dropdown {
            id: collectionDropdown

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // Same width as a grid tile below, so the picker lines up with the
            // first column.
            width: Math.max(Style.space(120), grid.cellWidth - root.tileGap * 2)
            options: root.collectionOptions
            value: root.collectionFilter
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            onChanged: function(v) { root.setCollectionFilter(v) }
          }

          // Selection helpers: no-op until multi-select lands.
          Row {
            id: selectionActions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            Button {
              text: "Select all"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.selectAllWallpapers()
            }

            Button {
              text: "Clear"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.clearWallpaperSelection()
            }
          }

          SearchField {
            id: wallpapersSearch

            anchors.left: collectionDropdown.right
            anchors.leftMargin: Style.space(12)
            anchors.right: selectionActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.wallpaperFilterText
            placeholder: "Search wallpapers…"
            active: root.searching
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.startSearch()
            onCleared: root.setWallpaperFilter("")
          }
        }

        // Rule between the search row and the grid. Same `contentSpacing` above
        // and below, so the search field sits centered between the hero rule and
        // this one.
        PanelSeparator {
          id: wallpapersSearchRule

          visible: root.view === "wallpapers"
          anchors.top: wallpapersSearchRow.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.leftMargin: -card.leftPadding
          width: card.width - card.borderLeft - card.borderRight
          foreground: root.foreground
        }

        GridView {
          id: grid

          visible: root.view === "wallpapers"
          anchors.top: wallpapersSearchRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          // Cancel the outer `tileGap` so the first and last tiles line up with
          // the content edges of the rows above instead of sitting slightly
          // inside them.
          anchors.leftMargin: -root.tileGap
          anchors.rightMargin: -root.tileGap
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing
          model: root.activeWallpapersModel
          clip: true

          // Grid adapts to the card width: as many columns as fit while keeping
          // each tile at least ~190px wide (five columns on a regular screen).
          // Column count comes from the parent width so the negative margins
          // above cannot add a column.
          readonly property int columnsHint: Math.max(2, Math.floor(parent.width / root.minTileWidth))
          readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
          cellWidth: Math.floor(width / columnsHint)
          // Thumbnail is 16:9 and fills the card; code + name overlay it, so no
          // extra strip is added and no space is wasted.
          cellHeight: Math.floor((cellWidth - root.tileGap * 2 - root.tileInset * 2) * 9 / 16)
            + root.tileInset * 2 + root.tileGap * 2

          delegate: Item {
            id: tile
            required property int index
            required property var model

            width: grid.cellWidth
            height: grid.cellHeight

            CursorSurface {
              id: tileCard

              anchors.fill: parent
              anchors.margins: root.tileGap
              foreground: root.foreground
              accent: root.accent
              bordered: true
              hasCursor: root.cursorActive && root.view === "wallpapers" && root.selectedIndex === tile.index
              // Persistent state: this is the open theme's default background
              // (live for the running theme, remembered otherwise).
              current: root.isThemeDefault(tile.model)

              RoundedImage {
                id: preview
                anchors.fill: parent
                anchors.margins: root.tileInset
                inset: root.tileInset
                // Local file when already installed (instant), reduced remote
                // preview otherwise; fall back to the full-res URL if a preview
                // is missing. GridView only creates visible delegates, so
                // nearby tiles load lazily as you scroll.
                source: String(tile.model.installed) === "1"
                  ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + tile.model.filename)
                  : (tile.model.preview !== "" ? tile.model.preview : tile.model.url)
              }

              // Overlay label: translucent band at the bottom of the image so the
              // code + name stay readable without stealing a row from the grid.
              Rectangle {
                id: labelBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.tileInset
                height: tileLabels.implicitHeight + Style.space(10)
                color: Util.alpha(root.background, 0.7)
                bottomLeftRadius: Math.max(0, Style.cornerRadius - root.tileInset)
                bottomRightRadius: Math.max(0, Style.cornerRadius - root.tileInset)

                Row {
                  id: tileLabels
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(6)

                  Text {
                    id: tileCode
                    textFormat: Text.PlainText
                    text: tile.model.code
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    // Datasets mix cases (country names vs lowercase captions):
                    // title-case each word so the grid reads consistently.
                    text: Model.titleCase(tile.model.name)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: Math.max(0, tileLabels.width - tileCode.width - tileLabels.spacing)
                  }
                }
              }

              // Installed disc, top-right of the thumbnail: same state as the
              // preview's, scaled down with the tile (accent when on disk, dim
              // otherwise).
              Rectangle {
                readonly property int disc: Math.round(Math.max(Style.space(9),
                  Math.min(Style.space(16), preview.width * 0.075)))
                readonly property int ring: Math.round(disc * 0.22)

                anchors.top: parent.top
                anchors.topMargin: root.tileInset + Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: root.tileInset + Style.space(8)
                width: disc
                height: disc
                radius: disc / 2
                color: Util.alpha(root.background, 0.55)

                Rectangle {
                  x: parent.ring
                  y: parent.ring
                  width: parent.disc - parent.ring * 2
                  height: width
                  radius: width / 2
                  color: String(tile.model.installed) === "1"
                    ? root.statusInstalled
                    : Util.alpha(root.foreground, 0.4)
                }
              }

              // Selection checkbox, top-left of the thumbnail (the installed
              // disc is top-right, the DEFAULT pill centered). Shown on the
              // cursor tile so the mouse can reach it, and kept visible while
              // checked. Clicking it toggles the check (see the tile TapHandler);
              // Space does the same from the keyboard.
              Item {
                id: checkbox

                readonly property bool checked: root.isWallpaperChecked(tile.model.filename)

                visible: checked || tileCard.hasCursor
                anchors.top: parent.top
                anchors.topMargin: root.tileInset + Style.space(8)
                anchors.left: parent.left
                anchors.leftMargin: root.tileInset + Style.space(8)
                width: Math.round(Math.max(Style.space(18),
                  Math.min(Style.space(26), preview.width * 0.09)))
                height: width

                Rectangle {
                  anchors.fill: parent
                  radius: Math.max(2, Style.space(5))
                  color: checkbox.checked
                    ? root.accent
                    : Util.alpha("#000000", 0.55)
                  border.width: Math.max(1, Style.normalBorderWidth)
                  border.color: checkbox.checked
                    ? root.accent
                    : Util.alpha(root.foreground, 0.75)

                  Text {
                    anchors.centerIn: parent
                    visible: checkbox.checked
                    text: "✓"
                    color: root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }
              }

              // "DEFAULT" pill, centered on the thumbnail, on the theme's
              // default wallpaper (dark fill so the accent reads on any image).
              // The corners stay free for the selection checkbox.
              Pill {
                visible: root.isThemeDefault(tile.model)
                anchors.centerIn: parent
                width: implicitWidth
                height: implicitHeight
                label: "DEFAULT"
                glyph: "✓"
                tint: root.accent
                fill: Util.alpha("#000000", 0.65)
                fontFamily: root.fontFamily
                hPadding: Style.space(12)
                vPadding: Style.space(6)
              }

              // Accent ring on the active tile. The kit's hover-cursor border is
              // theme-tuned and reads poorly on a busy thumbnail, so selection
              // follows the shell's own image-picker treatment (accent border at
              // full opacity, slightly thicker) instead of the faint menu state.
              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: tileCard.hasCursor
                  ? Border.flat(root.accent, Style.space(2))
                  : Border.none()
              }

              HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered && root.hoverArmed) root.takeCursor(tile.index)
              }

              // A click opens the fullscreen preview, exactly like Enter: the
              // tile is a doorway, not a toggle. "Set default" therefore lives
              // in the preview (double click on the image), because a single
              // click here already switches view and no second tap can land.
              // A click that lands on the checkbox toggles the check instead.
              TapHandler {
                onTapped: function(eventPoint) {
                  var p = eventPoint.position
                  if (checkbox.visible
                      && p.x >= checkbox.x && p.x <= checkbox.x + checkbox.width
                      && p.y >= checkbox.y && p.y <= checkbox.y + checkbox.height) {
                    root.toggleWallpaperCheck(tile.model.filename)
                    return
                  }
                  root.takeCursor(tile.index)
                  root.showPreview()
                }
              }
            }
          }
        }

        // ---- footer: actions + status ---------------------------------------
        // No footer bar: a separator, borderless controls on the flat surface
        // and a dim caption for status, as in the first-party panels.
        Column {
          id: footer

          // Kept above `previewView` (z: 10) so its controls stay clickable on
          // the fullscreen preview.
          visible: true
          z: 11
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: -root.footerOverlap
          spacing: root.footerSpacing

          // Wrapped so the rule can bleed past the footer's own padding to the
          // card edges (a Column would force its x back to 0).
          Item {
            width: parent.width
            height: 1

            PanelSeparator {
              x: -card.leftPadding
              width: card.width - card.borderLeft - card.borderRight
              foreground: root.foreground
            }
          }

          // Themes footer: installed/available summary on the left, progress of
          // the selected theme in the middle, key hints on the right.
          Item {
            id: themesFooterRow

            visible: root.view === "themes"
            width: parent.width
            height: Math.max(setupButton.implicitHeight,
              themesSummary.implicitHeight, themeProgress.implicitHeight,
              themesHints.implicitHeight)

            // Settings: setup of the plugin. Placeholder for now (no action),
            // but it also gives the themes footer the same height as the other
            // two, which carry buttons.
            Button {
              id: setupButton

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              // Frozen (and dimmed) while an action runs, like the rest of the
              // footer controls.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Setup"
              iconText: "󰒓"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.openSetup()
            }

            // Installed/available summary, right-aligned against the sidebar
            // rule so it lines up with the detail zone's content.
            Row {
              id: themesSummary

              anchors.right: themesSidebarRule.left
              anchors.rightMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: width / 2
                color: root.statusInstalled
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.themeCounts.installed + " installed · "
                  + root.themeCounts.available + " available"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ThemeProgress {
              id: themeProgress

              // Aligned with the detail buttons above and stretched across the
              // whole detail zone, up to the key-hints divider.
              anchors.left: parent.left
              anchors.leftMargin: themeListPane.width + Style.space(22)
              anchors.right: hintsRule.left
              anchors.rightMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter

              theme: root.progressTheme
              busy: root.actionRunning
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
            }

            Text {
              id: themesHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
              text: actionRunning
                ? root.keyHint("esc", "stop")
                : root.keyHint("enter", "browse")
                  + "&nbsp;&nbsp;" + root.keyHint("i", "install")
                  + "&nbsp;&nbsp;" + root.keyHint("/", "search")
                  + "&nbsp;&nbsp;" + root.keyHint("esc", "close")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Vertical rules, as in the original mockup: the first continues
            // the master list's right border into the footer, the second
            // separates the progress from the key hints.
            Rectangle {
              id: themesSidebarRule

              anchors.top: parent.top
              anchors.bottom: parent.bottom
              x: themeListPane.width - 1
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }

            Rectangle {
              id: hintsRule

              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: themesHints.left
              anchors.rightMargin: Style.space(20)
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }
          }

          // Wallpapers footer mirrors the themes one: three sections on a single
          // row — Install/Uninstall on the left, the open theme's progress in the
          // middle, the key hints on the right.
          Item {
            id: actionRow
            visible: root.view === "wallpapers"
            width: parent.width
            height: Math.max(primaryActions.implicitHeight,
              wallpapersProgress.implicitHeight, wallpapersHints.implicitHeight)

            Row {
              id: primaryActions
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              // Help, before the actions (the wallpapers header carries none).
              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Help"
                iconText: "󰘥"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.openHelp()
              }

              Button {
                // A batch install is bulk: disabled while a storage cap is
                // reached (one wallpaper at a time stays available).
                enabled: !actionRunning && !(root.storageLimitReached && root.checkedCount > 1)
                opacity: enabled ? 1 : 0.4
                text: "Install"
                iconText: "󰮏"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionInstall()
              }

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Uninstall"
                iconText: "󰩺"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionRemove()
              }
            }

            // First rule: same x as the themes screen's master/detail divider,
            // so the Install/Uninstall section spans the sidebar's width.
            Rectangle {
              id: wallpapersSidebarRule

              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              x: themeListPane.width - 1
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            ThemeProgress {
              id: wallpapersProgress

              anchors.left: wallpapersSidebarRule.right
              anchors.leftMargin: Style.space(22)
              anchors.right: wallpapersBulkRule.left
              anchors.rightMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              theme: root.progressTheme
              busy: root.actionRunning
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
            }

            // Second rule, between the progress and the key hints.
            Rectangle {
              id: wallpapersBulkRule

              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: wallpapersHints.left
              anchors.rightMargin: Style.space(20)
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Text {
              id: wallpapersHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
              text: root.actionRunning
                ? root.keyHint("esc", "stop")
                : root.keyHint("enter", "browse")
                  + "&nbsp;&nbsp;" + root.keyHint("space", "select")
                  + "&nbsp;&nbsp;" + root.keyHint("i", "install")
                  + "&nbsp;&nbsp;" + root.keyHint("/", "search")
                  + "&nbsp;&nbsp;" + root.keyHint("esc", "back")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Preview footer: Install / Download original on the left, the open
          // theme's progress in the middle, the key hints on the right.
          Item {
            id: previewFooterRow

            visible: root.view === "preview"
            width: parent.width
            height: Math.max(previewPrimaryActions.implicitHeight,
              previewProgress.implicitHeight, previewHints.implicitHeight)

            Row {
              id: previewPrimaryActions

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              // Help, before the actions (the big preview's only Help button:
              // the header carries none).
              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Help"
                iconText: "󰘥"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.openHelp()
              }

              Button {
                id: previewInstall

                enabled: !actionRunning && !root.currentInstalled
                opacity: enabled ? 1 : 0.4
                text: "Install"
                iconText: "󰮏"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionInstall()
              }

              // Same label and theme-red tint as the themes screen's Uninstall;
              // `Color.urgent` is the theme's red (color1), not a fixed danger.
              // The border is forced to urgent too (the kit's normal border
              // would use `foreground` at a low alpha).
              Button {
                text: "Uninstall"
                iconText: "󰩺"
                enabled: !actionRunning && root.currentInstalled
                opacity: enabled ? 1 : 0.4
                bordered: true
                foreground: root.urgent
                accent: root.urgent
                borderSpec: Border.flat(root.urgent, Math.max(1, Style.normalBorderWidth))
                fontFamily: root.fontFamily
                onClicked: root.actionRemove()
              }
            }

            ThemeProgress {
              id: previewProgress

              anchors.left: previewSidebarRule.right
              anchors.leftMargin: Style.space(22)
              anchors.right: previewHints.left
              anchors.rightMargin: Style.space(34)
              anchors.verticalCenter: parent.verticalCenter
              theme: root.progressTheme
              busy: root.actionRunning
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
            }

            // First rule: same x as the themes screen's master/detail divider,
            // so the Install/Uninstall section spans the sidebar's width.
            Rectangle {
              id: previewSidebarRule

              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              x: themeListPane.width - 1
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Rectangle {
              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: previewProgress.right
              anchors.leftMargin: Style.space(14)
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Text {
              id: previewHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
              text: root.keyHint("enter", "install")
                + "&nbsp;&nbsp;" + root.keyHint("d", "default")
                + "&nbsp;&nbsp;" + root.keyHint("u", "uninstall")
                + "&nbsp;&nbsp;" + root.keyHint("esc", "back")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Help footer: Setup placeholder plus a direct link to the version
          // dataset, then the same master/detail divider as the other screens.
          Item {
            id: helpFooterRow

            visible: root.view === "help"
            width: parent.width
            height: Math.max(helpFooterActions.implicitHeight,
              helpHints.implicitHeight)

            Row {
              id: helpFooterActions

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              // Same placeholder button as the themes footer, so the help footer
              // keeps the same height as the other screens.
              Button {
                id: helpFooterButton

                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Setup"
                iconText: "󰒓"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.openSetup()
              }

              // Direct link to the version dataset (derived from `base`).
              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Archive RAW"
                iconText: "󰆼"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: helpView.openDatabase()
              }

              // Star the project on GitHub. There is no direct "star" URL, so
              // this opens the repo (URL from config.links).
              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Star"
                iconText: "󰓎"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  Qt.openUrlExternally(root.pluginRepoUrl)
                  root.close()
                }
              }
            }

            // The master/detail divider used by every other footer, continuing
            // the Help sidebar border.
            Rectangle {
              id: helpSidebarRule

              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              x: themeListPane.width - 1
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Text {
              id: helpHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              text: root.keyHint("enter", "open")
                + "&nbsp;&nbsp;" + root.keyHint("arrows", "move")
                + "&nbsp;&nbsp;" + root.keyHint("pgup/pgdn", "scroll")
                + "&nbsp;&nbsp;" + root.keyHint("p", "propose")
                + "&nbsp;&nbsp;" + root.keyHint("d", "database")
                + "&nbsp;&nbsp;" + root.keyHint("esc", "back")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Setup footer: the Help/links group on the left and the keyboard
          // hints on the right, mirroring the Help footer. "Restore defaults"
          // lives in the right (SECTIONS) sidebar and the auto-save flash in the
          // section content.
          Item {
            id: setupFooterRow

            visible: root.view === "setup"
            width: parent.width
            height: Math.max(setupFooterLeft.implicitHeight,
              setupHints.implicitHeight)

            // Same left group as the Help footer, with Help in place of Setup.
            Row {
              id: setupFooterLeft

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Help "
                iconText: "󰘥"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.openHelp()
              }

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Archive RAW"
                iconText: "󰆼"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: helpView.openDatabase()
              }

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Star"
                iconText: "󰓎"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  Qt.openUrlExternally(root.pluginRepoUrl)
                  root.close()
                }
              }
            }

            // The master/detail divider used by every other footer, continuing
            // the sidebar border.
            Rectangle {
              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              x: themeListPane.width - 1
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Text {
              id: setupHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              text: setupSettings.dropdownOpen
                ? root.keyHint("arrows", "move")
                  + "&nbsp;&nbsp;" + root.keyHint("enter", "select")
                  + "&nbsp;&nbsp;" + root.keyHint("esc", "close")
                : setupSettings.editing
                  ? root.keyHint("arrows", "change")
                    + "&nbsp;&nbsp;" + root.keyHint("enter", "confirm")
                    + "&nbsp;&nbsp;" + root.keyHint("esc", "cancel")
                  : root.keyHint("enter", "open")
                  + "&nbsp;&nbsp;" + root.keyHint("arrows", "move")
                  + "&nbsp;&nbsp;" + root.keyHint("d", "defaults")
                  + "&nbsp;&nbsp;" + root.keyHint("?", "help")
                  + "&nbsp;&nbsp;" + root.keyHint("q", "close")
                  + "&nbsp;&nbsp;" + root.keyHint("esc", "back")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

        }

        // ---- fullscreen preview ---------------------------------------------
        Item {
          id: previewView

          visible: root.view === "preview"
          anchors.fill: parent
          z: 10

          // last source that failed to load, so the hero meta can report it
          property string failedSource: ""

          // target wallpaper, preloaded in background while the current one
          // stays up. Remote images come from the disk cache once resolved, so
          // stepping through the preview no longer re-downloads the 2K original.
          readonly property string nextSource: {
            var item = root.currentItem()
            if (!item) return ""
            if (String(item.installed) === "1")
              return Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + item.filename)
            var cached = root.cachedImagePath(item.url)
            if (cached !== "") return Util.fileUrl(cached)
            return item.url
          }

          // true only when the visible image is the one of the selected item,
          // so the title never pairs a name with the previous resolution
          readonly property bool shown: previewImage.status === Image.Ready
            && String(previewImage.source) === String(nextSource)

          readonly property bool failed: failedSource !== ""
            && String(failedSource) === String(nextSource)

          // true when an event point falls inside the full-bleed image frame;
          // used to route taps (image → set default, header → back)
          function onImage(point) {
            var p = previewView.mapToItem(previewImageFrame, point.position.x, point.position.y)
            return p.x >= 0 && p.y >= 0
              && p.x <= previewImageFrame.width && p.y <= previewImageFrame.height
          }

          Component {
            id: previewIcon

            HeroLogo {
              glyph: ""
              source: root.logoPath
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          Component {
            id: previewActions

            Row {
              spacing: Style.spacing.controlGap

              Button {
                visible: root.dev
                text: "DEV"
                iconText: "\uf121"
                bordered: true
                foreground: root.accent
                accent: root.accent
                fontFamily: root.fontFamily
              }

              // Global store, same pill as the themes/wallpapers header.
              StorePill {
                controlHeight: previewDownloadButton.implicitHeight
                wallpapers: root.globalCounts.wallpapers
                installed: root.globalCounts.installed
                limitReason: root.storageLimitReached ? root.storageLimitReason : ""
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onLimitActivated: root.openSetupDownload()
              }

              // Real image info ("2K | 2560x1440 | 0.3 MB"), standard colours,
              // styled like the store pill on the themes screen.
              BorderSurface {
                id: previewInfoPill

                visible: root.currentResolution !== "" || root.currentDimensions !== ""
                  || root.currentSize !== ""
                height: previewDownloadButton.implicitHeight
                width: infoRow.implicitWidth + leftPadding + rightPadding
                radius: Style.cornerRadius
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                leftPadding: Style.spacing.controlPaddingX
                rightPadding: Style.spacing.controlPaddingX

                Row {
                  id: infoRow
                  anchors.centerIn: parent
                  spacing: Style.space(10)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    visible: root.currentResolution !== ""
                    text: root.currentResolution
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Rectangle {
                    visible: root.currentResolution !== "" && root.currentDimensions !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, Style.normalBorderWidth)
                    height: infoRow.implicitHeight
                    color: Util.alpha(root.foreground, 0.25)
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    visible: root.currentDimensions !== ""
                    text: root.currentDimensions
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Rectangle {
                    visible: root.currentSize !== ""
                      && (root.currentResolution !== "" || root.currentDimensions !== "")
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, Style.normalBorderWidth)
                    height: infoRow.implicitHeight
                    color: Util.alpha(root.foreground, 0.25)
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    visible: root.currentSize !== ""
                    text: root.currentSize
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              Button {
                id: previewDownloadButton

                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Download"
                iconText: "󰇚"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionDownloadOriginal()
              }

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Back"
                iconText: "󰁍"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.closePreview()
              }

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Close"
                iconText: "✕"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.close()
              }
            }
          }

          PanelHero {
            id: previewHero

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.heroHeight
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: previewIcon
            trailingControl: previewActions
            // "Theme / Catppuccin / Preview": the file name below already
            // identifies the wallpaper, so the title stays short.
            title: ("Theme / " + Model.ucfirst(root.themeName) + " / Preview").toUpperCase()
            // Second line: just the file name, middle-elided so the extension
            // and resolution at the end stay readable; resolution and size live
            // in the info pill on the right.
            meta: {
              var item = root.currentItem()
              if (!item) return ""
              if (previewView.failed) return "failed to load"
              return Model.elideMiddle(item.filename, root.fileNameMaxChars)
            }
          }

          PanelSeparator {
            id: previewRule
            anchors.top: previewHero.bottom
            // Same gap as `heroRule`, so the preview header reads as tall as the
            // other screens'.
            anchors.topMargin: Style.space(14)
            // Full card width, like the hero rule.
            anchors.left: parent.left
            anchors.leftMargin: -card.leftPadding
            width: card.width - card.borderLeft - card.borderRight
            foreground: root.foreground
          }

          Item {
            id: previewImageFrame

            // Attached to the rule above and the footer rule below: the image
            // fills the space between them.
            anchors.top: previewRule.bottom
            // Full-bleed but inside the border: cancel only the card padding so
            // the image touches the border's inner edge, which stays visible.
            anchors.left: parent.left
            anchors.leftMargin: -card.leftPadding
            anchors.right: parent.right
            anchors.rightMargin: -card.rightPadding
            // Footer is a sibling of `previewView`, so it cannot be an anchor
            // target: reserve its height above the bottom instead, cancelling
            // the footer's own overlap so the image stays glued to its rule.
            anchors.bottom: parent.bottom
            anchors.bottomMargin: footer.height - root.footerOverlap
            clip: true

            Image {
              id: previewImage

              anchors.fill: parent
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              opacity: status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Installed disc, top-right of the image: accent when on disk, dim
            // otherwise. Right margin matches the card padding so it lines up
            // with the header/footer controls.
            Rectangle {
              // Ring width is subtracted on all sides, so the inner dot is
              // exactly centred whatever the spacing scale rounds to.
              readonly property int disc: Math.round(Style.space(18))
              readonly property int ring: Math.round(Style.space(4))

              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              anchors.right: parent.right
              anchors.rightMargin: card.rightPadding
              width: disc
              height: disc
              radius: disc / 2
              color: Util.alpha(root.background, 0.55)

              Rectangle {
                x: parent.ring
                y: parent.ring
                width: parent.disc - parent.ring * 2
                height: width
                radius: width / 2
                color: root.currentInstalled
                  ? root.statusInstalled
                  : Util.alpha(root.foreground, 0.4)
              }
            }

            // "DEFAULT" pill, top-left over the image. Dark fill so the accent
            // text reads over any wallpaper (the plain outline alone washed out
            // on bright images).
            Pill {
              id: previewDefaultPill

              visible: root.currentIsDefault
              anchors.top: parent.top
              anchors.topMargin: Style.space(12)
              anchors.left: parent.left
              anchors.leftMargin: card.leftPadding
              width: implicitWidth
              height: implicitHeight
              label: "DEFAULT"
              glyph: "✓"
              tint: root.accent
              fill: Util.alpha("#000000", 0.65)
              fontFamily: root.fontFamily
            }

            // Destination path of the open wallpaper, bottom-left of the image.
            // Theme background fill (not pure black) with a border; vertically
            // centred with the filmstrip on the right. Shown whether or not the
            // file is installed.
            BorderSurface {
              id: previewPathPill

              anchors.left: parent.left
              anchors.leftMargin: root.overlayInset
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.overlayInset
              readonly property int padLeft: Style.space(14)
              readonly property int padRight: Style.space(32)

              width: Math.min(pathText.implicitWidth + padLeft + padRight,
                parent.width - card.leftPadding - Style.space(12))
              // Same height as the filmstrip on the right, so the two overlays
              // read as one row; the path itself stays vertically centred.
              height: previewStrip.height
              radius: Style.cornerRadius
              color: Util.alpha(root.background, root.overlayFillAlpha)
              borderSpec: Border.flat(Util.alpha(root.foreground, 0.22),
                Math.max(1, Style.normalBorderWidth))

              Text {
                id: pathText

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: parent.padLeft
                anchors.rightMargin: parent.padRight
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                // Same middle-elision as the header: the directory head and the
                // file tail stay readable at any length.
                text: Model.elideMiddle(root.currentInstallPath, root.pathMaxChars)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: -0.8
                elide: Text.ElideMiddle
              }
            }

          }

          // Running overlay: opaque scrim over the image with an accent
          // spinner and a pulsing caption while an action runs.
          RunningOverlay {
            anchors.fill: previewImageFrame
            z: 6
            running: root.actionRunning
            label: root.actionLabel
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
          }

          // Thumbnail navigator: a filmstrip of neighbouring wallpapers that
          // follows the selection (arrows / h/l) and sits bottom-right of the
          // image. Clicking a cell jumps to it.
          BorderSurface {
            id: previewStrip

            readonly property real cellW: Style.space(64)
            readonly property real cellH: Math.round(cellW * 9 / 16)
            readonly property int visibleCells: 7

            anchors.right: parent.right
            // The strip lives in the padded content area, so no lateral margin:
            // its right edge lines up with the footer controls and the grids.
            anchors.rightMargin: 0
            anchors.bottom: parent.bottom
            // Lifted so the strip's bottom edge lines up with the path pill's.
            anchors.bottomMargin: footer.height - root.footerOverlap
              + root.overlayInset
            width: visibleCells * cellW + (visibleCells - 1) * previewStripList.spacing
              + contentLeftInset + contentRightInset
            height: cellH + contentTopInset + contentBottomInset
            radius: Style.cornerRadius
            color: Util.alpha(root.background, root.overlayFillAlpha)
            borderSpec: Border.flat(Util.alpha(root.foreground, 0.18),
              Math.max(1, Style.normalBorderWidth))
            padding: Style.space(6)

            ListView {
              id: previewStripList

              anchors.fill: parent
              anchors.leftMargin: previewStrip.contentLeftInset
              anchors.rightMargin: previewStrip.contentRightInset
              anchors.topMargin: previewStrip.contentTopInset
              anchors.bottomMargin: previewStrip.contentBottomInset
              orientation: ListView.Horizontal
              spacing: Style.space(4)
              clip: true
              model: root.activeWallpapersModel
              currentIndex: root.selectedIndex
              // Scroll the strip ourselves so the current cell is centred but
              // the ends stay flush: first cell at the left edge, last at the
              // right edge, with no blank gutter.
              highlightFollowsCurrentItem: false

              readonly property real cellStep: previewStrip.cellW + spacing

              function positionStrip() {
                var maxX = Math.max(0, contentWidth - width)
                var target = currentIndex * cellStep + previewStrip.cellW / 2 - width / 2
                contentX = Math.max(0, Math.min(maxX, target))
              }

              onCurrentIndexChanged: positionStrip()
              onContentWidthChanged: positionStrip()
              onWidthChanged: positionStrip()

              Behavior on contentX {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
              }

              delegate: Item {
                id: stripCell

                required property int index
                required property var model

                width: previewStrip.cellW
                height: previewStrip.cellH

                RoundedImage {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  inset: Style.space(2)
                  source: String(stripCell.model.installed) === "1"
                    ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName
                      + "/" + stripCell.model.filename)
                    : (stripCell.model.preview !== ""
                      ? stripCell.model.preview : stripCell.model.url)
                }

                BorderSurface {
                  anchors.fill: parent
                  color: "transparent"
                  radius: Style.cornerRadius
                  borderSpec: previewStripList.currentIndex === stripCell.index
                    ? Border.flat(root.accent, Math.max(1, Style.normalBorderWidth))
                    : Border.none()
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                  onTapped: {
                    if (!root.actionRunning) root.takeCursor(stripCell.index)
                  }
                }
              }
            }
          }

          // hidden preloader: fetches the target wallpaper in the background and
          // swaps it onto the visible image only when it is fully loaded, so the
          // previous wallpaper never disappears while the next one downloads.
          Image {
            id: nextImage
            visible: false
            asynchronous: true
            cache: true
            source: previewView.nextSource
            onStatusChanged: {
              if (status === Image.Ready) {
                previewImage.source = nextImage.source
              } else if (status === Image.Error) {
                // Keep the previous wallpaper on screen — that is the point of
                // the double buffer. Clearing `previewImage.source` here left a
                // blank frame with no feedback at all; the failure is reported
                // in the hero meta line instead.
                previewView.failedSource = String(nextImage.source)
              }
            }
          }

          // No spinner: wallpapers resolve in well under 400ms here, so any
          // rotating glyph either blinked for a frame or had to be delayed into
          // uselessness. Loading feedback is the hero meta line
          // (`LOADING <file>` / `FAILED TO LOAD <file>`), which is instant.

          TapHandler {
            // One handler, two gestures, split by region so they cannot fight:
            // a tap outside the wallpaper goes back, while on the wallpaper the
            // single tap is inert (it is the first half of the double tap) and
            // the double tap sets the theme default.
            onTapped: (point, button) => {
              if (root.actionRunning) return
              if (!previewView.onImage(point)) root.closePreview()
            }
            onDoubleTapped: (point, button) => {
              if (root.actionRunning) return
              if (previewView.onImage(point)) root.actionToggleDefault()
            }
          }
        }
      }
    }
  }
}
