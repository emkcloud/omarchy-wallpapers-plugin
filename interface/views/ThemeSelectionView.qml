import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Commons
import qs.Ui
import "../components"
import "../js/Model.js" as Model

// Theme selection screen (master-detail): the vertical list of remote themes on
// the left, the selected theme's preview, palette, description and bulk actions
// on the right. One shared cursor drives the list highlight and the detail pane
// for mouse and keyboard alike. The panel owns the state and the actions; this
// view renders them and calls back through `manager`.
Item {
  id: themesView

  // The panel root (state, models, processes and actions).
  required property var manager
  // Mirrors the Setup screen's shuffle count, used by the bulk Shuffle action.
  property int shuffleCount: 5

  // Width of the master pane: the Help/Setup sidebars and the footer dividers
  // reuse it so every vertical rule lines up.
  readonly property real paneWidth: themeListPane.width
  // The master ListView, exposed so the panel can keep the cursor row in view
  // (the panel owns `selectedIndex`, the view owns the list).
  property alias listView: themesList

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
        anchors.rightMargin: manager.contentMargin
        text: manager.filterText
        placeholder: "Search themes…"
        active: manager.searching
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onActivated: manager.startSearch()
        onCleared: manager.setThemeFilter("")
      }

      ListView {
        id: themesList

        anchors.top: searchBar.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: manager.contentMargin
        anchors.bottom: addSource.top
        anchors.bottomMargin: manager.contentSpacing
        clip: true
        spacing: Style.space(4)
        model: manager.activeThemesModel

        delegate: Item {
          id: themeRow
          required property int index
          required property var model

          // Mouse hover only lights the plate up; it never moves the
          // current theme. Clicking confirms the selection.
          property bool hovered: false

          width: themesList.width
          height: manager.themeRowHeight

          // Dark row plate, slightly lifted off the card, as in the
          // mockup. The CursorSurface paints the cursor/selected fill on
          // top of it.
          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            // Hover lightens the plate only; the CursorSurface still
            // paints the actual cursor/selected fill on top.
            color: themeRow.hovered
              ? Style.hoverFillFor(manager.foreground, manager.accent)
              : Util.alpha(manager.foreground, 0.05)
          }

          CursorSurface {
            id: themeRowCard

            anchors.fill: parent
            foreground: manager.foreground
            accent: manager.accent
            hasCursor: manager.cursorActive && manager.view === "themes"
              && manager.selectedIndex === themeRow.index

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
                color: manager.foreground
                font.family: manager.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: Model.themeStatusLabel(themeRow.model)
                color: manager.dim
                font.family: manager.fontFamily
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
                if (manager.busy && manager.actionTheme === themeRow.model.name)
                  return manager.statusInstalling
                var state = Model.themeState(themeRow.model)
                if (state === "installed") return manager.statusInstalled
                if (state === "partial") return manager.statusInstalling
                return Util.alpha(manager.foreground, 0.25)
              }
            }

            // Accent ring on the selected row: same treatment as the
            // wallpaper tiles (the kit's cursor border reads faint).
            BorderSurface {
              anchors.fill: parent
              color: "transparent"
              radius: Style.cornerRadius
              borderSpec: themeRowCard.hasCursor
                ? Border.flat(manager.accent, Style.space(2))
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
              onTapped: manager.takeCursor(themeRow.index)
              onDoubleTapped: {
                manager.takeCursor(themeRow.index)
                manager.selectTheme(themeRow.index)
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
        anchors.rightMargin: manager.contentMargin
        visible: manager.filterText !== "" && manager.activeThemesModel.count === 0
        textFormat: Text.PlainText
        text: "No matches for “" + manager.filterText + "”"
        color: manager.dim
        font.family: manager.fontFamily
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
        anchors.rightMargin: manager.contentMargin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(24)
        height: manager.actionButtonHeight

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
            strokeColor: manager.dim
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
          text: manager.addSourceSoon ? "COMING SOON (◕‿◕)" : "+ Add remote source"
          color: manager.addSourceSoon ? manager.accent : manager.dim
          font.family: manager.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: manager.triggerAddSource()
        }

        Timer {
          id: addSourceReset
          interval: 3000
          onTriggered: manager.addSourceSoon = false
        }
      }

      // Right rule of the master column, with the content padded off it.
      Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: Qt.rgba(manager.foreground.r, manager.foreground.g, manager.foreground.b, 0.12)
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
        onDoubleTapped: manager.selectTheme(manager.selectedIndex)
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
        source: manager.detailBackdrop
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
        source: manager.detailImageShown
        sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)),
          Math.max(1, Math.ceil(height * 2)))
        onStatusChanged: if (status === Image.Ready && source !== "")
          manager.detailBackdrop = source
      }

      // Dark gradient so the palette, name and description stay legible
      // over the wallpaper.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(manager.background, 0.0) }
          GradientStop { position: 0.45; color: Util.alpha(manager.background, 0.3) }
          GradientStop { position: 0.75; color: Util.alpha(manager.background, 0.85) }
          GradientStop { position: 1.0; color: manager.background }
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
            model: Model.paletteList(manager.selectedTheme)

            delegate: Rectangle {
              required property string modelData

              width: Style.space(26)
              height: width
              radius: Math.max(2, Style.cornerRadius - Style.space(2))
              color: modelData
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: Util.alpha(manager.foreground, 0.25)
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
            text: Model.themeLabel(manager.selectedTheme)
            color: manager.foreground
            font.family: manager.fontFamily
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
              var theme = manager.selectedTheme
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
            color: manager.dim
            font.family: manager.fontFamily
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
              text: "Browse " + (manager.selectedTheme ? manager.selectedTheme.count : "")
              iconText: "󰉖"
              height: manager.actionButtonHeight
              bordered: false
              background: Util.alpha(manager.foreground, 0.12)
              foreground: manager.foreground
              accent: manager.accent
              fontFamily: manager.fontFamily
              onClicked: manager.selectTheme(manager.selectedIndex)

              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
                visible: manager.themeActionFocused("browse")
              }
            }

            Button {
              visible: manager.selectedThemePresent
              enabled: !manager.actionRunning && !manager.selectedThemeFull
                && !manager.storageLimitReached
              opacity: enabled ? 1 : 0.4
              text: "Install (ALL)"
              iconText: "󰮏"
              height: manager.actionButtonHeight
              bordered: true
              foreground: manager.foreground
              accent: manager.accent
              fontFamily: manager.fontFamily
              onClicked: manager.actionInstallTheme()

              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
                visible: manager.themeActionFocused("install")
              }
            }

            Button {
              visible: manager.selectedThemePresent
              enabled: !manager.actionRunning && !manager.selectedThemeFull
                && !manager.storageLimitReached
              opacity: enabled ? 1 : 0.4
              text: "Shuffle (" + shuffleCount + ")"
              iconText: "󰮏"
              height: manager.actionButtonHeight
              bordered: true
              foreground: manager.foreground
              accent: manager.accent
              fontFamily: manager.fontFamily
              onClicked: manager.actionRandomInstall()

              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
                visible: manager.themeActionFocused("shuffle")
              }
            }

            Button {
              visible: manager.selectedThemePresent
              enabled: !manager.actionRunning && !manager.selectedThemeEmpty
              opacity: enabled ? 1 : 0.4
              text: "Uninstall"
              iconText: "󰱢"
              height: manager.actionButtonHeight
              bordered: true
              foreground: manager.foreground
              accent: manager.accent
              fontFamily: manager.fontFamily
              onClicked: manager.actionRemoveThemeAll()

              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
                visible: manager.themeActionFocused("uninstall")
              }
            }

            // Custom Install: opens the dedicated screen (whole theme, one
            // collection, shuffle or pick by hand). Always clickable.
            Button {
              text: "Custom Install"
              iconText: "󰒓"
              height: manager.actionButtonHeight
              bordered: true
              foreground: manager.foreground
              accent: manager.accent
              fontFamily: manager.fontFamily
              onClicked: manager.openCustomInstall()

              BorderSurface {
                anchors.fill: parent
                color: "transparent"
                radius: Style.cornerRadius
                borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
                visible: manager.themeActionFocused("custom")
              }
            }

            // The Omarchy theme is not installed: installing its
            // wallpapers is impossible, so show a non-interactive
            // info badge (no hover, no tooltip, no action).
            BorderSurface {
              visible: !manager.selectedThemePresent
              width: badgeRow.implicitWidth + leftPadding + rightPadding
              height: manager.actionButtonHeight
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.controlSpec("normal", manager.foreground, manager.accent)
              leftPadding: Style.spacing.controlPaddingX
              rightPadding: Style.spacing.controlPaddingX

              Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: Style.spacing.controlGap

                Text {
                  textFormat: Text.PlainText
                  text: "󰀪"
                  color: manager.foreground
                  font.family: manager.fontFamily
                  font.pixelSize: Style.font.icon
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "Theme not found"
                  color: manager.foreground
                  font.family: manager.fontFamily
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
    running: manager.actionRunning
    label: manager.actionLabel
    foreground: manager.foreground
    background: manager.background
    accent: manager.accent
    fontFamily: manager.fontFamily
  }
}
