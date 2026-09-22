import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../components"
import "../sections"

// Setup screen: the same three-column skeleton as Help — the shared roadmap on
// the left (same width and padding as Help), the selected section's settings in
// the centre, and the section index on the right.
// Values are held here and persisted automatically (debounced) to
// `settingsPath` (the plugin's config dir) with FileView.setText, then reused
// by the panel (e.g. `shuffleCount`). There is no Save button.
Item {
  id: setup

  property string settingsPath: ""
  property string settingsDir: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  // Same master-pane width as the themes/help screens, so the sidebars line up.
  property real sidebarWidth: 0
  // Roadmap rendered in the left column, shared with Help (loaded by the panel).
  property var roadmap: ({ title: "Roadmap", subtitle: "", items: [] })
  // "Propose a feature" label, shared with Help; hidden when empty.
  property string featureLabel: ""

  signal featureClicked()
  // "Rotate now": the panel runs `manager.sh rotate` immediately.
  signal rotateRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property int gutter: Style.space(28)
  readonly property int bodyPadY: Style.space(24)

  // ---- settings ------------------------------------------------------------
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
  // when an install launched from there finishes. Persisted here with the other
  // settings; only surfaced on that screen.
  property bool randomDefaultOnInstall: true
  // Per-theme remembered default wallpaper: `<theme> -> { filename, url }`.
  // Not a row in the UI, but persisted with the other settings so a default
  // chosen while browsing another theme survives restarts and is applied when
  // the user switches to that theme. `themeDefaultsRevision` makes the plain
  // object a tracked dependency for the DEFAULT markers.
  property var themeDefaults: ({})
  property int themeDefaultsRevision: 0
  // Injected by the panel: a rotate is in flight, so "Rotate now" is disabled.
  property bool rotateBusy: false

  property bool settingsLoaded: false
  // Flashes the "Saved" caption after a write.
  property bool saved: false

  // ---- usage (right sidebar) ----------------------------------------------
  // Live local usage injected by the panel, shown against the caps.
  property int localFileCount: 0
  property real localBytes: 0

  readonly property int usageFilePercent: maxLocalFiles > 0
    ? Math.min(100, Math.round(localFileCount / maxLocalFiles * 100)) : 0
  readonly property int usageDiskPercent: maxDiskGb > 0
    ? Math.min(100, Math.round(localBytes / (maxDiskGb * 1073741824) * 100)) : 0

  // Uniform bottom margin under every sidebar section title (SECTIONS / USAGE /
  // ACTIONS), so they all breathe the same.
  readonly property int sectionTitleGap: Style.space(10)

  // Thousands separator for the big counters ("1,000").
  function grouped(n) {
    var s = String(Math.max(0, Math.round(Number(n) || 0)))
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }

  // ---- per-theme default wallpaper -----------------------------------------
  // The wallpaper chosen as a theme's default while browsing a theme that is
  // not the running one. `setThemeDefault`/`clearThemeDefault` are called by the
  // panel and persist immediately (debounced).
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

  // Shared sidebar caption: uppercase, dim, with the uniform gap below.
  component SectionTitle: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: setup.dim
    font.family: setup.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
    font.letterSpacing: 1.2
    bottomPadding: setup.sectionTitleGap
  }

  // Every change is persisted automatically (debounced); there is no Save
  // button. `load()` fills the properties before `settingsLoaded` flips, so
  // these handlers stay no-ops until the initial load has finished.
  onResolutionChanged: scheduleSave()
  onShuffleCountChanged: scheduleSave()
  onParallelDownloadsChanged: scheduleSave()
  onMaxLocalFilesChanged: scheduleSave()
  onMaxDiskGbChanged: scheduleSave()
  onRotationEnabledChanged: scheduleSave()
  onRotationIntervalChanged: scheduleSave()
  onRotationAllThemeChanged: scheduleSave()
  onRotationRandomChanged: scheduleSave()

  component FieldHint: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: Qt.darker(setup.foreground, 1.6)
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    lineHeight: 1.25
    lineHeightMode: Text.ProportionalHeight
  }

  // One usage card: dashed outline, caption + percent badge, "used / total" and
  // a progress bar. Turns to the theme's urgent color once near the cap.
  component UsageCard: Item {
    id: usageCard

    property string label: ""
    property string usedLabel: ""
    property string totalLabel: ""
    property int percent: 0

    readonly property bool critical: percent >= 90
    readonly property color tint: usageCard.critical ? Color.urgent : setup.accent
    readonly property color borderColor: usageCard.critical ? Color.urgent : setup.dim
    readonly property int pad: Style.space(12)

    implicitHeight: usageBody.implicitHeight + pad * 2

    // Dotted rounded outline, same treatment as "Restore defaults".
    Shape {
      id: usageOutline

      anchors.fill: parent

      readonly property real r: Math.max(0, Style.cornerRadius)
      readonly property real w: width - usagePath.strokeWidth
      readonly property real h: height - usagePath.strokeWidth
      readonly property real inset: usagePath.strokeWidth / 2

      ShapePath {
        id: usagePath

        strokeColor: usageCard.borderColor
        strokeWidth: 1
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 3]
        capStyle: ShapePath.FlatCap

        startX: usageOutline.inset + usageOutline.r
        startY: usageOutline.inset
        PathLine {
          x: usageOutline.inset + usageOutline.w - usageOutline.r
          y: usageOutline.inset
        }
        PathArc {
          x: usageOutline.inset + usageOutline.w
          y: usageOutline.inset + usageOutline.r
          radiusX: usageOutline.r
          radiusY: usageOutline.r
        }
        PathLine {
          x: usageOutline.inset + usageOutline.w
          y: usageOutline.inset + usageOutline.h - usageOutline.r
        }
        PathArc {
          x: usageOutline.inset + usageOutline.w - usageOutline.r
          y: usageOutline.inset + usageOutline.h
          radiusX: usageOutline.r
          radiusY: usageOutline.r
        }
        PathLine {
          x: usageOutline.inset + usageOutline.r
          y: usageOutline.inset + usageOutline.h
        }
        PathArc {
          x: usageOutline.inset
          y: usageOutline.inset + usageOutline.h - usageOutline.r
          radiusX: usageOutline.r
          radiusY: usageOutline.r
        }
        PathLine {
          x: usageOutline.inset
          y: usageOutline.inset + usageOutline.r
        }
        PathArc {
          x: usageOutline.inset + usageOutline.r
          y: usageOutline.inset
          radiusX: usageOutline.r
          radiusY: usageOutline.r
        }
      }
    }

    Column {
      id: usageBody

      anchors.left: parent.left
      anchors.leftMargin: usageCard.pad
      anchors.right: parent.right
      anchors.rightMargin: usageCard.pad
      anchors.top: parent.top
      anchors.topMargin: usageCard.pad
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: usageLabel

          textFormat: Text.PlainText
          text: usageCard.label
          color: setup.dim
          font.family: setup.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          font.capitalization: Font.AllUppercase
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: Math.max(0, parent.width - usageLabel.implicitWidth
            - usageBadge.width - parent.spacing * 2)
          height: 1
        }

        BorderSurface {
          id: usageBadge

          width: usageBadgeText.implicitWidth + Style.space(12)
          height: usageBadgeText.implicitHeight + Style.space(6)
          radius: Style.space(4)
          color: Util.alpha(usageCard.tint, 0.15)
          borderSpec: Border.flat(usageCard.tint, Math.max(1, Style.normalBorderWidth))
          anchors.verticalCenter: parent.verticalCenter

          Text {
            id: usageBadgeText

            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: usageCard.percent + "%"
            color: usageCard.tint
            font.family: setup.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Row {
        spacing: Style.space(6)

        Text {
          id: usageUsed

          textFormat: Text.PlainText
          text: usageCard.usedLabel
          color: setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: "/ " + usageCard.totalLabel
          color: setup.dim
          font.family: setup.fontFamily
          font.pixelSize: Style.font.body
          anchors.bottom: usageUsed.bottom
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(6)
        radius: height / 2
        color: Util.alpha(setup.foreground, 0.12)

        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, usageCard.percent / 100))
          height: parent.height
          radius: height / 2
          color: usageCard.tint
        }
      }
    }
  }

  // ---- sections ------------------------------------------------------------
  // Only Download and Rotation are exposed for now; Storage, Theme integration
  // and Advanced are deferred until they are actually implemented.
  property var sections: [
    { id: "download", label: "Download" },
    { id: "rotation", label: "Automatic rotation" }
  ]
  property string section: "download"

  function selectSection(id) {
    if (editing) cancelEdit()
    section = id
    contentFlick.contentY = 0
    contentRow = Math.max(0, Math.min(navRows.length - 1, contentRow))
  }

  // Keyboard navigation of the sections (arrows / h-j-k-l): same model as the
  // other screens' cursor.
  function moveSelection(delta) {
    if (sections.length === 0) return
    var current = 0
    for (var i = 0; i < sections.length; i++)
      if (sections[i].id === section) { current = i; break }
    var next = Math.max(0, Math.min(sections.length - 1, current + delta))
    selectSection(sections[next].id)
  }

  // ---- keyboard focus model ------------------------------------------------
  // Two areas: the SECTIONS column and the section content. Tab / h-l switch
  // area, arrows / j-k walk the rows, Enter / Space toggle switches, Left/Right
  // adjust numeric values and the interval dropdown.
  property string navArea: "sections"
  property int contentRow: 0

  // "Edit mode" for the adjustable rows, following the WAI-ARIA select-only
  // pattern: Enter opens (remembering the current value), Up/Down preview the
  // options, Enter commits, Esc reverts.
  property bool editing: false
  property int editingRow: -1
  property var editingOriginal: null

  readonly property var navRows: section === "download"
    ? ["resolution", "shuffle", "parallel", "maxFiles", "maxDisk"]
    : ["enabled", "allTheme", "random", "interval", "rotateNow"]

  // Rows that open in edit mode instead of toggling on Enter.
  readonly property var adjustableRows: ["shuffle", "parallel", "maxFiles", "maxDisk"]

  // True while the interval dropdown's popup is open: the panel releases the
  // keyboard so the dropdown's own list handles arrows / Enter / Esc.
  readonly property bool dropdownOpen: intervalField.popupOpen

  function isRowFocused(sec, idx) {
    return navArea === "content" && section === sec && contentRow === idx
  }

  function cycleArea(dir) {
    if (editing) commitEdit()
    navArea = dir >= 0
      ? (navArea === "sections" ? "content" : "sections")
      : (navArea === "content" ? "sections" : "content")
    if (navArea === "content") contentRow = 0
  }

  function moveCursor(dx, dy) {
    // While editing, arrows preview the value instead of moving the cursor.
    if (navArea === "content" && editing) {
      if (dy !== 0) adjustRow(dy)
      else if (dx !== 0) adjustRow(dx)
      return
    }
    if (navArea === "sections") {
      if (dy !== 0) {
        moveSelection(dy)
        return
      }
      if (dx > 0) {
        navArea = "content"
        contentRow = 0
      }
      return
    }
    if (dy !== 0) {
      // Clamp at both ends: the first and last row stay put.
      contentRow = Math.max(0, Math.min(navRows.length - 1, contentRow + dy))
      return
    }
    if (dx !== 0) adjustRow(dx)
  }

  // PageUp/PageDown jump to the previous/next section, clamped at the ends.
  function pageSection(dir) {
    moveSelection(dir)
    contentRow = 0
  }

  function activateCursor() {
    if (navArea !== "content") return
    // Interval time is a dropdown: open its real list, exactly like a click.
    // The popup then owns the keyboard (see `dropdownOpen`).
    if (navRows[contentRow] === "interval") { intervalField.open(); return }
    if (editing) { commitEdit(); return }
    if (adjustableRows.indexOf(navRows[contentRow]) >= 0) { startEdit(); return }
    activateRow()
  }

  function rowValue(key) {
    switch (key) {
    case "interval": return rotationInterval
    case "shuffle": return shuffleCount
    case "parallel": return parallelDownloads
    case "maxFiles": return maxLocalFiles
    case "maxDisk": return maxDiskGb
    }
    return null
  }

  function setRowValue(key, value) {
    switch (key) {
    case "interval": rotationInterval = value; break
    case "shuffle": shuffleCount = clampInt(value, 1, 50, shuffleCount); break
    case "parallel": parallelDownloads = clampInt(value, 1, 12, parallelDownloads); break
    case "maxFiles": maxLocalFiles = clampInt(value, 1000, 5000, maxLocalFiles); break
    case "maxDisk": maxDiskGb = clampInt(value, 1, 50, maxDiskGb); break
    }
  }

  function startEdit() {
    editing = true
    editingRow = contentRow
    editingOriginal = rowValue(navRows[contentRow])
  }

  function commitEdit() {
    editing = false
    editingRow = -1
    editingOriginal = null
  }

  function cancelEdit() {
    if (editing && editingOriginal !== null)
      setRowValue(navRows[editingRow], editingOriginal)
    editing = false
    editingRow = -1
    editingOriginal = null
  }

  function adjustRow(dir) {
    switch (navRows[contentRow]) {
    case "shuffle":
      shuffleCount = clampInt(shuffleCount + dir, 1, 50, shuffleCount); break
    case "parallel":
      parallelDownloads = clampInt(parallelDownloads + dir, 1, 12, parallelDownloads); break
    case "maxFiles":
      maxLocalFiles = clampInt(maxLocalFiles + dir * 100, 1000, 5000, maxLocalFiles); break
    case "maxDisk":
      maxDiskGb = clampInt(maxDiskGb + dir, 1, 50, maxDiskGb); break
    case "interval":
      cycleInterval(dir); break
    default:
      break
    }
  }

  function activateRow() {
    switch (navRows[contentRow]) {
    case "enabled": rotationEnabled = !rotationEnabled; break
    case "allTheme": rotationAllTheme = !rotationAllTheme; break
    case "random": rotationRandom = !rotationRandom; break
    case "interval": cycleInterval(1); break
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

  function cycleInterval(dir) {
    var i = intervalOptions.indexOf(rotationInterval)
    if (i < 0) i = 0
    i = (i + dir + intervalOptions.length) % intervalOptions.length
    rotationInterval = intervalOptions[i]
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
      themeDefaults: themeDefaults
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

  readonly property var intervalOptions: [1, 5, 15, 30, 60, 120]
  readonly property var intervalChoices: [
    { value: "1", label: "1 minute" },
    { value: "5", label: "5 minutes" },
    { value: "15", label: "15 minutes" },
    { value: "30", label: "30 minutes" },
    { value: "60", label: "1 hour" },
    { value: "120", label: "2 hours" }
  ]

  FileView {
    id: settingsFile

    path: setup.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: setup.load(text())
    onLoadFailed: setup.load("")
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", setup.settingsDir]
  }

  Timer {
    id: savedReset
    interval: 2000
    repeat: false
    onTriggered: setup.saved = false
  }

  Timer {
    id: autosaveTimer
    interval: 400
    repeat: false
    onTriggered: setup.save()
  }

  // `settingsPath` derives from the injected manifest, which can arrive after
  // this component is created: the first binding may point at the fallback
  // (official) path, whose failed load locks `settingsLoaded`. Reload from the
  // real path as soon as it is known.
  onSettingsPathChanged: {
    settingsLoaded = false
    Qt.callLater(function() { settingsFile.reload() })
  }

  Component.onCompleted: {
    if (setup.settingsDir !== "") mkdirProc.running = true
    Qt.callLater(function() { settingsFile.reload() })
  }

  // ---- left: roadmap (same column as Help) ---------------------------------
  Item {
    id: sidebar

    anchors.top: parent.top
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: setup.sidebarWidth > 0
      ? setup.sidebarWidth
      : Math.max(Style.space(210), Math.floor(parent.width * 0.26))

    RoadmapPane {
      anchors.fill: parent
      roadmap: setup.roadmap
      featureLabel: setup.featureLabel
      foreground: setup.foreground
      accent: setup.accent
      fontFamily: setup.fontFamily
      bodyPadY: setup.bodyPadY
      gutter: setup.gutter
      onFeatureClicked: setup.featureClicked()
    }

    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: 1
      color: Qt.rgba(setup.foreground.r, setup.foreground.g, setup.foreground.b, 0.12)
    }
  }

  // ---- right: section index -------------------------------------------------
  Item {
    id: indexPane

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: Math.max(Style.space(184),
      Math.floor(parent.width * 0.25) - Style.space(56))

    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: 1
      color: Qt.rgba(setup.foreground.r, setup.foreground.g, setup.foreground.b, 0.12)
    }

    Column {
      id: sectionNav

      anchors.top: parent.top
      anchors.topMargin: setup.bodyPadY
      anchors.left: parent.left
      anchors.leftMargin: gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.bottom: usagePane.top
      anchors.bottomMargin: Style.space(18)
      spacing: 0

      SectionTitle { text: "SECTIONS" }

      Column {
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: setup.sections

          delegate: Item {
            id: sectionEntry

            required property var modelData

            width: parent ? parent.width : 0
            height: entrySurface.height

            CursorSurface {
              id: entrySurface

              anchors.left: parent.left
              anchors.right: parent.right
              height: entryLabel.implicitHeight + Style.space(14)
              foreground: setup.foreground
              accent: setup.accent
              hasCursor: setup.section === sectionEntry.modelData.id

              Text {
                id: entryLabel

                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: sectionEntry.modelData.label
                color: setup.foreground
                font.family: setup.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              HoverHandler { cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: setup.selectSection(sectionEntry.modelData.id) }
            }

            // Accent ring on the highlighted section, so the keyboard cursor is
            // obvious while the SECTIONS column owns focus.
            BorderSurface {
              anchors.fill: entrySurface
              color: "transparent"
              radius: Style.cornerRadius
              borderSpec: Border.flat(setup.accent, Math.max(1, Style.normalBorderWidth))
              visible: setup.section === sectionEntry.modelData.id
            }
          }
        }
      }
    }

    // ---- usage: local files and disk space against the caps ----------------
    Column {
      id: usagePane

      anchors.left: parent.left
      anchors.leftMargin: gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.bottom: actionsPane.top
      anchors.bottomMargin: Style.space(18)
      spacing: 0

      SectionTitle { text: "USAGE" }

      Column {
        width: parent.width
        spacing: Style.space(10)

        UsageCard {
          width: parent.width
          label: "Local files"
          usedLabel: setup.grouped(setup.localFileCount)
          totalLabel: setup.grouped(setup.maxLocalFiles)
          percent: setup.usageFilePercent
        }

        UsageCard {
          width: parent.width
          label: "Disk space"
          usedLabel: (setup.localBytes / 1073741824).toFixed(1)
          totalLabel: setup.maxDiskGb.toFixed(1) + " GB"
          percent: setup.usageDiskPercent
        }
      }
    }

    // Actions: caption + the action buttons, at the bottom of the index column.
    Column {
      id: actionsPane

      anchors.left: parent.left
      anchors.leftMargin: gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: setup.bodyPadY
      spacing: 0

      SectionTitle { text: "ACTIONS" }

      // Restore defaults: same dashed treatment and height as the Help
      // sidebar's "Propose a feature".
      DashedButton {
        id: restoreButton

        width: parent.width
        text: "Restore defaults"
        foreground: setup.foreground
        accent: setup.accent
        fontFamily: setup.fontFamily
        onClicked: setup.restoreDefaults()
      }
    }
  }

  // ---- centre: content ------------------------------------------------------
  Flickable {
    id: contentFlick

    anchors.top: parent.top
    anchors.topMargin: setup.bodyPadY
    anchors.left: sidebar.right
    anchors.leftMargin: gutter
    anchors.right: indexPane.left
    anchors.rightMargin: gutter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: setup.bodyPadY
    contentWidth: width
    contentHeight: contentColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: contentColumn

      width: contentFlick.width
      spacing: Style.space(22)

      // ---- Download ---------------------------------------------------------
      Column {
        visible: setup.section === "download"
        width: parent.width
        spacing: Style.space(18)

        Text {
          textFormat: Text.PlainText
          text: "Download"
          color: setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          font.capitalization: Font.AllUppercase
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "These settings apply to every future installation. Wallpapers already downloaded are not touched at all."
          color: setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          lineHeightMode: Text.ProportionalHeight
        }

        Item {
          width: parent.width
          height: Math.max(resolutionText.height, resolutionGroup.height)

          Column {
            id: resolutionText

            anchors.left: parent.left
            anchors.right: resolutionGroup.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: resolutionLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Default resolution (coming soon)"
              color: setup.isRowFocused("download", 0) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Variant downloaded when a wallpaper is available in several formats. 2K ≈ 2 MB per image, 4K ≈ 8 MB, 8K ≈ 30 MB. If the chosen resolution does not exist, the highest available one is used."
            }
          }

          // Only 2K is wired up for now; 4K and 8K are shown disabled until
          // they are implemented (Ui/ButtonGroup has no per-option disabled
          // state, so this is a local row).
          Row {
            id: resolutionGroup

            anchors.right: parent.right
            anchors.top: parent.top
            // Match the NumberFields below: same overall width, chips evenly
            // split with a small gap.
            width: Style.spacing.numberFieldWidth
            spacing: Style.space(4)

            Repeater {
              model: [
                { value: "2k", label: "2K", available: true },
                { value: "4k", label: "4K", available: false },
                { value: "8k", label: "8K", available: false }
              ]

              delegate: Button {
                required property var modelData

                width: (resolutionGroup.width - resolutionGroup.spacing * 2) / 3
                horizontalPadding: Style.space(4)
                enabled: modelData.available
                opacity: enabled ? 1 : 0.4
                text: modelData.label
                selected: setup.resolution === modelData.value
                bordered: true
                foreground: setup.foreground
                background: setup.background
                accent: setup.accent
                fontFamily: setup.fontFamily
                onClicked: setup.resolution = modelData.value
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(shuffleText.height, shuffleField.height)

          Column {
            id: shuffleText

            anchors.left: parent.left
            anchors.right: shuffleField.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: shuffleLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Random wallpapers per theme"
              color: setup.isRowFocused("download", 1) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "How many wallpapers the Shuffle action installs for the selected theme (the Shuffle button or the f key). Range 1-50, default 5. A different random seed is used on every run."
            }
          }

          NumberField {
            id: shuffleField

            anchors.right: parent.right
            anchors.top: parent.top
            from: 1
            to: 50
            value: setup.shuffleCount
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { setup.shuffleCount = v }
          }
        }

        Item {
          width: parent.width
          height: Math.max(parallelText.height, parallelField.height)

          Column {
            id: parallelText

            anchors.left: parent.left
            anchors.right: parallelField.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: parallelLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Parallel downloads"
              color: setup.isRowFocused("download", 2) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "How many files are downloaded at the same time when installing. Range 1-12, default 8. Higher values are faster but heavier on the network and disk, and the remote server as well."
            }
          }

          NumberField {
            id: parallelField

            anchors.right: parent.right
            anchors.top: parent.top
            from: 1
            to: 12
            value: setup.parallelDownloads
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { setup.parallelDownloads = v }
          }
        }

        Item {
          width: parent.width
          height: Math.max(localFilesText.height, localFilesField.height)

          Column {
            id: localFilesText

            anchors.left: parent.left
            anchors.right: localFilesField.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: localFilesLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Max local files"
              color: setup.isRowFocused("download", 3) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Maximum number of wallpaper files kept on disk. The cap applies only to the bulk \"Install all\" action; installing single wallpapers by hand is always allowed, regardless of the cap."
            }
          }

          NumberField {
            id: localFilesField

            anchors.right: parent.right
            anchors.top: parent.top
            from: 1000
            to: 5000
            value: setup.maxLocalFiles
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { setup.maxLocalFiles = v }
          }
        }

        Item {
          width: parent.width
          height: Math.max(diskText.height, diskField.height)

          Column {
            id: diskText

            anchors.left: parent.left
            anchors.right: diskField.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: diskLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Max disk size (GB)"
              color: setup.isRowFocused("download", 4) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Maximum disk space used by installed wallpapers. The cap applies to the bulk \"Install all\" action and to Shuffle; installing wallpapers by hand is always allowed, regardless of the cap."
            }
          }

          NumberField {
            id: diskField

            anchors.right: parent.right
            anchors.top: parent.top
            from: 1
            to: 50
            value: setup.maxDiskGb
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { setup.maxDiskGb = v }
          }
        }
      }

      // ---- Rotation ---------------------------------------------------------
      Column {
        visible: setup.section === "rotation"
        width: parent.width
        spacing: Style.space(18)

        Text {
          textFormat: Text.PlainText
          text: "Automatic rotation"
          color: setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          font.capitalization: Font.AllUppercase
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Change the wallpaper automatically on a schedule, using the image files that are already installed locally on your system."
          color: setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          lineHeight: 1.25
          lineHeightMode: Text.ProportionalHeight
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Math.max(rotationText.implicitHeight, rotationControl.height)

            Column {
              id: rotationText

              anchors.left: parent.left
              anchors.right: rotationControl.left
              anchors.rightMargin: Style.space(16)
              anchors.top: parent.top
              spacing: Style.space(7)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Enable feature"
                color: setup.isRowFocused("rotation", 0) ? setup.accent : setup.foreground
                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                font.family: setup.fontFamily
                font.pixelSize: Style.font.subtitle
                font.capitalization: Font.AllUppercase
              }

              FieldHint {
                text: "Turns automatic rotation on or off. When enabled, the plugin changes the desktop background on its own at the interval below, using files that are already installed."
              }
            }

            // Same control column width as the Download inputs, so every row
            // lines up.
            Item {
              id: rotationControl

              width: Style.spacing.numberFieldWidth
              height: rotationSwitch.implicitHeight
              anchors.right: parent.right
              anchors.top: parent.top

              ToggleSwitch {
                id: rotationSwitch

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: setup.rotationEnabled
                foreground: setup.foreground
                accent: setup.accent
                onToggled: setup.rotationEnabled = !setup.rotationEnabled
              }
            }

            TapHandler { onTapped: setup.rotationEnabled = !setup.rotationEnabled }
          }
        }

        Item {
          width: parent.width
          height: Math.max(sourceText.height, sourceControl.height)

          Column {
            id: sourceText

            anchors.left: parent.left
            anchors.right: sourceControl.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: sourceLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Include theme wallpapers"
              color: setup.isRowFocused("rotation", 1) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Off: rotate only the wallpapers this plugin installed. On: rotate through every wallpaper bundled with the selected Omarchy theme, including the ones you did not download here."
            }
          }

          Item {
            id: sourceControl

            width: Style.spacing.numberFieldWidth
            height: sourceSwitch.implicitHeight
            anchors.right: parent.right
            anchors.top: parent.top

            ToggleSwitch {
              id: sourceSwitch

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: setup.rotationAllTheme
              foreground: setup.foreground
              accent: setup.accent
              onToggled: setup.rotationAllTheme = !setup.rotationAllTheme
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(randomText.height, randomControl.height)

          Column {
            id: randomText

            anchors.left: parent.left
            anchors.right: randomControl.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Random order"
              color: setup.isRowFocused("rotation", 2) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Sequential by default: wallpapers advance in the order they appear. When enabled, the next one is chosen at random, so the sequence feels less predictable and more varied over time."
            }
          }

          Item {
            id: randomControl

            width: Style.spacing.numberFieldWidth
            height: randomSwitch.implicitHeight
            anchors.right: parent.right
            anchors.top: parent.top

            ToggleSwitch {
              id: randomSwitch

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: setup.rotationRandom
              foreground: setup.foreground
              accent: setup.accent
              onToggled: setup.rotationRandom = !setup.rotationRandom
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(intervalText.height, intervalField.height)

          Column {
            id: intervalText

            anchors.left: parent.left
            anchors.right: intervalField.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              id: intervalLabel

              width: parent.width
              textFormat: Text.PlainText
              text: "Interval time"
              color: setup.isRowFocused("rotation", 3) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "How long each wallpaper stays on screen before the next one is picked. Short intervals change the background frequently; longer ones keep the current wallpaper for a while."
            }
          }

          Dropdown {
            id: intervalField

            anchors.right: parent.right
            anchors.top: parent.top
            width: Style.space(120)
            options: setup.intervalChoices
            value: String(setup.rotationInterval)
            foreground: setup.foreground
            background: setup.background
            accent: setup.accent
            fontFamily: setup.fontFamily
            onChanged: function(v) { setup.rotationInterval = parseInt(v) }
          }
        }

        // Manual trigger: run one rotation now, with the pool and order above.
        // Independent of the switch, so the feature can be tried out.
        Item {
          width: parent.width
          height: Math.max(rotateNowText.height, rotateNowButton.height)

          Column {
            id: rotateNowText

            anchors.left: parent.left
            anchors.right: rotateNowButton.left
            anchors.rightMargin: Style.space(16)
            anchors.top: parent.top
            spacing: Style.space(7)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Rotate now"
              color: setup.isRowFocused("rotation", 4) ? setup.accent : setup.foreground
              Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
              font.family: setup.fontFamily
              font.pixelSize: Style.font.subtitle
              font.capitalization: Font.AllUppercase
            }

            FieldHint {
              text: "Change the background immediately, using the pool and order above. It picks the next file just like a scheduled change. Works even when automatic rotation is off, so you can try it out."
            }
          }

          Button {
            id: rotateNowButton

            anchors.right: parent.right
            anchors.top: parent.top
            // Same width as the interval dropdown above, pinned so the label
            // swap ("Rotate now" / "Rotating…") never resizes it.
            width: Style.space(120)
            enabled: !setup.rotateBusy
            opacity: enabled ? 1 : 0.4
            text: setup.rotateBusy ? "Rotating…" : "Rotate now"
            iconText: "󰑓"
            bordered: true
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onClicked: setup.rotateRequested()
          }
        }
      }

    }
  }
}
