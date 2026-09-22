import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../components"
import "../js/Model.js" as Model

// Wallpapers screen: the collection picker, search field and Select all/Clear
// row on top, then the lazy thumbnail grid of the open theme. Tiles carry the
// installed/default state and a selection checkbox; a tap opens the fullscreen
// preview. The panel owns the state and the actions; this view renders them and
// calls back through `manager`.
Item {
  id: wallpapersView

  // The panel root (state, models, processes and actions).
  required property var manager
  // x / width of the search-row rule, computed by the panel so it bleeds to the
  // card edges (this view is inset by the card padding).
  property real ruleX: 0
  property real ruleWidth: 0

  // Handles the panel drives directly: the grid (cursor scroll, column count)
  // and the collection popup (sync its value, open/close it from the keyboard).
  property alias grid: grid
  property alias collectionDropdown: collectionDropdown

  Item {
    id: wallpapersSearchRow

    visible: manager.view === "wallpapers"
    anchors.top: parent.top
    anchors.topMargin: manager.contentSpacing
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
      width: Math.max(Style.space(120), grid.cellWidth - manager.tileGap * 2)
      options: manager.collectionOptions
      value: manager.collectionFilter
      foreground: manager.foreground
      background: manager.background
      accent: manager.accent
      fontFamily: manager.fontFamily
      hasCursor: manager.view === "wallpapers" && manager.filterFocus === 0
      onChanged: function(v) {
        if (!manager.searching) manager.filterFocus = 0
        manager.setCollectionFilter(v)
      }
      // Taking the keyboard focus to open the popup (click or Enter) also
      // lands the row focus on the picker.
      onPopupOpenChanged: if (popupOpen && !manager.searching) manager.filterFocus = 0
    }

    // Accent ring on the focused filter-row control, same treatment as the
    // grid tiles and the Setup sidebar.
    BorderSurface {
      anchors.fill: collectionDropdown
      color: "transparent"
      radius: Style.cornerRadius
      borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
      visible: manager.view === "wallpapers" && manager.filterFocus === 0
    }

    // Selection helpers, reachable by keyboard (Left/Right from the
    // search field, Enter/Space to fire).
    Row {
      id: selectionActions

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      Button {
        text: "Select all"
        bordered: true
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onClicked: {
          if (!manager.searching) manager.filterFocus = 2
          manager.selectAllWallpapers()
        }

        BorderSurface {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
          visible: manager.view === "wallpapers" && manager.filterFocus === 2
        }
      }

      Button {
        text: "Clear"
        bordered: true
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onClicked: {
          if (!manager.searching) manager.filterFocus = 3
          manager.clearWallpaperSelection()
        }

        BorderSurface {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
          visible: manager.view === "wallpapers" && manager.filterFocus === 3
        }
      }
    }

    SearchField {
      id: wallpapersSearch

      anchors.left: collectionDropdown.right
      anchors.leftMargin: Style.space(12)
      anchors.right: selectionActions.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: manager.wallpaperFilterText
      placeholder: "Search wallpapers…"
      active: manager.searching
      foreground: manager.foreground
      accent: manager.accent
      fontFamily: manager.fontFamily
      onActivated: manager.startSearch()
      onCleared: manager.setWallpaperFilter("")
    }
  }

  // Rule between the search row and the grid. Same `contentSpacing` above
  // and below, so the search field sits centered between the hero rule and
  // this one.
  PanelSeparator {
    id: wallpapersSearchRule

    visible: manager.view === "wallpapers"
    anchors.top: wallpapersSearchRow.bottom
    anchors.topMargin: manager.contentSpacing
    anchors.left: parent.left
    anchors.leftMargin: ruleX
    width: ruleWidth
    foreground: manager.foreground
  }

  GridView {
    id: grid

    visible: manager.view === "wallpapers"
    anchors.top: wallpapersSearchRule.bottom
    anchors.topMargin: manager.contentSpacing
    anchors.left: parent.left
    anchors.right: parent.right
    // Cancel the outer `tileGap` so the first and last tiles line up with
    // the content edges of the rows above instead of sitting slightly
    // inside them.
    anchors.leftMargin: -manager.tileGap
    anchors.rightMargin: -manager.tileGap
    anchors.bottom: parent.bottom
    anchors.bottomMargin: manager.contentSpacing
    model: manager.activeWallpapersModel
    clip: true

    // Grid adapts to the card width: as many columns as fit while keeping
    // each tile at least ~190px wide (five columns on a regular screen).
    // Column count comes from the parent width so the negative margins
    // above cannot add a column.
    readonly property int columnsHint: Math.max(2, Math.floor(parent.width / manager.minTileWidth))
    readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
    cellWidth: Math.floor(width / columnsHint)
    // Thumbnail is 16:9 and fills the card; code + name overlay it, so no
    // extra strip is added and no space is wasted.
    cellHeight: Math.floor((cellWidth - manager.tileGap * 2 - manager.tileInset * 2) * 9 / 16)
      + manager.tileInset * 2 + manager.tileGap * 2

    delegate: Item {
      id: tile
      required property int index
      required property var model

      width: grid.cellWidth
      height: grid.cellHeight

      CursorSurface {
        id: tileCard

        anchors.fill: parent
        anchors.margins: manager.tileGap
        foreground: manager.foreground
        accent: manager.accent
        bordered: true
        hasCursor: manager.cursorActive && manager.view === "wallpapers" && manager.selectedIndex === tile.index
        // Persistent state: this is the open theme's default background
        // (live for the running theme, remembered otherwise).
        current: manager.isThemeDefault(tile.model)

        RoundedImage {
          id: preview
          anchors.fill: parent
          anchors.margins: manager.tileInset
          inset: manager.tileInset
          // Local file when already installed (instant), reduced remote
          // preview otherwise; fall back to the full-res URL if a preview
          // is missing. GridView only creates visible delegates, so
          // nearby tiles load lazily as you scroll.
          source: String(tile.model.installed) === "1"
            ? Util.fileUrl(manager.backgroundsDir + "/" + manager.themeName + "/" + tile.model.filename)
            : (tile.model.preview !== "" ? tile.model.preview : tile.model.url)
        }

        // Overlay label: translucent band at the bottom of the image so the
        // code + name stay readable without stealing a row from the grid.
        Rectangle {
          id: labelBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: manager.tileInset
          height: tileLabels.implicitHeight + Style.space(10)
          color: Util.alpha(manager.background, 0.7)
          bottomLeftRadius: Math.max(0, Style.cornerRadius - manager.tileInset)
          bottomRightRadius: Math.max(0, Style.cornerRadius - manager.tileInset)

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
              color: manager.accent
              font.family: manager.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              // Datasets mix cases (country names vs lowercase captions):
              // title-case each word so the grid reads consistently.
              text: Model.titleCase(tile.model.name)
              color: manager.foreground
              font.family: manager.fontFamily
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
          anchors.topMargin: manager.tileInset + Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: manager.tileInset + Style.space(8)
          width: disc
          height: disc
          radius: disc / 2
          color: Util.alpha(manager.background, 0.55)

          Rectangle {
            x: parent.ring
            y: parent.ring
            width: parent.disc - parent.ring * 2
            height: width
            radius: width / 2
            color: String(tile.model.installed) === "1"
              ? manager.statusInstalled
              : Util.alpha(manager.foreground, 0.4)
          }
        }

        // Selection checkbox, top-left of the thumbnail (the installed
        // disc is top-right, the DEFAULT pill centered). Shown on the
        // cursor tile so the mouse can reach it, and kept visible while
        // checked. Clicking it toggles the check (see the tile TapHandler);
        // Space does the same from the keyboard.
        Item {
          id: checkbox

          readonly property bool checked: manager.isWallpaperChecked(tile.model.filename)

          visible: checked || tileCard.hasCursor
          anchors.top: parent.top
          anchors.topMargin: manager.tileInset + Style.space(8)
          anchors.left: parent.left
          anchors.leftMargin: manager.tileInset + Style.space(8)
          width: Math.round(Math.max(Style.space(18),
            Math.min(Style.space(26), preview.width * 0.09)))
          height: width

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.space(5))
            color: checkbox.checked
              ? manager.accent
              : Util.alpha("#000000", 0.55)
            border.width: Math.max(1, Style.normalBorderWidth)
            border.color: checkbox.checked
              ? manager.accent
              : Util.alpha(manager.foreground, 0.75)

            Text {
              anchors.centerIn: parent
              visible: checkbox.checked
              text: "✓"
              color: manager.background
              font.family: manager.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }
        }

        // "DEFAULT" pill, centered on the thumbnail, on the theme's
        // default wallpaper (dark fill so the accent reads on any image).
        // The corners stay free for the selection checkbox.
        Pill {
          visible: manager.isThemeDefault(tile.model)
          anchors.centerIn: parent
          width: implicitWidth
          height: implicitHeight
          label: "DEFAULT"
          glyph: "✓"
          tint: manager.accent
          fill: Util.alpha("#000000", 0.65)
          fontFamily: manager.fontFamily
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
            ? Border.flat(manager.accent, Style.space(2))
            : Border.none()
        }

        HoverHandler {
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: if (hovered && manager.hoverArmed) manager.takeCursor(tile.index)
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
              manager.toggleWallpaperCheck(tile.model.filename)
              return
            }
            manager.takeCursor(tile.index)
            manager.showPreview()
          }
        }
      }
    }
  }
}
