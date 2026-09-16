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
  readonly property bool dev: manifest !== null
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
    logo: "assets/images/logo.png"
  })

  FileView {
    id: configFile
    path: root.pluginRoot ? root.pluginRoot + "/config/config.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.pluginPaths = Model.parsePaths(text(), root.pluginPaths)
  }

  // Active Omarchy theme: `theme.name` (e.g. "osaka-jade"). Used to land the
  // cursor on the theme the user is actually running when the overlay opens.
  property string activeThemeSlug: ""
  FileView {
    id: activeThemeFile
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.activeThemeSlug = text().trim()
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

  // Plugin repository, opened by the GitHub button in the hero actions.
  readonly property string pluginRepoUrl: "https://github.com/emkcloud/omarchy-wallpapers-plugin"

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  property string view: "themes"          // "themes" | "wallpapers" | "preview"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  // Themes-screen cursor to restore when leaving a theme (goBack): browsing a
  // theme must not lose which row was open.
  property int lastThemeIndex: 0
  property bool busy: false
  property string statusText: ""
  // Search: one filter per list. `filterText` narrows the themes list,
  // `wallpaperFilterText` the wallpapers grid (each binds the list to a rebuilt
  // display model when active). `searching` routes all keys to the search
  // editor instead of the cursor shortcuts; it is shared by both views.
  // Entered with `/`, exited with Esc/Tab.
  property string filterText: ""
  property string wallpaperFilterText: ""
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

  // ---- image cache ----------------------------------------------------------
  // Big remote images are downloaded once by `manager.sh image` into
  // ~/.cache/omarchy/<pluginId>/ and then loaded from disk, so switching
  // selection never re-downloads or re-decodes the 2K original. The id comes
  // from the injected manifest, so the official and developer installs keep
  // separate caches.
  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "emkcloud.wallpaper-manager"
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

  // What the wallpapers grid and cursor read from.
  readonly property var activeWallpapersModel:
    wallpaperFilterText === "" ? wallpapersModel : wallpapersDisplayModel

  function rebuildWallpaperDisplay() {
    wallpapersDisplayModel.clear()
    for (var i = 0; i < wallpapersModel.count; i++) {
      var row = wallpapersModel.get(i)
      if (Model.wallpaperMatches(row, wallpaperFilterText)) wallpapersDisplayModel.append(row)
    }
    wallpapersRevision++
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

  // Whether the open wallpaper is the theme's current default background.
  readonly property bool currentIsDefault: {
    var rev = wallpapersRevision
    var item = currentItem()
    return !!item && String(item.isDefault) === "1"
  }

  // Gap around the preview overlays (path pill / filmstrip). The lateral insets
  // match the bottom one so all four sides read the same.
  readonly property real overlayInset: Style.space(12)
    + (previewStrip.height - previewPathPill.height) / 2

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
    if (cmd === "random-install") return "Downloading 5 random…"
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

  function open(payload) {
    opened = true
    view = "themes"
    selectedIndex = 0
    cursorActive = true
    pendingThemeSelect = true
    statusText = ""
    filterText = ""
    wallpaperFilterText = ""
    searching = false
    actionTheme = ""
    actionCancelled = false
    actionRunning = false
    addSourceSoon = false
    setupSoon = false
    loadThemes()
  }

  function close() {
    opened = false
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { keys.forceActiveFocus() })

  // manager.sh keys its caches (datasets + images) from this env var, so the
  // official and developer installs never share files. `/usr/bin/env` passes it
  // without relying on Process.environment's QVariantHash type.
  function scriptCmd(args) {
    return ["/usr/bin/env", "WALLPAPER_MANAGER_ID=" + pluginId, scriptPath].concat(args)
  }

  function setStatus(text) {
    statusText = String(text || "")
  }

  function loadThemes() {
    busy = true
    setStatus("Loading themes…")
    themesProc.running = true
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
    if (wallpaperFilterText !== "") rebuildWallpaperDisplay()
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
    themeName = item.name
    themeCatalogUrl = item.catalogUrl
    view = "wallpapers"
    selectedIndex = 0
    loadWallpapers()
  }

  function loadWallpapers() {
    busy = true
    setStatus("Loading wallpapers of " + themeName + "…")
    wallpapersModel.clear()
    wallpapersRevision++
    catalogProc.command = scriptCmd(["catalog", themeName, themeCatalogUrl])
    catalogProc.running = true
  }

  function goBack() {
    view = "themes"
    selectedIndex = Math.max(0, Math.min(activeThemesModel.count - 1, lastThemeIndex))
    cursorActive = true
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
  // count is computed by hand — see AGENTS.md).
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

    stepCursor(dx !== 0 ? dx : dy * grid.colCount)
  }

  // PageUp/PageDown: jump a whole visible page of tiles (rows on screen ×
  // columns; rows only on the themes list). PanelKeyCatcher does not map these
  // keys, so they bubble up to the card's Keys.onPressed fallback.
  function pageCursor(dir) {
    if (actionRunning) return
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
    if (view === "themes") selectTheme(selectedIndex)
    else if (view === "wallpapers") showPreview()
    else actionInstall()
  }

  function dismissCursor() {
    // While an action runs, Esc stops it instead of navigating away; a second
    // Esc then closes/backs out.
    if (actionRunning) {
      cancelAction()
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
      // Same rule as the buttons: no bulk task while one is running.
      if (actionRunning) return
      if (themeAction === "install") actionInstallTheme()
      else if (themeAction === "uninstall") actionRemoveThemeAll()
      else if (themeAction === "random") actionRandomInstall()
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

  // Wallpaper multi-select: buttons are in place, behaviour comes next.
  function selectAllWallpapers() {}
  function clearWallpaperSelection() {}

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
    grid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function previewNext(delta) {
    if (activeWallpapersModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(activeWallpapersModel.count - 1, selectedIndex + delta))
  }

  function actionInstall() {
    if (actionRunning) return
    var item = currentItem()
    // Already installed: nothing to do (button and `i` are no-ops).
    if (!item || String(item.installed) === "1") return
    busy = true
    setStatus("Installing " + item.name + "…")
    runAction(["install", themeName, item.filename])
  }

  function actionRemove() {
    if (actionRunning) return
    var item = currentItem()
    // Not installed: nothing to remove.
    if (!item || String(item.installed) !== "1") return
    busy = true
    setStatus("Removing " + item.name + "…")
    runAction(["remove", themeName, item.filename])
  }

  // `d` / double click: a switch. Not the default → set it (manager.sh installs
  // the file first if missing); already the default → clear it back to the
  // theme's own background.
  function actionToggleDefault() {
    if (actionRunning) return
    var item = currentItem()
    if (!item) return
    busy = true
    if (String(item.isDefault) === "1") {
      setStatus("Clearing default: " + item.name + "…")
      runAction(["unset-default", themeName, item.filename])
    } else {
      setStatus("Setting default: " + item.name + "…")
      runAction(["set-default", themeName, item.filename, item.url])
    }
  }

  function actionInstallAll() {
    busy = true
    setStatus("Installing all of theme " + themeName + "…")
    runAction(["install", themeName])
  }

  // Bulk install straight from the themes screen: no need to open the theme.
  function actionInstallTheme() {
    var theme = selectedTheme
    if (!theme) return
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

  // Install a small random sample (5) of the selected theme's wallpapers.
  function actionRandomInstall() {
    var theme = selectedTheme
    if (!theme) return
    busy = true
    setStatus("Installing 5 random wallpapers of " + theme.name + "…")
    runAction(["random-install", theme.name, "5"])
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
      if (args.length > 2) setWallpaperInstalled(String(args[2]), "1")
      else setAllWallpapersInstalled("1")
    } else if (cmd === "remove") {
      if (args.length > 2) setWallpaperInstalled(String(args[2]), "0")
      else setAllWallpapersInstalled("0")
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
  onSelectedIndexChanged: prefetchTimer.restart()
  onViewChanged: refreshDetailShown()
  // A prewarmed neighbour may make the full image available: upgrade the detail
  // pane from the small preview without waiting for the next selection.
  onImageCacheRevisionChanged: refreshDetailShown()

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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        wallpapersModel.clear()
        var rows = Model.parseCatalog(text)
        for (var i = 0; i < rows.length; i++) wallpapersModel.append(rows[i])
        if (root.wallpaperFilterText !== "") root.rebuildWallpaperDisplay()
        root.wallpapersRevision++
        root.busy = false
        root.setStatus(Model.catalogStatus(wallpapersModel.count, root.themeName))
        if (root.activeWallpapersModel.count > 0)
          Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
      }
    }
    onExited: {
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
      // Update the in-memory catalog in place; no full reload (see AGENTS).
      if (!cancelled) root.applyActionResult()
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

      // Del/Backspace are not part of the canonical key set (PanelKeyCatcher
      // maps removal to x/X); PageUp/PageDown are not mapped either. Both
      // bubble up here. While the themes search is active the catcher is
      // blocked and this handler owns every key.
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
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
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
        blocked: root.searching

        onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
        onActivateRequested: root.activateCursor()
        onCloseRequested: root.dismissCursor()
        onDeleteRequested: root.actionRemove()
        onTextKey: function(text) { root.handleTextKey(text) }
        onTabRequested: if ((root.view === "themes" || root.view === "wallpapers")
          && !root.searching) root.startSearch()

        // ---- hero -----------------------------------------------------------
        Component {
          id: heroIcon

          HeroLogo {
            glyph: root.view === "themes" ? "󰸌" : ""
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

            // Global store: total wallpapers and installed count across every
            // theme. Height matches a sibling Button's implicitHeight so the
            // pill lines up with the kit controls (the kit has no shared
            // "control height" applied to Button).
            BorderSurface {
              width: storeRow.implicitWidth + leftPadding + rightPadding
              height: refreshButton.implicitHeight
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              leftPadding: Style.spacing.controlPaddingX
              rightPadding: Style.spacing.controlPaddingX

              Row {
                id: storeRow
                anchors.centerIn: parent
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  text: root.globalCounts.wallpapers + " wallpapers"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                  width: Math.max(1, Style.normalBorderWidth)
                  height: storeRow.implicitHeight
                  color: Util.alpha(root.foreground, 0.25)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.globalCounts.installed + " installed"
                  color: root.statusInstalled
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Button {
              visible: root.view === "themes"
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

            Button {
              id: refreshButton

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
              visible: root.view === "wallpapers"
              // Frozen while an action runs, like the preview's actions.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Back"
              iconText: "󰁍"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.goBack()
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
          title: root.view === "themes"
            ? "Wallpaper manager"
            : ("Theme / " + Model.ucfirst(root.themeName))
          detail: ""
          meta: root.view === "themes"
            ? ("remote collections · " + themesModel.count
              + (themesModel.count === 1 ? " theme" : " themes"))
            : "browse and manage wallpapers"
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
                      opacity: enabled ? 1 : 0.4
                      text: "Random (5)"
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

        // ---- wallpapers view: search + grid ---------------------------------
        Item {
          id: wallpapersSearchRow

          visible: root.view === "wallpapers"
          anchors.top: heroRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(wallpapersSearch.height, selectionActions.implicitHeight)

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

            anchors.left: parent.left
            anchors.right: selectionActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.wallpaperFilterText
            placeholder: "Search wallpapers — name or code…"
            active: root.searching
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.startSearch()
            onCleared: root.setWallpaperFilter("")
          }
        }

        GridView {
          id: grid

          visible: root.view === "wallpapers"
          anchors.top: wallpapersSearchRow.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing
          model: root.activeWallpapersModel
          clip: true

          // Grid adapts to the card width: as many columns as fit while keeping
          // each tile at least ~190px wide (five columns on a regular screen).
          readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
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
              // Persistent state: this is the theme's default background.
              current: String(tile.model.isDefault) === "1"

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
                    text: tile.model.name
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

              // "DEFAULT" pill, top-left of the thumbnail, on the theme's
              // default wallpaper (dark fill so the accent reads on any image).
              Pill {
                visible: String(tile.model.isDefault) === "1"
                anchors.top: parent.top
                anchors.topMargin: root.tileInset + Style.space(8)
                anchors.left: parent.left
                anchors.leftMargin: root.tileInset + Style.space(8)
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
                onHoveredChanged: if (hovered) root.takeCursor(tile.index)
              }

              // A click opens the fullscreen preview, exactly like Enter: the
              // tile is a doorway, not a toggle. "Set default" therefore lives
              // in the preview (double click on the image), because a single
              // click here already switches view and no second tap can land.
              TapHandler {
                onTapped: {
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
              // footer controls; it is only a placeholder today.
              enabled: !actionRunning
              opacity: enabled ? 1 : 0.4
              text: "Setup"
              iconText: "󰒓"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              tooltipText: "Setup"
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
          // row — Install/Remove on the left, the open theme's progress in the
          // middle, Install all/Remove all on the right.
          Item {
            id: actionRow
            visible: root.view === "wallpapers"
            width: parent.width
            height: Math.max(primaryActions.implicitHeight,
              wallpapersProgress.implicitHeight, bulkActions.implicitHeight)

            Row {
              id: primaryActions
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              Button {
                enabled: !actionRunning
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
                text: "Remove"
                iconText: "󰩺"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionRemove()
              }
            }

            // First rule: same x as the themes screen's master/detail divider,
            // so the Install/Remove section spans the sidebar's width.
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

            // Second rule, between the progress and the bulk actions.
            Rectangle {
              id: wallpapersBulkRule

              z: 2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.right: bulkActions.left
              anchors.rightMargin: Style.space(20)
              width: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.12)
            }

            Row {
              id: bulkActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              Button {
                enabled: !root.actionRunning && !root.currentThemeFull
                opacity: enabled ? 1 : 0.4
                text: "Install all"
                iconText: "󰧩"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionInstallAll()
              }

              Button {
                enabled: !root.actionRunning && !root.currentThemeEmpty
                opacity: enabled ? 1 : 0.4
                text: "Remove all"
                iconText: "󰱢"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionRemoveAll()
              }
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

              // Real image info ("2K | 2560x1440"), standard colours, styled
              // like the store pill on the themes screen.
              BorderSurface {
                id: previewInfoPill

                visible: root.currentResolution !== "" || root.currentDimensions !== ""
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
            // "Catppuccin / Countries / Andorra": theme, collection, name.
            title: {
              var item = root.currentItem()
              if (!item) return ""
              var parts = [Model.ucfirst(root.themeName)]
              var collection = Model.ucfirst(item.collection)
              if (collection !== "") parts.push(collection)
              parts.push(item.name)
              return parts.join(" / ")
            }
            // Second line: file name, then its size in MB.
            meta: {
              var item = root.currentItem()
              if (!item) return ""
              if (previewView.failed) return "failed to load"
              var size = Model.formatSize(item.sizeBytes)
              return size !== "" ? item.filename + " · " + size : item.filename
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
              width: Math.min(pathText.implicitWidth + Style.space(28),
                parent.width - card.leftPadding - Style.space(12))
              height: pathText.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Util.alpha(root.background, 0.82)
              borderSpec: Border.flat(Util.alpha(root.foreground, 0.22),
                Math.max(1, Style.normalBorderWidth))

              Text {
                id: pathText

                width: parent.width - Style.space(28)
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.currentInstallPath
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
            // Match the pill's lateral gap from the card border: the strip lives
            // in the padded content area, so add back its content inset.
            anchors.rightMargin: root.overlayInset
              - (card.borderRight + card.rightPadding)
            anchors.bottom: parent.bottom
            // Lifted so the strip's bottom edge lines up with the path pill's.
            anchors.bottomMargin: footer.height - root.footerOverlap
              + root.overlayInset
            width: visibleCells * cellW + (visibleCells - 1) * previewStripList.spacing
              + contentLeftInset + contentRightInset
            height: cellH + contentTopInset + contentBottomInset
            radius: Style.cornerRadius
            color: Util.alpha(root.background, 0.7)
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
