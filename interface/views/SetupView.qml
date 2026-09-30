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
  // Persistent settings object created by the panel. Kept out of this view so
  // the Setup screen can be destroyed and rebuilt without losing the values.
  required property var settings

  // Injected by the panel: a rotate is in flight, so "Rotate now" is disabled.
  property bool rotateBusy: false

  // ---- usage (right sidebar) ----------------------------------------------
  // Live local usage injected by the panel, shown against the caps.
  property int localFileCount: 0
  property real localBytes: 0

  readonly property int usageFilePercent: settings.maxLocalFiles > 0
    ? Math.min(100, Math.round(localFileCount / settings.maxLocalFiles * 100)) : 0
  readonly property int usageDiskPercent: settings.maxDiskGb > 0
    ? Math.min(100, Math.round(localBytes / (settings.maxDiskGb * 1073741824) * 100)) : 0

  // Uniform bottom margin under every sidebar section title (SECTIONS / USAGE /
  // ACTIONS), so they all breathe the same.
  readonly property int sectionTitleGap: Style.space(10)

  // Thousands separator for the big counters ("1,000").
  function grouped(n) {
    var s = String(Math.max(0, Math.round(Number(n) || 0)))
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }

  // ---- per-theme default wallpaper -----------------------------------------
  // `themeDefault` / `setThemeDefault` / `clearThemeDefault` live in Settings.

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

  // The popup is a top-level overlay: the panel closes it when the Setup
  // screen is left so it cannot float over the next view.
  function closeDropdown() {
    if (intervalField.popupOpen) intervalField.close()
  }

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
    case "interval": return settings.rotationInterval
    case "shuffle": return settings.shuffleCount
    case "parallel": return settings.parallelDownloads
    case "maxFiles": return settings.maxLocalFiles
    case "maxDisk": return settings.maxDiskGb
    }
    return null
  }

  function setRowValue(key, value) {
    switch (key) {
    case "interval": settings.rotationInterval = value; break
    case "shuffle": settings.shuffleCount = settings.clampInt(value, 1, 50, settings.shuffleCount); break
    case "parallel": settings.parallelDownloads = settings.clampInt(value, 1, 12, settings.parallelDownloads); break
    case "maxFiles": settings.maxLocalFiles = settings.clampInt(value, 1000, 5000, settings.maxLocalFiles); break
    case "maxDisk": settings.maxDiskGb = settings.clampInt(value, 1, 50, settings.maxDiskGb); break
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
      settings.shuffleCount = settings.clampInt(settings.shuffleCount + dir, 1, 50, settings.shuffleCount); break
    case "parallel":
      settings.parallelDownloads = settings.clampInt(settings.parallelDownloads + dir, 1, 12, settings.parallelDownloads); break
    case "maxFiles":
      settings.maxLocalFiles = settings.clampInt(settings.maxLocalFiles + dir * 100, 1000, 5000, settings.maxLocalFiles); break
    case "maxDisk":
      settings.maxDiskGb = settings.clampInt(settings.maxDiskGb + dir, 1, 50, settings.maxDiskGb); break
    case "interval":
      cycleInterval(dir); break
    default:
      break
    }
  }

  function activateRow() {
    switch (navRows[contentRow]) {
    case "enabled": settings.rotationEnabled = !settings.rotationEnabled; break
    case "allTheme": settings.rotationAllTheme = !settings.rotationAllTheme; break
    case "random": settings.rotationRandom = !settings.rotationRandom; break
    case "interval": cycleInterval(1); break
    case "rotateNow":
      if (!rotateBusy) rotateRequested(); break
    case "shuffle":
      settings.shuffleCount = settings.clampInt(settings.shuffleCount + 1, 1, 50, settings.shuffleCount); break
    case "parallel":
      settings.parallelDownloads = settings.clampInt(settings.parallelDownloads + 1, 1, 12, settings.parallelDownloads); break
    case "maxFiles":
      settings.maxLocalFiles = settings.clampInt(settings.maxLocalFiles + 100, 1000, 5000, settings.maxLocalFiles); break
    case "maxDisk":
      settings.maxDiskGb = settings.clampInt(settings.maxDiskGb + 1, 1, 50, settings.maxDiskGb); break
    default:
      break
    }
  }

  function cycleInterval(dir) {
    var i = settings.intervalOptions.indexOf(settings.rotationInterval)
    if (i < 0) i = 0
    i = (i + dir + settings.intervalOptions.length) % settings.intervalOptions.length
    settings.rotationInterval = settings.intervalOptions[i]
  }

  // load / serialize / scheduleSave / save / restoreDefaults live in Settings.

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
          totalLabel: setup.grouped(settings.maxLocalFiles)
          percent: setup.usageFilePercent
        }

        UsageCard {
          width: parent.width
          label: "Disk space"
          usedLabel: (setup.localBytes / 1073741824).toFixed(1)
          totalLabel: settings.maxDiskGb.toFixed(1) + " GB"
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
        onClicked: settings.restoreDefaults()
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
                selected: settings.resolution === modelData.value
                bordered: true
                foreground: setup.foreground
                background: setup.background
                accent: setup.accent
                fontFamily: setup.fontFamily
                onClicked: settings.resolution = modelData.value
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
            value: settings.shuffleCount
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { settings.shuffleCount = v }
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
            value: settings.parallelDownloads
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { settings.parallelDownloads = v }
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
            value: settings.maxLocalFiles
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { settings.maxLocalFiles = v }
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
            value: settings.maxDiskGb
            foreground: setup.foreground
            accent: setup.accent
            fontFamily: setup.fontFamily
            onModified: function(v) { settings.maxDiskGb = v }
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
                checked: settings.rotationEnabled
                foreground: setup.foreground
                accent: setup.accent
                onToggled: settings.rotationEnabled = !settings.rotationEnabled
              }
            }

            TapHandler { onTapped: settings.rotationEnabled = !settings.rotationEnabled }
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
              checked: settings.rotationAllTheme
              foreground: setup.foreground
              accent: setup.accent
              onToggled: settings.rotationAllTheme = !settings.rotationAllTheme
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
              text: "Sequential by default: wallpapers advance in the order they appear and resume where they left off after a theme switch. When enabled, the next one is drawn from a shuffled pool that never repeats a wallpaper until all of them have been shown, then a new cycle starts."
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
              checked: settings.rotationRandom
              foreground: setup.foreground
              accent: setup.accent
              onToggled: settings.rotationRandom = !settings.rotationRandom
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
            options: settings.intervalChoices
            value: String(settings.rotationInterval)
            foreground: setup.foreground
            background: setup.background
            accent: setup.accent
            fontFamily: setup.fontFamily
            onChanged: function(v) { settings.rotationInterval = parseInt(v) }
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
