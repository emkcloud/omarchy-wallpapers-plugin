import QtQuick
import Quickshell
import Quickshell.Io
import "js/Model.js" as Model

// Persistent application settings for the wallpaper manager.
//
// Created once by WallpaperManager and shared with the Setup screen. Keeping
// the values (and the load/save state) here — instead of inside SetupView —
// means the Setup screen can be destroyed and re-created when the user leaves
// it without losing anything: reopening it reads the same object.
//
// Every change is persisted automatically (debounced) to `settingsPath`; there
// is no Save button.
Item {
  id: settings

  // Where the settings live. The panel sets these from the injected manifest,
  // so `settingsPath` can arrive after this object is created (the file is
  // reloaded as soon as it is known — see `onSettingsPathChanged`).
  property string settingsPath: ""
  property string settingsDir: ""

  readonly property var defaults: ({
    resolution: "2k",
    shuffleCount: 5,
    parallelDownloads: 8,
    maxLocalFiles: 2500,
    maxDiskGb: 3,
    rotationEnabled: false,
    rotationInterval: 30,
    rotationAllTheme: false,
    rotationRandom: false,
    randomDefaultOnInstall: true
  })

  property string resolution: "2k"
  property int shuffleCount: 5
  property int parallelDownloads: 8
  property int maxLocalFiles: 2500
  property int maxDiskGb: 3
  property bool rotationEnabled: false
  property int rotationInterval: 30
  // Off: rotate only the plugin's wallpapers. On: every wallpaper of the
  // selected theme.
  property bool rotationAllTheme: false
  property bool rotationRandom: false
  // Custom-install screen: set a random wallpaper of the theme as the default
  // when an install launched from there finishes.
  property bool randomDefaultOnInstall: true

  // Per-theme remembered default wallpaper: `<theme> -> { filename, url }`.
  // Not a row in the UI, but persisted with the other settings so a default
  // chosen while browsing another theme survives restarts. `themeDefaultsRevision`
  // makes the plain object a tracked dependency for the DEFAULT markers.
  property var themeDefaults: ({})
  property int themeDefaultsRevision: 0

  // Global favourites, shared across themes. Keyed by `filename`, which is
  // identical in every theme's catalogue (the theme lives in the directory, not
  // in the name), so a starred wallpaper can be found and reinstalled in any
  // theme. The value keeps the display name/code/collection/resolution so a
  // favourite can be listed even without loading a catalogue.
  // `favoritesRevision` makes the plain object a tracked dependency for the
  // star markers and the "☆ Favorites" filter.
  property var favorites: ({})
  property int favoritesRevision: 0

  property bool settingsLoaded: false
  // Flashes the "Saved" caption after a write.
  property bool saved: false

  // ---- Setup screen navigation ---------------------------------------------
  // Focus state of the Setup screen, kept here (not in the view) so the screen
  // can be destroyed and rebuilt without losing where the cursor was.
  //
  // Two areas: the SECTIONS column and the section content. Tab / h-l switch
  // area, arrows / j-k walk the rows, Enter / Space toggle switches, Left/Right
  // adjust numeric values and the interval dropdown.
  readonly property var setupSections: [
    { id: "download", label: "Download" },
    { id: "rotation", label: "Automatic rotation" },
    { id: "version", label: "Updates" }
  ]
  property string setupSection: "download"
  property string setupNavArea: "sections"
  property int setupContentRow: 0
  // "Edit mode" for the adjustable rows, following the WAI-ARIA select-only
  // pattern: Enter opens (remembering the current value), Up/Down preview the
  // options, Enter commits, Esc reverts.
  property bool setupEditing: false
  property int setupEditingRow: -1
  property var setupEditingOriginal: null
  // True while the interval dropdown's popup is open.
  property bool setupDropdownOpen: false

  readonly property var setupNavRows: setupSection === "download"
    ? ["resolution", "shuffle", "parallel", "maxFiles", "maxDisk"]
    : setupSection === "rotation"
    ? ["enabled", "allTheme", "random", "interval", "rotateNow"]
    : ["changelog", "cdnChangelog", "security", "proposeFeature", "checkVersion"]

  // Rows that open in edit mode instead of toggling on Enter.
  readonly property var setupAdjustableRows: ["shuffle", "parallel", "maxFiles", "maxDisk"]

  function selectSetupSection(id) {
    if (setupEditing) cancelSetupEdit()
    setupSection = id
    setupContentRow = Math.max(0, Math.min(setupNavRows.length - 1, setupContentRow))
  }

  // Keyboard navigation of the sections (arrows / h-j-k-l): same model as the
  // other screens' cursor.
  function moveSetupSelection(delta) {
    if (setupSections.length === 0) return
    var current = 0
    for (var i = 0; i < setupSections.length; i++)
      if (setupSections[i].id === setupSection) { current = i; break }
    var next = Math.max(0, Math.min(setupSections.length - 1, current + delta))
    selectSetupSection(setupSections[next].id)
  }

  function isSetupRowFocused(sec, idx) {
    return setupNavArea === "content" && setupSection === sec && setupContentRow === idx
  }

  function cycleSetupArea(dir) {
    if (setupEditing) commitSetupEdit()
    setupNavArea = dir >= 0
      ? (setupNavArea === "sections" ? "content" : "sections")
      : (setupNavArea === "content" ? "sections" : "content")
    if (setupNavArea === "content") setupContentRow = 0
  }

  function moveSetupCursor(dx, dy) {
    // While editing, arrows preview the value instead of moving the cursor.
    if (setupNavArea === "content" && setupEditing) {
      if (dy !== 0) adjustSetupRow(dy)
      else if (dx !== 0) adjustSetupRow(dx)
      return
    }
    if (setupNavArea === "sections") {
      if (dy !== 0) {
        moveSetupSelection(dy)
        return
      }
      if (dx > 0) {
        setupNavArea = "content"
        setupContentRow = 0
      }
      return
    }
    if (dy !== 0) {
      // Clamp at both ends: the first and last row stay put.
      setupContentRow = Math.max(0, Math.min(setupNavRows.length - 1, setupContentRow + dy))
      return
    }
    if (dx !== 0) adjustSetupRow(dx)
  }

  // PageUp/PageDown jump to the previous/next section, clamped at the ends.
  function pageSetupSection(dir) {
    moveSetupSelection(dir)
    setupContentRow = 0
  }

  // The interval dropdown opens its own popup; SetupView calls it through the
  // `activateSetupCursor` hook below.
  function startSetupEdit() {
    setupEditing = true
    setupEditingRow = setupContentRow
    setupEditingOriginal = setupRowValue(setupNavRows[setupContentRow])
  }

  function commitSetupEdit() {
    setupEditing = false
    setupEditingRow = -1
    setupEditingOriginal = null
  }

  function cancelSetupEdit() {
    if (setupEditing && setupEditingOriginal !== null)
      setSetupRowValue(setupNavRows[setupEditingRow], setupEditingOriginal)
    setupEditing = false
    setupEditingRow = -1
    setupEditingOriginal = null
  }

  function setupRowValue(key) {
    switch (key) {
    case "interval": return rotationInterval
    case "shuffle": return shuffleCount
    case "parallel": return parallelDownloads
    case "maxFiles": return maxLocalFiles
    case "maxDisk": return maxDiskGb
    }
    return null
  }

  function setSetupRowValue(key, value) {
    switch (key) {
    case "interval": rotationInterval = value; break
    case "shuffle": shuffleCount = clampInt(value, 1, 50, shuffleCount); break
    case "parallel": parallelDownloads = clampInt(value, 1, 12, parallelDownloads); break
    case "maxFiles": maxLocalFiles = clampInt(value, 1000, 5000, maxLocalFiles); break
    case "maxDisk": maxDiskGb = clampInt(value, 1, 50, maxDiskGb); break
    }
  }

  function adjustSetupRow(dir) {
    switch (setupNavRows[setupContentRow]) {
    case "shuffle":
      shuffleCount = clampInt(shuffleCount + dir, 1, 50, shuffleCount); break
    case "parallel":
      parallelDownloads = clampInt(parallelDownloads + dir, 1, 12, parallelDownloads); break
    case "maxFiles":
      maxLocalFiles = clampInt(maxLocalFiles + dir * 100, 1000, 5000, maxLocalFiles); break
    case "maxDisk":
      maxDiskGb = clampInt(maxDiskGb + dir, 1, 50, maxDiskGb); break
    case "interval":
      cycleSetupInterval(dir); break
    default:
      break
    }
  }

  function activateSetupRow() {
    switch (setupNavRows[setupContentRow]) {
    case "enabled": rotationEnabled = !rotationEnabled; break
    case "allTheme": rotationAllTheme = !rotationAllTheme; break
    case "random": rotationRandom = !rotationRandom; break
    case "interval": cycleSetupInterval(1); break
    case "rotateNow":
      if (!rotateBusy) rotateRequested(); break
    case "shuffle":
      shuffleCount = clampInt(shuffleCount + 1, 1, 50, shuffleCount); break
    case "parallel":
      parallelDownloads = clampInt(parallelDownloads + 1, 1, 12, parallelDownloads); break
    case "maxFiles":
      maxLocalFiles = clampInt(maxLocalFiles + 100, 1000, 5000, maxLocalFiles); break
    case "maxDisk":
      maxDiskGb = clampInt(maxDiskGb + 1, 1, 50, maxDiskGb); break
    default:
      break
    }
  }

  function cycleSetupInterval(dir) {
    var i = intervalOptions.indexOf(rotationInterval)
    if (i < 0) i = 0
    i = (i + dir + intervalOptions.length) % intervalOptions.length
    rotationInterval = intervalOptions[i]
  }

  // Set by SetupView: `true` while a rotate is in flight, so "Rotate now" is
  // disabled; `activateSetupCursor` lets the view open its own interval popup.
  property bool rotateBusy: false
  property var activateSetupCursor: null
  signal rotateRequested()

  // ---- Help screen navigation ----------------------------------------------
  // Cursor state of the Help guide, kept here (not in the view) so the screen
  // can be destroyed and rebuilt without losing the selected topic.
  // `setupHelpSelectedFlat` walks topics first, then reference links;
  // `setupHelpContentTopic` lags behind it when the cursor sits on a resource,
  // so the prev/next cards keep steering the content; `setupHelpSelectedFile`
  // is the Markdown file currently shown.
  property int setupHelpSelectedFlat: 0
  property int setupHelpContentTopic: 0
  property string setupHelpSelectedFile: ""

  readonly property var intervalOptions: [1, 5, 15, 30, 60, 120]
  readonly property var intervalChoices: [
    { value: "1", label: "1 minute" },
    { value: "5", label: "5 minutes" },
    { value: "15", label: "15 minutes" },
    { value: "30", label: "30 minutes" },
    { value: "60", label: "1 hour" },
    { value: "120", label: "2 hours" }
  ]

  // ---- per-theme default wallpaper -----------------------------------------
  // The wallpaper chosen as a theme's default while browsing a theme that is
  // not the running one. Called by the panel; persists immediately (debounced).
  function themeDefault(theme) {
    var d = themeDefaults[String(theme)]
    return d && d.filename ? d : null
  }

  function sanitizeThemeDefaults(raw) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    for (var k in raw) {
      var v = raw[k]
      if (v && typeof v === "object" && typeof v.filename === "string" && v.filename !== "")
        out[String(k)] = {
          filename: String(v.filename),
          url: typeof v.url === "string" ? v.url : ""
        }
    }
    return out
  }

  function setThemeDefault(theme, filename, url) {
    if (!settingsLoaded || !theme || !filename) return
    var next = {}
    for (var k in themeDefaults) next[k] = themeDefaults[k]
    next[String(theme)] = { filename: String(filename), url: String(url || "") }
    themeDefaults = next
    themeDefaultsRevision++
    scheduleSave()
  }

  function clearThemeDefault(theme) {
    if (!settingsLoaded || !themeDefaults[String(theme)]) return
    var next = {}
    for (var k in themeDefaults)
      if (k !== String(theme)) next[k] = themeDefaults[k]
    themeDefaults = next
    themeDefaultsRevision++
    scheduleSave()
  }

  // ---- favourites ----------------------------------------------------------
  function isFavorite(filename) {
    var rev = favoritesRevision
    return Model.isFavorite(favorites, filename)
  }

  // Star/unstar a set of wallpapers in one write. `entries` is an array of
  // catalogue rows (objects with filename/name/code/collection/resolution);
  // `on` stamps or clears them together, so the grid's group toggle is a
  // single revision bump and a single debounced save.
  function setFavorites(entries, on) {
    if (!settingsLoaded || !entries || entries.length === 0) return
    var next = {}
    for (var k in favorites) next[k] = favorites[k]
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i] || {}
      var key = e.filename ? String(e.filename) : ""
      if (!key) continue
      if (on) {
        next[key] = {
          name: e.name ? String(e.name) : "",
          code: e.code ? String(e.code) : "",
          collection: e.collection ? String(e.collection) : "",
          resolution: e.resolution ? String(e.resolution) : ""
        }
      } else {
        delete next[key]
      }
    }
    favorites = next
    favoritesRevision++
    scheduleSave()
  }

  function clampInt(value, lo, hi, fallback) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(lo, Math.min(hi, Math.round(n)))
  }

  function load(raw) {
    if (settingsLoaded) return
    var parsed = {}
    try { parsed = raw ? JSON.parse(raw) : {} } catch (e) { parsed = {} }
    if (!parsed || typeof parsed !== "object") parsed = {}

    // Only 2K is selectable for now (4K/8K are placeholders), so any other
    // stored value falls back to it.
    resolution = parsed.resolution === "2k" ? "2k" : defaults.resolution
    shuffleCount = clampInt(parsed.shuffleCount, 1, 50, defaults.shuffleCount)
    parallelDownloads = clampInt(parsed.parallelDownloads, 1, 12, defaults.parallelDownloads)
    maxLocalFiles = clampInt(parsed.maxLocalFiles, 1000, 5000, defaults.maxLocalFiles)
    maxDiskGb = clampInt(parsed.maxDiskGb, 1, 50, defaults.maxDiskGb)
    rotationEnabled = parsed.rotationEnabled === true
    var interval = clampInt(parsed.rotationInterval, 1, 1440, defaults.rotationInterval)
    rotationInterval = intervalOptions.indexOf(interval) >= 0 ? interval : defaults.rotationInterval
    rotationAllTheme = parsed.rotationAllTheme === true
    rotationRandom = parsed.rotationRandom === true
    randomDefaultOnInstall = parsed.randomDefaultOnInstall !== false
    themeDefaults = sanitizeThemeDefaults(parsed.themeDefaults)
    favorites = Model.sanitizeFavorites(parsed.favorites)

    settingsLoaded = true
    saved = false
  }

  function serialize() {
    return JSON.stringify({
      version: 1,
      resolution: resolution,
      shuffleCount: shuffleCount,
      parallelDownloads: parallelDownloads,
      maxLocalFiles: maxLocalFiles,
      maxDiskGb: maxDiskGb,
      rotationEnabled: rotationEnabled,
      rotationInterval: rotationInterval,
      rotationAllTheme: rotationAllTheme,
      rotationRandom: rotationRandom,
      randomDefaultOnInstall: randomDefaultOnInstall,
      themeDefaults: themeDefaults,
      favorites: favorites
    }, null, 2) + "\n"
  }

  // Coalesce a burst of changes into a single write.
  function scheduleSave() {
    if (!settingsLoaded) return
    autosaveTimer.restart()
  }

  function save() {
    settingsFile.setText(serialize())
    saved = true
    savedReset.restart()
  }

  function restoreDefaults() {
    resolution = defaults.resolution
    shuffleCount = defaults.shuffleCount
    parallelDownloads = defaults.parallelDownloads
    maxLocalFiles = defaults.maxLocalFiles
    maxDiskGb = defaults.maxDiskGb
    rotationEnabled = defaults.rotationEnabled
    rotationInterval = defaults.rotationInterval
    rotationAllTheme = defaults.rotationAllTheme
    rotationRandom = defaults.rotationRandom
    randomDefaultOnInstall = defaults.randomDefaultOnInstall
  }

  // Persist on every change (debounced). `load()` fills the properties before
  // `settingsLoaded` flips, so these are no-ops until the initial load is done.
  onResolutionChanged: scheduleSave()
  onShuffleCountChanged: scheduleSave()
  onParallelDownloadsChanged: scheduleSave()
  onMaxLocalFilesChanged: scheduleSave()
  onMaxDiskGbChanged: scheduleSave()
  onRotationEnabledChanged: scheduleSave()
  onRotationIntervalChanged: scheduleSave()
  onRotationAllThemeChanged: scheduleSave()
  onRotationRandomChanged: scheduleSave()

  FileView {
    id: settingsFile

    path: settings.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: settings.load(text())
    onLoadFailed: settings.load("")
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", settings.settingsDir]
  }

  Timer {
    id: savedReset
    interval: 2000
    repeat: false
    onTriggered: settings.saved = false
  }

  Timer {
    id: autosaveTimer
    interval: 400
    repeat: false
    onTriggered: settings.save()
  }

  // `settingsPath` derives from the injected manifest, which can arrive after
  // this object is created: the first binding may point at the fallback
  // (official) path, whose failed load would lock `settingsLoaded`. Reload from
  // the real path as soon as it is known.
  onSettingsPathChanged: {
    settingsLoaded = false
    Qt.callLater(function() { settingsFile.reload() })
  }

  Component.onCompleted: {
    if (settingsDir !== "") mkdirProc.running = true
    Qt.callLater(function() { settingsFile.reload() })
  }
}
