import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../components"
import "../js/Model.js" as Model

// Fullscreen preview of the selected wallpaper: the hi-res image cropped like
// the desktop, its installed/default state, a filmstrip navigator and the
// download / install / uninstall actions. The panel owns the state and the
// actions; this view renders them and calls back through `manager`.
Item {
  id: previewView

  // The panel root (state, models, processes and actions).
  required property var manager
  // Card insets, computed by the panel: the image and its overlays are
  // full-bleed, so they cancel the card padding themselves.
  property real cardLeftPadding: 0
  property real cardRightPadding: 0
  // Width of the rules (card width minus its borders).
  property real ruleWidth: 0
  // Height of the sibling footer, reserved at the bottom of the image frame.
  property real footerHeight: 0

  // Natural height of the header, so the panel can pin both heroes to it.
  readonly property real heroNaturalHeight: previewHero.implicitHeight

  // last source that failed to load, so the hero meta can report it
  property string failedSource: ""

  // target wallpaper, preloaded in background while the current one
  // stays up. Remote images come from the disk cache once resolved, so
  // stepping through the preview no longer re-downloads the 2K original.
  readonly property string nextSource: {
    var item = manager.currentItem()
    if (!item) return ""
    if (String(item.installed) === "1")
      return Util.fileUrl(manager.backgroundsDir + "/" + manager.themeName + "/" + item.filename)
    var cached = manager.cachedImagePath(item.url)
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
      source: manager.logoPath
      foreground: manager.foreground
      fontFamily: manager.fontFamily
    }
  }

  Component {
    id: previewActions

    Row {
      spacing: Style.spacing.controlGap

      Button {
        visible: manager.dev
        text: "DEV"
        iconText: "\uf121"
        bordered: true
        foreground: manager.accent
        accent: manager.accent
        fontFamily: manager.fontFamily
      }

      // Global store, same pill as the themes/wallpapers header.
      StorePill {
        controlHeight: previewDownloadButton.implicitHeight
        wallpapers: manager.globalCounts.wallpapers
        installed: manager.globalCounts.installed
        limitReason: manager.storageLimitReached ? manager.storageLimitReason : ""
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onLimitActivated: manager.openSetupDownload()
      }

      // Real image info ("2K | 2560x1440 | 0.3 MB"), standard colours,
      // styled like the store pill on the themes screen.
      BorderSurface {
        id: previewInfoPill

        visible: manager.currentResolution !== "" || manager.currentDimensions !== ""
          || manager.currentSize !== ""
        height: previewDownloadButton.implicitHeight
        width: infoRow.implicitWidth + leftPadding + rightPadding
        radius: Style.cornerRadius
        color: "transparent"
        borderSpec: Border.controlSpec("normal", manager.foreground, manager.accent)
        leftPadding: Style.spacing.controlPaddingX
        rightPadding: Style.spacing.controlPaddingX

        Row {
          id: infoRow
          anchors.centerIn: parent
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            visible: manager.currentResolution !== ""
            text: manager.currentResolution
            color: manager.foreground
            font.family: manager.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            visible: manager.currentResolution !== "" && manager.currentDimensions !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.normalBorderWidth)
            height: infoRow.implicitHeight
            color: Util.alpha(manager.foreground, 0.25)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            visible: manager.currentDimensions !== ""
            text: manager.currentDimensions
            color: manager.foreground
            font.family: manager.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            visible: manager.currentSize !== ""
              && (manager.currentResolution !== "" || manager.currentDimensions !== "")
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.normalBorderWidth)
            height: infoRow.implicitHeight
            color: Util.alpha(manager.foreground, 0.25)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            visible: manager.currentSize !== ""
            text: manager.currentSize
            color: manager.foreground
            font.family: manager.fontFamily
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
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onClicked: manager.actionDownloadOriginal()
      }

      Button {
        enabled: !actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Back"
        iconText: "󰁍"
        bordered: true
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onClicked: manager.closePreview()
      }

      Button {
        enabled: !actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Close"
        iconText: "✕"
        bordered: true
        foreground: manager.foreground
        accent: manager.accent
        fontFamily: manager.fontFamily
        onClicked: manager.close()
      }
    }
  }

  PanelHero {
    id: previewHero

    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: manager.heroHeight
    foreground: manager.foreground
    fontFamily: manager.fontFamily
    iconComponent: previewIcon
    trailingControl: previewActions
    // "Theme / Catppuccin / Preview": the file name below already
    // identifies the wallpaper, so the title stays short.
    title: ("Theme / " + Model.ucfirst(manager.themeName) + " / Preview").toUpperCase()
    // Second line: just the file name, middle-elided so the extension
    // and resolution at the end stay readable; resolution and size live
    // in the info pill on the right.
    meta: {
      var item = manager.currentItem()
      if (!item) return ""
      if (previewView.failed) return "failed to load"
      return Model.elideMiddle(item.filename, manager.fileNameMaxChars)
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
    anchors.leftMargin: -cardLeftPadding
    width: ruleWidth
    foreground: manager.foreground
  }

  Item {
    id: previewImageFrame

    // Attached to the rule above and the footer rule below: the image
    // fills the space between them.
    anchors.top: previewRule.bottom
    // Full-bleed but inside the border: cancel only the card padding so
    // the image touches the border's inner edge, which stays visible.
    anchors.left: parent.left
    anchors.leftMargin: -cardLeftPadding
    anchors.right: parent.right
    anchors.rightMargin: -cardRightPadding
    // Footer is a sibling of `previewView`, so it cannot be an anchor
    // target: reserve its height above the bottom instead, cancelling
    // the footer's own overlap so the image stays glued to its rule.
    anchors.bottom: parent.bottom
    anchors.bottomMargin: footerHeight - manager.footerOverlap
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
      anchors.rightMargin: cardRightPadding
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
        color: manager.currentInstalled
          ? manager.statusInstalled
          : Util.alpha(manager.foreground, 0.4)
      }
    }

    // "DEFAULT" pill, top-left over the image. Dark fill so the accent
    // text reads over any wallpaper (the plain outline alone washed out
    // on bright images).
    Pill {
      id: previewDefaultPill

      visible: manager.currentIsDefault
      anchors.top: parent.top
      anchors.topMargin: Style.space(12)
      anchors.left: parent.left
      anchors.leftMargin: cardLeftPadding
      width: implicitWidth
      height: implicitHeight
      label: "DEFAULT"
      glyph: "✓"
      tint: manager.accent
      fill: Util.alpha("#000000", 0.65)
      fontFamily: manager.fontFamily
    }

    // Destination path of the open wallpaper, bottom-left of the image.
    // Theme background fill (not pure black) with a border; vertically
    // centred with the filmstrip on the right. Shown whether or not the
    // file is installed.
    BorderSurface {
      id: previewPathPill

      anchors.left: parent.left
      anchors.leftMargin: manager.overlayInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: manager.overlayInset
      readonly property int padLeft: Style.space(14)
      readonly property int padRight: Style.space(32)

      width: Math.min(pathText.implicitWidth + padLeft + padRight,
        parent.width - cardLeftPadding - Style.space(12))
      // Same height as the filmstrip on the right, so the two overlays
      // read as one row; the path itself stays vertically centred.
      height: previewStrip.height
      radius: Style.cornerRadius
      color: Util.alpha(manager.background, manager.overlayFillAlpha)
      borderSpec: Border.flat(Util.alpha(manager.foreground, 0.22),
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
        text: Model.elideMiddle(manager.currentInstallPath, manager.pathMaxChars)
        color: manager.foreground
        font.family: manager.fontFamily
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
    running: manager.actionRunning
    label: manager.actionLabel
    foreground: manager.foreground
    background: manager.background
    accent: manager.accent
    fontFamily: manager.fontFamily
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
    anchors.bottomMargin: footerHeight - manager.footerOverlap
      + manager.overlayInset
    width: visibleCells * cellW + (visibleCells - 1) * previewStripList.spacing
      + contentLeftInset + contentRightInset
    height: cellH + contentTopInset + contentBottomInset
    radius: Style.cornerRadius
    color: Util.alpha(manager.background, manager.overlayFillAlpha)
    borderSpec: Border.flat(Util.alpha(manager.foreground, 0.18),
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
      model: manager.activeWallpapersModel
      currentIndex: manager.selectedIndex
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
            ? Util.fileUrl(manager.backgroundsDir + "/" + manager.themeName
              + "/" + stripCell.model.filename)
            : (stripCell.model.preview !== ""
              ? stripCell.model.preview : stripCell.model.url)
        }

        BorderSurface {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: previewStripList.currentIndex === stripCell.index
            ? Border.flat(manager.accent, Math.max(1, Style.normalBorderWidth))
            : Border.none()
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: {
            if (!manager.actionRunning) manager.takeCursor(stripCell.index)
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
      if (manager.actionRunning) return
      if (!previewView.onImage(point)) manager.closePreview()
    }
    onDoubleTapped: (point, button) => {
      if (manager.actionRunning) return
      if (previewView.onImage(point)) manager.actionToggleDefault()
    }
  }
}
