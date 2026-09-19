import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

// Help screen: a three-column layout inside the card body. Left is the index
// (sections + topics) with the external resources and the "propose a feature"
// action pinned at the bottom; centre is the selected topic rendered from
// Markdown; right is the roadmap. All content is data: `help/index.json`,
// `help/roadmap.json` and one Markdown file per topic under `help/`.
//
// The parent owns the hero and the keyboard state machine and calls into
// `moveSelection` / `activateSelection`; this view only renders and reports.
Item {
  id: help

  property string helpRoot: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  // Project links from config.json (`repo`/`readme`/`issues`/`releases`), so
  // the Help resources and the feature button stay data-driven.
  property var links: ({})
  // Width of the themes screen's master pane, so the Help sidebar lines up
  // with it exactly (0 falls back to a local estimate).
  property real sidebarWidth: 0

  signal linkOpened()

  readonly property color dim: Qt.darker(foreground, 1.4)
  // Lateral breathing room between the three columns; a touch wider than the
  // other screens so the prose column does not feel cramped.
  readonly property int gutter: Style.space(28)
  // Standard body padding above and below every column, matching the gap the
  // themes screen keeps under the "Add remote source" button.
  readonly property int bodyPadY: Style.space(24)

  property var index: Model.emptyHelpIndex()
  // Injected by the panel: the roadmap data is loaded once there and shared
  // with Setup (see `RoadmapPane.qml`).
  property var roadmap: Model.parseRoadmap("")
  property var blocks: []
  property int selectedFlat: 0
  // Topic currently rendered in the centre. It lags behind `selectedFlat` when
  // the cursor sits on a resource, so the prev/next cards below keep steering
  // the content even while a reference is highlighted.
  property int contentTopic: 0
  property string selectedFile: ""

  readonly property var flatItems: Model.helpFlatItems(index)
  readonly property var sidebarEntries: Model.helpSidebarEntries(index)

  // The keyboard cursor walks the topics first and then the reference links, so
  // keyboard-only users can select a resource and open it with Enter.
  readonly property int topicCount: flatItems.length
  readonly property int resourceCount: index.resources ? index.resources.length : 0
  readonly property int navTotal: topicCount + resourceCount

  function selectFlat(target) {
    if (target < 0 || target >= navTotal) return
    selectedFlat = target
    // A resource keeps the last topic on screen; only topics load content.
    if (target >= topicCount) return
    contentTopic = target
    var item = flatItems[target]
    if (selectedFile !== item.file) {
      blocks = []
      selectedFile = item.file
    }
    Qt.callLater(positionNav)
  }

  function moveSelection(delta) {
    selectFlat(Math.max(0, Math.min(navTotal - 1, selectedFlat + delta)))
  }

  function activateSelection() {
    if (selectedFlat >= topicCount) {
      openUrl(linkFor(index.resources[selectedFlat - topicCount]))
      return
    }
    selectFlat(selectedFlat)
  }

  // PageUp/PageDown scroll the central topic content.
  function scrollPage(direction) {
    markdownView.pageBy(direction)
  }

  function positionNav() {
    if (selectedFlat >= topicCount) return
    var viewIndex = navViewIndex(selectedFlat)
    if (viewIndex >= 0) navList.positionViewAtIndex(viewIndex, ListView.Contain)
  }

  function navViewIndex(flat) {
    for (var i = 0; i < sidebarEntries.length; i++) {
      var entry = sidebarEntries[i]
      if (entry.type === "item" && entry.flat === flat) return i
    }
    return -1
  }

  function openUrl(url) {
    if (!url) return
    Qt.openUrlExternally(String(url))
    // The overlay sits in the wlr overlay layer, i.e. above a normal browser
    // window: hide it so the page is not trapped behind the panel.
    help.linkOpened()
  }

  // Resolve a resource/feature entry to a URL: `link` names a config.json link,
  // `url` is the literal fallback.
  function linkFor(entry) {
    if (!entry) return ""
    if (entry.link && help.links[entry.link]) return String(help.links[entry.link])
    return String(entry.url || "")
  }

  // Help keyboard shortcuts: `p` proposes a feature, `d` opens the raw database.
  function openFeature() {
    openUrl(linkFor(help.index.feature))
  }

  function openDatabase() {
    openUrl(help.links.database || "")
  }

  // Pick the first topic when none is selected yet. Called both when the index
  // lands and when the view becomes visible: `onIndexChanged` alone is not
  // enough because the `flatItems` binding may still be stale inside the
  // handler, and the index can already be loaded before Help is first opened.
  function ensureSelection() {
    if (selectedFile === "" && flatItems.length > 0) selectFlat(0)
  }

  onSelectedFlatChanged: Qt.callLater(positionNav)
  // The index is injected by the panel (loaded once, shared with Setup). Pick
  // the first topic as soon as it lands.
  onIndexChanged: Qt.callLater(ensureSelection)
  onVisibleChanged: if (visible) ensureSelection()

  // ---- data ----------------------------------------------------------------
  FileView {
    id: contentFile

    path: help.helpRoot && help.selectedFile
      ? help.helpRoot + "/" + help.selectedFile : ""
    watchChanges: false
    printErrors: false
    onLoaded: help.blocks = Model.parseMarkdown(text())
    onLoadFailed: help.blocks = []
  }

  // ---- left: roadmap --------------------------------------------------------
  Item {
    id: sidebar

    anchors.top: parent.top
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: help.sidebarWidth > 0
      ? help.sidebarWidth
      : Math.max(Style.space(210), Math.floor(parent.width * 0.26))

    RoadmapPane {
      anchors.fill: parent
      roadmap: help.roadmap
      featureLabel: help.index.feature ? help.index.feature.title : ""
      foreground: help.foreground
      accent: help.accent
      fontFamily: help.fontFamily
      bodyPadY: help.bodyPadY
      gutter: help.gutter
      onFeatureClicked: help.openUrl(help.linkFor(help.index.feature))
    }

    Rectangle {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: 1
      color: Qt.rgba(help.foreground.r, help.foreground.g, help.foreground.b, 0.12)
    }
  }

  // ---- right: index + resources --------------------------------------------
  Item {
    id: roadmapPane

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
      color: Qt.rgba(help.foreground.r, help.foreground.g, help.foreground.b, 0.12)
    }

    ListView {
      id: navList

      anchors.top: parent.top
      anchors.topMargin: help.bodyPadY
      anchors.left: parent.left
      anchors.leftMargin: gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.bottom: sidebarFooter.top
      anchors.bottomMargin: help.bodyPadY
      clip: true
      spacing: Style.space(2)
      model: help.sidebarEntries

      delegate: Item {
        id: navEntry

        required property var modelData
        required property int index

        readonly property bool isSection: modelData.type === "section"
        // The first section label sits flush with the top; later sections get
        // a little air above them.
        readonly property int sectionTopGap: index === 0 ? 0 : Style.space(12)

        width: navList.width
        height: isSection
          ? sectionTopGap + sectionLabel.implicitHeight + Style.space(10)
          : itemSurface.height

        Text {
          id: sectionLabel

          visible: navEntry.isSection
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.topMargin: navEntry.sectionTopGap
          textFormat: Text.PlainText
          text: navEntry.isSection ? navEntry.modelData.title : ""
          color: help.dim
          font.family: help.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        CursorSurface {
          id: itemSurface

          visible: !navEntry.isSection
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: itemLabel.implicitHeight + Style.space(14)
          foreground: help.foreground
          accent: help.accent
          hasCursor: !navEntry.isSection && navEntry.modelData.flat === help.selectedFlat

          Text {
            id: itemLabel

            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: navEntry.isSection ? "" : navEntry.modelData.title
            color: help.foreground
            font.family: help.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: if (!navEntry.isSection) help.selectFlat(navEntry.modelData.flat)
          }
        }

        // Accent ring on the selected topic, matching the Setup screen's
        // SECTIONS column, so the cursor is obvious in the index.
        BorderSurface {
          anchors.fill: itemSurface
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: Border.flat(help.accent, Math.max(1, Style.normalBorderWidth))
          visible: !navEntry.isSection && navEntry.modelData.flat === help.selectedFlat
        }
      }
    }

    Column {
      id: sidebarFooter

      anchors.left: parent.left
      anchors.leftMargin: gutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: help.bodyPadY
      spacing: Style.space(10)

      Column {
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "RESOURCES"
          color: help.dim
          font.family: help.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          // Match the gap the nav section labels leave under themselves.
          bottomPadding: Style.space(2)
        }

        Repeater {
          model: help.index.resources

          delegate: Item {
            id: resourceRow

            required property var modelData
            required property int index

            // The keyboard cursor continues past the topics into the resources.
            // A resource is compact like before: no surface, no border, only the
            // label and the arrow turn accent when selected or hovered.
            readonly property bool selected: help.selectedFlat === help.topicCount + index

            width: sidebarFooter.width
            height: resourceLabel.implicitHeight

            Text {
              id: resourceLabel

              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: resourceArrow.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: resourceRow.modelData.title
              color: (resourceHover.hovered || resourceRow.selected)
                ? help.accent : help.foreground
              font.family: help.fontFamily
              font.pixelSize: Style.font.body
              font.capitalization: Font.AllUppercase
              elide: Text.ElideRight
            }

            Text {
              id: resourceArrow

              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "↗"
              color: (resourceHover.hovered || resourceRow.selected)
                ? help.accent : help.dim
              font.family: help.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            HoverHandler {
              id: resourceHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              onTapped: help.openUrl(help.linkFor(resourceRow.modelData))
            }
          }
        }
      }
    }
  }

  // ---- centre: topic content ------------------------------------------------
  Item {
    id: contentPane

    anchors.top: parent.top
    anchors.topMargin: help.bodyPadY
    anchors.left: sidebar.right
    anchors.leftMargin: gutter
    anchors.right: roadmapPane.left
    anchors.rightMargin: gutter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: help.bodyPadY

    // The prev/next cards steer the topic in the centre, not the cursor: while a
    // resource is highlighted the cards keep pointing at the displayed topic.
    readonly property int prevIndex: help.contentTopic - 1
    readonly property int nextIndex: help.contentTopic + 1
    readonly property bool hasPrev: prevIndex >= 0
    readonly property bool hasNext: nextIndex < help.topicCount
    readonly property real navHalf: (width - Style.space(14)) / 2

    MarkdownView {
      id: markdownView

      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: topicNav.top
      anchors.bottomMargin: Style.space(18)
      blocks: help.blocks
      foreground: help.foreground
      accent: help.accent
      fontFamily: help.fontFamily
    }

    // Previous / next topic: two bordered cards mirroring each other, so the
    // whole guide can be walked from the bottom of any topic.
    Row {
      id: topicNav

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(14)

      BorderSurface {
        id: navPrev

        visible: contentPane.hasPrev
        width: contentPane.hasNext ? contentPane.navHalf : contentPane.width
        // Same control height as the "Propose a feature" dashed button.
        height: Style.space(36)
        padding: Style.space(12)
        radius: Style.cornerRadius
        color: prevHover.hovered
          ? Style.hoverFillFor(help.foreground, help.accent) : "transparent"
        borderSpec: Border.flat(Util.alpha(help.foreground, 0.14),
          Math.max(1, Style.normalBorderWidth))

        Item {
          id: prevRow

          anchors.left: parent.left
          anchors.leftMargin: navPrev.contentLeftInset
          anchors.right: parent.right
          anchors.rightMargin: navPrev.contentRightInset
          anchors.verticalCenter: parent.verticalCenter
          height: prevTitle.implicitHeight

          Text {
            id: prevArrow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "←"
            color: help.dim
            font.family: help.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: prevTitle

            anchors.left: prevArrow.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: contentPane.hasPrev
              ? help.flatItems[contentPane.prevIndex].title : ""
            color: help.foreground
            font.family: help.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }
        }

        HoverHandler { id: prevHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: if (contentPane.hasPrev) help.selectFlat(contentPane.prevIndex)
        }
      }

      BorderSurface {
        id: navNext

        visible: contentPane.hasNext
        width: contentPane.hasPrev ? contentPane.navHalf : contentPane.width
        // Same control height as the "Propose a feature" dashed button.
        height: Style.space(36)
        padding: Style.space(12)
        radius: Style.cornerRadius
        color: nextHover.hovered
          ? Style.hoverFillFor(help.foreground, help.accent) : "transparent"
        borderSpec: Border.flat(Util.alpha(help.foreground, 0.14),
          Math.max(1, Style.normalBorderWidth))

        Item {
          id: nextRow

          anchors.left: parent.left
          anchors.leftMargin: navNext.contentLeftInset
          anchors.right: parent.right
          anchors.rightMargin: navNext.contentRightInset
          anchors.verticalCenter: parent.verticalCenter
          height: nextTitle.implicitHeight

          Text {
            id: nextArrow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "→"
            color: help.dim
            font.family: help.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: nextTitle

            anchors.left: parent.left
            anchors.right: nextArrow.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: contentPane.hasNext
              ? help.flatItems[contentPane.nextIndex].title : ""
            color: help.foreground
            font.family: help.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
          }
        }

        HoverHandler { id: nextHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: if (contentPane.hasNext) help.selectFlat(contentPane.nextIndex)
        }
      }
    }
  }
}
