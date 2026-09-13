import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
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

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  property string view: "themes"          // "themes" | "wallpapers" | "preview"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  property bool busy: false
  property string statusText: ""
  // Themes search: `filterText` narrows the left list (no model when empty),
  // `searching` routes all keys to the search editor instead of the cursor
  // shortcuts. Entered with `/`, exited with Esc/Tab.
  property string filterText: ""
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
  // "Add remote source" placeholder: shows a COMING SOON label for 3s on click.
  property bool addSourceSoon: false
  // Custom Install placeholder: same COMING SOON feedback, always clickable.
  property bool setupSoon: false
  // Bumped whenever `themesModel` is reloaded: property bindings that read the
  // model rows (`selectedTheme`, `themeCounts`) depend on it to re-evaluate.
  property int themesRevision: 0

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
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
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
  readonly property var progressTheme: {
    if (actionRunning && actionTheme !== "") {
      var running = themeByName(actionTheme)
      if (running) return running
    }
    return selectedTheme
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
    if (!item || item.installed === "1") return ""
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

  // Stable status-dot colors: brand green/blue (assets/images/logo.png palette)
  // for installed/installing, dim for available.
  readonly property color statusInstalled: "#05DF72"
  readonly property color statusInstalling: "#155DFC"

  // ---- lifecycle ------------------------------------------------------------
  function open(payload) {
    opened = true
    view = "themes"
    selectedIndex = 0
    cursorActive = true
    statusText = ""
    filterText = ""
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

  function scriptCmd(args) {
    var cmd = [scriptPath].concat(args)
    return cmd
  }

  function setStatus(text) {
    statusText = String(text || "")
  }

  function loadThemes() {
    busy = true
    setStatus("Loading themes…")
    themesProc.running = true
  }

  // ---- themes search --------------------------------------------------------
  function startSearch() {
    if (view !== "themes" || searching) return
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

  // The dataset carries a readable `title` ("Tokyo Night"); the tiles show it
  // uppercased. Fallback for older datasets: normalize the slug. See Model.js.
  function selectTheme(index) {
    if (index < 0 || index >= activeThemesModel.count) return
    var item = activeThemesModel.get(index)
    // Drop the previous theme's rows first: the wallpapers GridView delegates
    // survive the trip through the themes view, so leaving them alive while
    // `themeName` changes makes them re-resolve their local file path against
    // the new theme and log a pile of "Cannot open" warnings.
    wallpapersModel.clear()
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
    catalogProc.command = scriptCmd(["catalog", themeName, themeCatalogUrl])
    catalogProc.running = true
  }

  function goBack() {
    view = "themes"
    selectedIndex = 0
    setStatus("")
  }

  function refresh() {
    if (actionRunning) return
    if (view === "themes") loadThemes()
    else if (view === "wallpapers") loadWallpapers()
  }

  // ---- cursor state machine -------------------------------------------------
  // Ui/PanelKeyCatcher.qml turns raw keys into semantic signals; the panel
  // keeps the state machine. The themes screen is a vertical ListView, the
  // wallpapers screen a GridView (which has no `columns` in Qt 6, so the column
  // count is computed by hand — see AGENTS.md).
  function activeCount() {
    return view === "themes" ? activeThemesModel.count : wallpapersModel.count
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
    // An active theme filter swallows the first Esc (clear, stay put).
    if (view === "themes" && filterText !== "") {
      setThemeFilter("")
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
    var action = Model.textAction(text)
    if (action === "default") actionSetDefault()
    else if (action === "refresh") refresh()
    else if (action === "install") actionInstall()
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
        || selectedIndex < 0 || selectedIndex >= wallpapersModel.count)
      return null
    return wallpapersModel.get(selectedIndex)
  }

  function showPreview() {
    if (wallpapersModel.count === 0) return
    view = "preview"
  }

  function closePreview() {
    view = "wallpapers"
    grid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function previewNext(delta) {
    if (wallpapersModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(wallpapersModel.count - 1, selectedIndex + delta))
  }

  function actionInstall() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Installing " + item.name + "…")
    runAction(["install", themeName, item.filename])
  }

  function actionRemove() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Removing " + item.name + "…")
    runAction(["remove", themeName, item.filename])
  }

  function actionSetDefault() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Setting default: " + item.name + "…")
    runAction(["set-default", themeName, item.filename, item.url])
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
    actionRunning = true
    actionProc.command = scriptCmd(args)
    actionProc.running = true
  }

  // Live progress from `manager.sh` (`PROGRESS` TSV lines): buffer the latest
  // count and flush it on a timer, so a bulk install does not re-evaluate the
  // whole screen on every downloaded file. `onExited` refreshes from the source
  // of truth once the operation is over.
  function applyProgress(name, installed) {
    if (!name || !isFinite(installed)) return
    pendingProgressTheme = name
    pendingProgressInstalled = installed
    progressTimer.restart()
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

  // manager.sh picks the cache directory from this env var, so the official and
  // developer installs never share files. `/usr/bin/env` passes it without
  // relying on Process.environment's QVariantHash type.
  function cachedCmd(args) {
    return ["/usr/bin/env", "WALLPAPER_MANAGER_ID=" + pluginId, scriptPath].concat(args)
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

  // Warm the cache for the neighbours of the selection so moving through the
  // list finds the images already on disk. Fire-and-forget, debounced. Never
  // while an install/remove runs: the extra downloads would compete with it and
  // make the UI stutter.
  function prefetchNeighbours() {
    if (busy || actionRunning) return
    var urls = []
    var model
    if (view === "themes") model = themesModel
    else if (view === "wallpapers" || view === "preview") model = wallpapersModel
    else return
    var lo = Math.max(0, selectedIndex - 3)
    var hi = Math.min(model.count - 1, selectedIndex + 3)
    for (var i = lo; i <= hi; i++) {
      var row = model.get(i)
      if (!row) continue
      if (view === "themes") {
        var themeUrl = row.image ? row.image : row.preview
        if (themeUrl && themeUrl.indexOf("http") === 0) urls.push(themeUrl)
      } else if (row.installed !== "1" && row.url && row.url.indexOf("http") === 0) {
        urls.push(row.url)
      }
    }
    if (urls.length === 0) return
    Quickshell.execDetached(cachedCmd(["prewarm"].concat(urls)))
  }

  onDetailTargetUrlChanged: {
    resolveDetailImage()
    refreshDetailShown()
  }
  onPreviewTargetUrlChanged: resolvePreviewImage()
  onSelectedIndexChanged: prefetchTimer.restart()
  onViewChanged: refreshDetailShown()

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
        if (root.selectedIndex >= root.activeThemesModel.count)
          root.selectedIndex = Math.max(0, root.activeThemesModel.count - 1)
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
        root.busy = false
        root.setStatus(Model.catalogStatus(wallpapersModel.count, root.themeName))
        if (wallpapersModel.count > 0)
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
      root.actionTheme = ""
      root.progressTimer.stop()
      root.pendingProgressTheme = ""
      root.pendingProgressInstalled = -1
      root.setStatus(cancelled ? "Operation cancelled" : "Operation completed")
      root.refresh()
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
            if (root.filterText !== "") root.setThemeFilter("")
            else root.stopSearch()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.stopSearch()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setThemeFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveCursor(0, -1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveCursor(0, 1)
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
            root.setThemeFilter(root.filterText + event.text)
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
        } else if (root.view === "themes" && event.text === "/") {
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
        onTabRequested: if (root.view === "themes" && !root.searching) root.startSearch()

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
              text: "DEVELOPER"
              iconText: "\uf121"
              bordered: true
              foreground: root.accent
              accent: root.accent
              fontFamily: root.fontFamily
            }

            Button {
              visible: root.view === "wallpapers"
              text: "Back"
              iconText: "󰁍"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.goBack()
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
          title: root.view === "themes" ? "Wallpaper manager" : root.themeName
          detail: root.view === "themes"
            ? ""
            : (wallpapersModel.count > 0 ? String(wallpapersModel.count) : "")
          meta: root.view === "themes"
            ? ("remote collections · " + themesModel.count
              + (themesModel.count === 1 ? " theme" : " themes"))
            : "browse and manage"
        }

        PanelSeparator {
          id: heroRule
          visible: root.view !== "preview"
          anchors.top: hero.bottom
          anchors.topMargin: Style.space(14)
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
          anchors.right: parent.right
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

              // Omarchy-style search field (a real box, no QQC TextField so
              // arrow keys keep driving the cursor): `/` enters it, Esc clears
              // then exits. The focused state leans on the accent (not the kit's
              // fainter focus border) so active reads as active, not disabled.
              BorderSurface {
                id: searchBar

                anchors.top: parent.top
                anchors.topMargin: Style.space(12)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.contentMargin
                height: Math.max(searchGlyph.implicitHeight, searchQuery.implicitHeight)
                  + contentTopInset + contentBottomInset
                radius: Style.cornerRadius
                color: root.searching ? Util.alpha(root.accent, 0.10) : "transparent"
                borderSpec: root.searching
                  ? Border.flat(root.accent, Math.max(1, Style.normalBorderWidth))
                  : Border.flat(Util.alpha(root.foreground, 0.18),
                    Math.max(1, Style.normalBorderWidth))
                leftPadding: Style.spacing.controlPaddingX
                rightPadding: Style.spacing.controlPaddingX
                topPadding: Style.spacing.controlPaddingY
                bottomPadding: Style.spacing.controlPaddingY

                // Click anywhere on the field to take over the keyboard.
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startSearch()
                }

                Text {
                  id: searchGlyph

                  anchors.left: parent.left
                  anchors.leftMargin: searchBar.contentLeftInset
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "󰍉"
                  color: root.searching ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }

                Text {
                  id: searchQuery

                  anchors.left: searchGlyph.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: searchClear.visible ? searchClear.left : parent.right
                  anchors.rightMargin: searchClear.visible ? Style.space(6) : searchBar.contentRightInset
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.filterText || "Search themes…"
                  color: root.filterText ? root.foreground : root.dim
                  opacity: root.filterText ? 1 : 0.58
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                // Blinking caret, right after the typed text.
                Rectangle {
                  id: searchCaret

                  visible: root.searching
                  width: 1
                  height: searchQuery.implicitHeight
                  color: root.accent
                  anchors.verticalCenter: parent.verticalCenter
                  x: {
                    var pos = root.filterText === ""
                      ? searchQuery.x
                      : Math.min(searchQuery.x + searchQuery.contentWidth + Style.space(2),
                          searchQuery.x + searchQuery.width)
                    if (searchClear.visible) pos = Math.min(pos, searchClear.x - Style.space(4))
                    return pos
                  }

                  SequentialAnimation on opacity {
                    running: searchCaret.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.0; duration: 500 }
                    NumberAnimation { to: 1.0; duration: 500 }
                  }
                }

                // Clear button: empties the filter but keeps the field focused.
                Text {
                  id: searchClear

                  visible: root.searching && root.filterText !== ""
                  anchors.right: parent.right
                  anchors.rightMargin: searchBar.contentRightInset
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "✕"
                  color: clearHover.hovered ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon

                  HoverHandler {
                    id: clearHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  TapHandler {
                    onTapped: root.setThemeFilter("")
                  }
                }
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
                    // row up. Entering the wallpaper grid stays on Enter/Space
                    // or the detail "Browse" button.
                    TapHandler {
                      onTapped: root.takeCursor(themeRow.index)
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
        }

        // ---- wallpapers view ------------------------------------------------
        GridView {
          id: grid

          visible: root.view === "wallpapers"
          anchors.top: heroRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing
          model: wallpapersModel
          clip: true

          // Grid adapts to the card width: as many columns as fit while keeping
          // each tile at least ~190px wide (so previews stay readable).
          readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
          readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
          cellWidth: Math.floor(width / columnsHint)
          cellHeight: Math.floor(cellWidth * 0.9)

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
              current: tile.model.isDefault === "1"

              RoundedImage {
                id: preview
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: root.tileInset
                height: parent.height - Style.space(60)
                inset: root.tileInset
                bottomRadius: 0
                // Local file when already installed (instant), reduced remote
                // preview otherwise; fall back to the full-res URL if a preview
                // is missing. GridView only creates visible delegates, so
                // nearby tiles load lazily as you scroll.
                source: tile.model.installed === "1"
                  ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + tile.model.filename)
                  : (tile.model.preview !== "" ? tile.model.preview : tile.model.url)
              }

              Row {
                id: tileLabels
                anchors.top: preview.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
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

              Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)

                Pill {
                  visible: tile.model.installed === "1"
                  label: "installed"
                  tint: root.accent
                }

                Pill {
                  visible: tile.model.isDefault === "1"
                  label: "default"
                  tint: root.urgent
                }
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

          visible: root.view !== "preview"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(14)

          PanelSeparator { foreground: root.foreground }

          // Themes footer: installed/available summary on the left, progress of
          // the selected theme in the middle, key hints on the right.
          Item {
            id: themesFooterRow

            visible: root.view === "themes"
            width: parent.width
            height: Math.max(themesSummary.implicitHeight,
              themeProgress.implicitHeight, themesHints.implicitHeight)

            Row {
              id: themesSummary

              anchors.left: parent.left
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
                textFormat: Text.PlainText
                text: root.themeCounts.installed + " installed · "
                  + root.themeCounts.available + " available"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: themeProgress

              // Aligned with the detail buttons above and stretched across the
              // whole detail zone, up to the key-hints divider.
              anchors.left: parent.left
              anchors.leftMargin: themeListPane.width + Style.space(22)
              anchors.right: hintsRule.left
              anchors.rightMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              readonly property real ratio: {
                var theme = root.progressTheme
                if (!theme || !theme.count) return 0
                return Math.max(0, Math.min(1, (theme.installed || 0) / theme.count))
              }

              Item {
                width: parent.width
                height: progressLabel.implicitHeight

                Text {
                  id: progressLabel

                  anchors.left: parent.left
                  textFormat: Text.PlainText
                  text: {
                    var theme = root.progressTheme
                    if (!theme) return ""
                    return Model.themeLabel(theme) + " · " + (theme.installed || 0) + "/" + (theme.count || 0)
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: progressPercent

                  anchors.right: parent.right
                  textFormat: Text.PlainText
                  text: Math.round(themeProgress.ratio * 100) + "%"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Util.alpha(root.foreground, 0.12)

                Rectangle {
                  width: parent.width * themeProgress.ratio
                  height: parent.height
                  radius: parent.radius
                  color: root.accent
                }
              }
            }

            Text {
              id: themesHints

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.StyledText
              text: actionRunning
                ? root.keyHint("esc", "stop")
                : root.keyHint("enter", "browse") + "   " + root.keyHint("i", "install")
                  + "   " + root.keyHint("/", "search") + "   " + root.keyHint("esc", "close")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Vertical rules, as in the original mockup: the first continues
            // the master list's right border into the footer, the second
            // separates the progress from the key hints.
            Rectangle {
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

          Item {
            id: actionRow
            visible: root.view === "wallpapers"
            width: parent.width
            height: Math.max(primaryActions.implicitHeight, bulkActions.implicitHeight)

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

              Button {
                enabled: !actionRunning
                opacity: enabled ? 1 : 0.4
                text: "Default"
                iconText: "󰋯"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionSetDefault()
              }
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

          Text {
            id: statusLabel
            // Never on the themes view: the summary/progress row already
            // reports the state, and this caption would grow the footer and
            // shove the content up when an operation starts.
            visible: text !== "" && root.view !== "themes"
            width: parent.width
            textFormat: Text.PlainText
            text: root.statusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // ---- fullscreen preview ---------------------------------------------
        Item {
          id: previewView

          visible: root.view === "preview"
          anchors.fill: parent
          z: 10

          // natural size of the wallpaper currently shown; drives the fitted
          // rounded frame so the image corners follow the theme geometry
          property size fittedSize: Qt.size(0, 0)

          // last source that failed to load, so the hero meta can report it
          property string failedSource: ""

          // target wallpaper, preloaded in background while the current one
          // stays up. Remote images come from the disk cache once resolved, so
          // stepping through the preview no longer re-downloads the 2K original.
          readonly property string nextSource: {
            var item = root.currentItem()
            if (!item) return ""
            if (item.installed === "1")
              return Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + item.filename)
            if (root.previewImagePath !== "" && root.previewImageSource === item.url)
              return Util.fileUrl(root.previewImagePath)
            return item.url
          }

          // true only when the visible image is the one of the selected item,
          // so the title never pairs a name with the previous resolution
          readonly property bool shown: previewImage.status === Image.Ready
            && String(previewImage.source) === String(nextSource)

          readonly property bool failed: failedSource !== ""
            && String(failedSource) === String(nextSource)

          // true when an event point falls inside the fitted wallpaper rect;
          // used to route taps (image → set default, outside → back)
          function onImage(point) {
            var p = previewView.mapToItem(fitted, point.position.x, point.position.y)
            return p.x >= 0 && p.y >= 0 && p.x <= fitted.width && p.y <= fitted.height
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
                text: "DEVELOPER"
                iconText: "\uf121"
                bordered: true
                foreground: root.accent
                accent: root.accent
                fontFamily: root.fontFamily
              }

              Pill {
                visible: root.currentItem() && root.currentItem().installed === "1"
                anchors.verticalCenter: parent.verticalCenter
                label: "installed"
                tint: root.accent
              }

              Pill {
                visible: root.currentItem() && root.currentItem().isDefault === "1"
                anchors.verticalCenter: parent.verticalCenter
                label: "default"
                tint: root.urgent
              }

              Button {
                text: "Back"
                iconText: "󰁍"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.closePreview()
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
            // "AD - Andorra (2000x1000)": code, name, then the real resolution
            title: {
              var item = root.currentItem()
              if (!item) return ""
              var label = item.code !== "" ? item.code + " - " + item.name : item.name
              if (previewView.shown && previewImage.implicitWidth > 0)
                return label + " (" + previewImage.implicitWidth
                  + "x" + previewImage.implicitHeight + ")"
              return label
            }
            // no `detail` pill: the code is inline in the title
            meta: {
              var item = root.currentItem()
              if (!item) return ""
              if (previewView.failed) return "failed to load " + item.filename
              if (!previewView.shown) return "loading " + item.filename
              return item.filename
            }
          }

          PanelSeparator {
            id: previewRule
            anchors.top: previewHero.bottom
            anchors.topMargin: root.contentSpacing
            foreground: root.foreground
          }

          Text {
            id: previewHint
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            textFormat: Text.StyledText
            text: "<b>h/l</b> or <b>arrows</b> to walk · <b>Enter</b> to install · <b>d</b> or <b>double click</b> to set default · <b>Esc</b> to go back"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            id: previewImageFrame

            anchors.top: previewRule.bottom
            anchors.topMargin: root.contentSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: previewHint.top
            anchors.bottomMargin: root.contentSpacing

            // rounded mask sized exactly to the fitted image, so the image
            // corners are rounded even when the wallpaper letterboxes
            Rectangle {
              id: previewImageMask
              x: fitted.x
              y: fitted.y
              width: fitted.width
              height: fitted.height
              visible: false
              layer.enabled: true
              color: "white"
              radius: Style.cornerRadius
            }

            // fitted rect: aspect-fit box computed from the natural image size
            Item {
              id: fitted
              readonly property real s: {
                var iw = previewView.fittedSize.width
                var ih = previewView.fittedSize.height
                if (iw <= 0 || ih <= 0) return 0
                return Math.min(previewImageFrame.width / iw, previewImageFrame.height / ih)
              }
              x: (previewImageFrame.width - previewView.fittedSize.width * s) / 2
              y: (previewImageFrame.height - previewView.fittedSize.height * s) / 2
              width: previewView.fittedSize.width * s
              height: previewView.fittedSize.height * s
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: previewImageMask
              }

              Image {
                id: previewImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
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
                previewView.fittedSize = Qt.size(nextImage.implicitWidth, nextImage.implicitHeight)
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
              if (!previewView.onImage(point)) root.closePreview()
            }
            onDoubleTapped: (point, button) => {
              if (previewView.onImage(point)) root.actionSetDefault()
            }
          }
        }
      }
    }
  }
}
