pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../components"
import "../js/Model.js" as Model

// Custom install screen: the theme's wallpapers previewed on the left (3x3
// thumbnails with the theme info overlaid at the bottom, like the themes
// detail pane), the install choices on the right — the whole theme, one
// collection each, a random sample, or "select only" to pick by hand. The panel
// owns the state and the actions; this view renders them and calls back through
// `manager`.
Item {
  id: customView

  // The panel root (state, models, processes and actions).
  required property var manager

  // Width of the previews pane, so the footer divider lines up with it.
  readonly property real paneWidth: leftPane.width

  Row {
    id: customRow

    anchors.fill: parent
    spacing: 0

    // ---- left: previews + theme info
    Item {
      id: leftPane

      width: Math.max(Style.space(260),
        Math.floor((customRow.width - customRow.spacing) * 0.62))
      height: parent.height
      clip: true

      // The pane split 3x3: each cell takes a third of the width and a third of
      // the height, and the image fills it "cover" (RoundedImage already uses
      // PreserveAspectCrop), so cells are not forced square and there are no
      // outer margins — only the gap between cells.
      Grid {
        id: previewGrid

        anchors.fill: parent
        columns: 3
        spacing: Style.space(6)

        readonly property real cellWidth: (leftPane.width - spacing * 2) / 3
        readonly property real cellHeight: (leftPane.height - spacing * 2) / 3

        Repeater {
          model: manager.customPreviews

          delegate: RoundedImage {
            required property string modelData

            width: previewGrid.cellWidth
            height: previewGrid.cellHeight
            // No rounding on the preview tiles.
            radius: 0
            source: modelData
          }
        }
      }

      // Uniform dark tint so the whole grid reads evenly and the overlaid info
      // stays legible wherever it sits.
      Rectangle {
        anchors.fill: parent
        color: Util.alpha(manager.background, 0.62)
      }

      // Soft band behind the info: more opaque than the tint, fading out at the
      // top and bottom so the text is legible without a hard edge.
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: infoColumn.height + Style.space(190)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(manager.background, 0.0) }
          GradientStop { position: 0.32; color: Util.alpha(manager.background, 0.88) }
          GradientStop { position: 0.68; color: Util.alpha(manager.background, 0.88) }
          GradientStop { position: 1.0; color: Util.alpha(manager.background, 0.0) }
        }
      }

      Column {
        id: infoColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Same inset as the hero title (card padding + icon + gap), symmetric,
        // so the info lines up with "CUSTOM INSTALL" above.
        anchors.leftMargin: manager.contentMargin + Style.font.displayLarge + Style.space(14)
        anchors.rightMargin: manager.contentMargin + Style.font.displayLarge + Style.space(14)
        // Same block spacing as the themes detail pane (palette / name / body).
        spacing: Style.space(22)

        // Palette first, above the name, like the themes detail pane.
        Row {
          spacing: Style.space(6)
          visible: paletteRepeater.count > 0

          Repeater {
            id: paletteRepeater
            model: Model.paletteList(manager.customTheme)

            delegate: Rectangle {
              required property string modelData

              width: Style.space(22)
              height: width
              radius: Math.max(2, Style.cornerRadius - Style.space(2))
              color: modelData
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: Util.alpha(manager.foreground, 0.25)
            }
          }
        }

        // Name and counts as one block, so the palette/title gap matches the
        // themes detail pane while the caption hugs the title.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: Model.themeLabel(manager.customTheme)
            color: manager.foreground
            font.family: manager.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              var theme = manager.customTheme
              if (!theme) return ""
              return (theme.collections || 0)
                + (theme.collections === 1 ? " collection · " : " collections · ")
                + (theme.count || 0) + " wallpapers · "
                + (theme.installed || 0) + " installed"
            }
            color: manager.foreground
            font.family: manager.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: manager.customTheme ? String(manager.customTheme.description || "") : ""
          color: manager.foreground
          font.family: manager.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
      }

      // Status captions live outside the centred info block, so appearing or
      // disappearing never shifts it. The catalog-loading caption lives on the
      // right pane, next to the option cards it gates.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: manager.contentMargin
        visible: !manager.customLoading && manager.customThemePresent === false
        textFormat: Text.PlainText
        text: "Theme not installed in Omarchy — install it first."
        color: manager.urgent
        font.family: manager.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    // Right rule of the preview column, continuing the other screens' divider.
    Rectangle {
      width: 1
      height: parent.height
      color: Qt.rgba(manager.foreground.r, manager.foreground.g,
        manager.foreground.b, 0.12)
    }

    // ---- right: install choices
    Item {
      id: rightPane

      width: customRow.width - leftPane.width - customRow.spacing - 1
      height: parent.height

      ListView {
        id: optionsList

        anchors.top: parent.top
        anchors.topMargin: manager.contentMargin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: manager.contentMargin
        anchors.rightMargin: manager.contentMargin
        anchors.bottom: switchCard.top
        anchors.bottomMargin: Style.space(16)
        clip: true
        spacing: Style.space(8)
        // Hidden until the catalog is in: rendering the list with only the
        // three catalog-independent cards made the collection cards pop in
        // later, shifting whatever the user was about to click.
        visible: manager.customCatalogReady
        model: manager.customRows
        currentIndex: Math.min(manager.customSelection, count - 1)
        onCurrentIndexChanged: if (currentIndex >= 0)
          positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
          id: optionCard

          required property var modelData
          required property int index

          width: optionsList.width
          height: Style.space(62)
          readonly property bool focused: manager.customRowFocused(index)
          property bool hovered: false

          function detailText() {
            var d = optionCard.modelData
            if (d.kind === "shuffle") return d.count + " random wallpapers"
            if (d.kind === "selectOnly") return d.hint
            var res = d.resolution !== ""
              ? String(d.resolution).toUpperCase()
              : String(manager.setupResolution).toUpperCase()
            var s = d.count + (d.count === 1 ? " wallpaper · " : " wallpapers · ") + res
            if (d.installed > 0) s += " · " + d.installed + " installed"
            return s
          }

          BorderSurface {
            anchors.fill: parent
            radius: Style.cornerRadius
            // Same fill language as the themes list: a dim plate at rest and
            // the shared hover-cursor fill on hover or selection.
            color: optionCard.focused || optionCard.hovered
              ? Style.hoverFillFor(manager.foreground, manager.accent)
              : Util.alpha(manager.foreground, 0.05)
            borderSpec: optionCard.focused
              ? Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
              : Border.none()
          }

          Rectangle {
            id: radioDot

            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, Style.normalBorderWidth)
            border.color: optionCard.focused
              ? manager.accent
              : Util.alpha(manager.foreground, 0.5)

            Rectangle {
              anchors.centerIn: parent
              width: Style.space(6)
              height: width
              radius: width / 2
              color: manager.accent
              visible: optionCard.focused
            }
          }

          Column {
            anchors.left: radioDot.right
            anchors.leftMargin: Style.space(12)
            anchors.right: sizeText.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: optionCard.modelData.label
              color: manager.foreground
              font.family: manager.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: optionCard.detailText()
              color: manager.dim
              font.family: manager.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Text {
            id: sizeText

            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: optionCard.modelData.sizeBytes > 0
              ? Model.formatSize(optionCard.modelData.sizeBytes) : ""
            color: manager.dim
            font.family: manager.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: optionCard.hovered = hovered
          }
          // A single click only moves the selection; Enter / Space / `i` or a
          // double click runs the choice.
          TapHandler {
            onTapped: manager.takeCustomCursor(index)
            onDoubleTapped: {
              manager.takeCustomCursor(index)
              manager.activateCustom()
            }
          }
        }
      }

      // Loading caption shown while the catalog is being read, so the pane
      // never flashes a partial set of option cards.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: !manager.customCatalogReady
        textFormat: Text.PlainText
        text: manager.customLoading ? "Loading catalog…" : "No wallpapers available."
        color: manager.dim
        font.family: manager.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // Default-at-end switch, pinned to the bottom of the column.
      Item {
        id: switchCard

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: manager.contentMargin
        anchors.rightMargin: manager.contentMargin
        // Standard margin before the footer separator line.
        anchors.bottomMargin: manager.contentMargin
        height: Style.space(58)
        readonly property bool focused: manager.customRowFocused(manager.customSwitchRow)
        property bool hovered: false

        BorderSurface {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: switchCard.focused || switchCard.hovered
            ? Style.hoverFillFor(manager.foreground, manager.accent)
            : Util.alpha(manager.foreground, 0.05)
          borderSpec: switchCard.focused
            ? Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
            : Border.none()
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.right: switchControl.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Set a random wallpaper as default when done"
          color: manager.foreground
          font.family: manager.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        ToggleSwitch {
          id: switchControl

          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          checked: manager.randomDefaultOnInstall
          foreground: manager.foreground
          accent: manager.accent
          onToggled: manager.toggleRandomDefaultOnInstall()
        }

        HoverHandler {
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: switchCard.hovered = hovered
        }
        TapHandler {
          onTapped: {
            manager.takeCustomCursor(manager.customSwitchRow)
            manager.toggleRandomDefaultOnInstall()
          }
        }
      }
    }
  }

  // Running overlay: freezes the screen while an install runs; only Esc cancels.
  RunningOverlay {
    anchors.fill: parent
    z: 6
    running: manager.actionRunning
    label: manager.actionLabel
    foreground: manager.foreground
    background: manager.background
    accent: manager.accent
    fontFamily: manager.fontFamily
  }
}
