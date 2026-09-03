import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by omarchy-shell.
  property var manifest: null
  readonly property string pluginDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : ""

  readonly property string scriptPath: {
    var p = pluginDir
    return p ? p.replace(/\/$/, "") + "/manager.sh" : "manager.sh"
  }

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  property string view: "themes"          // "themes" | "wallpapers"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  property bool busy: false
  property string statusText: ""

  // ---- theme colors ---------------------------------------------------------
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Color.muted
  readonly property color cardBackground: Color.popups.background
  readonly property color cardBorder: Color.popups.border
  readonly property color scrim: Util.alpha(Color.background, 0.78)
  readonly property color barFill: Util.alpha(Color.foreground, 0.12)
  readonly property color tileFill: Util.alpha(Color.foreground, 0.10)
  readonly property color tileBorder: Util.alpha(Color.foreground, 0.30)
  readonly property int minTileWidth: Style.space(190)
  readonly property string fontFamily: Style.font.family

  ListModel { id: themesModel }
  ListModel { id: wallpapersModel }

  // ---- rounded thumbnail ----------------------------------------------------
  // Thumbnails must follow the window-manager rounding: `Style.cornerRadius`
  // mirrors Hyprland's `decoration:rounding` (the shell re-reads it on startup
  // and on theme change), so changing `rounding` in looknfeel.lua is picked up
  // here too. `clip: true` on an Image only clips rectangularly, hence the
  // MultiEffect mask.
  //
  // `inset` is the distance from the parent card's edge: concentric-radii rule
  // (`r_inner = r_outer - gap`) keeps the padding visually uniform. Tiles use
  // `inset: 0` (image flush to the card) and round only the top corners, so the
  // thumbnail radius is exactly the card radius.
  component RoundedImage: Item {
    id: roundedImage

    property alias source: roundedImageSource.source
    property alias status: roundedImageSource.status
    property alias fillMode: roundedImageSource.fillMode
    property int inset: 0
    property int radius: Math.max(0, Style.cornerRadius - inset)
    property int topRadius: radius
    property int bottomRadius: radius

    Rectangle {
      id: roundedImageMask
      anchors.fill: parent
      visible: false
      layer.enabled: true
      color: "white"
      topLeftRadius: roundedImage.topRadius
      topRightRadius: roundedImage.topRadius
      bottomLeftRadius: roundedImage.bottomRadius
      bottomRightRadius: roundedImage.bottomRadius
    }

    Item {
      anchors.fill: parent
      layer.enabled: roundedImage.topRadius > 0 || roundedImage.bottomRadius > 0
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: roundedImageMask
      }

      Image {
        id: roundedImageSource
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 512
      }
    }
  }

  // ---- lifecycle ------------------------------------------------------------
  function open(payload) {
    opened = true
    view = "themes"
    selectedIndex = 0
    statusText = ""
    loadThemes()
  }

  function close() {
    opened = false
  }

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

  function selectTheme(index) {
    if (index < 0 || index >= themesModel.count) return
    var item = themesModel.get(index)
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
    if (view === "wallpapers") loadWallpapers()
  }

  // ---- actions --------------------------------------------------------------
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
    runAction(["install", themeName, item.name])
  }

  function actionRemove() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Removing " + item.name + "…")
    runAction(["remove", themeName, item.name])
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

  function actionRemoveAll() {
    busy = true
    setStatus("Removing all of theme " + themeName + "…")
    runAction(["remove", themeName])
  }

  function runAction(args) {
    actionProc.command = scriptCmd(args)
    actionProc.running = true
  }

  // ---- theme loading --------------------------------------------------------
  Process {
    id: themesProc
    command: root.scriptCmd(["themes"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        themesModel.clear()
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          var parts = line.split("\t")
          if (parts.length >= 5)
            themesModel.append({
              name: parts[0],
              catalogUrl: parts[1],
              sections: parseInt(parts[2], 10),
              count: parseInt(parts[3], 10),
              preview: parts[4]
            })
        }
        root.busy = false
        root.setStatus(themesModel.count + (themesModel.count === 1 ? " theme available" : " themes available"))
        if (themesModel.count > 0)
          Qt.callLater(function() { themesGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
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
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          var parts = line.split("\t")
          if (parts.length >= 8)
            wallpapersModel.append({
              filename: parts[0],
              name: parts[1],
              code: parts[2],
              url: parts[3],
              sha256: parts[4],
              installed: parts[5],
              isDefault: parts[6],
              preview: parts[7]
            })
        }
        root.busy = false
        root.setStatus(wallpapersModel.count + (wallpapersModel.count === 1 ? " wallpaper in " : " wallpapers in ") + root.themeName)
        if (wallpapersModel.count > 0)
          Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
      }
    }
    onExited: {
      if (root.busy) {
        root.busy = false
        root.setStatus(wallpapersModel.count > 0
          ? wallpapersModel.count + (wallpapersModel.count === 1 ? " wallpaper in " : " wallpapers in ") + root.themeName
          : "Error loading catalog")
      }
    }
  }

  // ---- action result --------------------------------------------------------
  Process {
    id: actionProc
    onExited: {
      root.busy = false
      root.setStatus("Operation completed")
      root.refresh()
    }
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

    Item {
      id: card
      visible: root.opened
      anchors.centerIn: parent
      width: Math.min(parent.width - 120, 1180)
      height: Math.min(parent.height - 120, 780)

      MouseArea { anchors.fill: parent; onClicked: {} }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius + Style.space(2)
        color: root.cardBackground
        border.color: root.cardBorder
        border.width: Math.max(1, Style.normalBorderWidth)
      }

      // ---- header -----------------------------------------------------------
      Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(64)
        color: root.barFill
        radius: Style.cornerRadius

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
          text: root.view === "themes"
            ? "Wallpaper manager"
            : root.themeName + " — browse and manage"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            visible: root.view === "wallpapers"
            text: "Back"
            iconText: "󰁍"
            hasCursor: root.view === "wallpapers"
            onClicked: root.goBack()
          }

          Button {
            text: "Refresh"
            iconText: "󰑓"
            hasCursor: true
            onClicked: root.refresh()
          }

          Button {
            text: "Close"
            iconText: "󰩍"
            hasCursor: true
            onClicked: root.close()
          }
        }
      }

      // ---- themes view ------------------------------------------------------
      GridView {
        id: themesGrid
        visible: root.view === "themes"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        anchors.margins: Style.space(18)
        model: themesModel
        clip: true
        focus: root.view === "themes"

        readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
        readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
        cellWidth: Math.floor(width / columnsHint)
        cellHeight: Math.floor(cellWidth * 0.9)

        function moveTo(index) {
          root.selectedIndex = index
          positionViewAtIndex(index, GridView.Contain)
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (!isFinite(root.selectedIndex)) root.selectedIndex = 0
          if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            moveTo(Math.max(0, root.selectedIndex - colCount))
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            moveTo(Math.min(themesModel.count - 1, root.selectedIndex + colCount))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            moveTo(Math.max(0, root.selectedIndex - 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            moveTo(Math.min(themesModel.count - 1, root.selectedIndex + 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.selectTheme(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }

        delegate: Item {
          id: themeTile
          required property int index
          required property var model
          readonly property bool selected: root.view === "themes" && root.selectedIndex === index

          width: themesGrid.cellWidth - Style.space(10)
          height: themesGrid.cellHeight - Style.space(10)

          Rectangle {
            id: themeCard
            anchors.fill: parent
            radius: Style.cornerRadius
            color: themeTile.selected ? Style.selectedFillFor(root.foreground, root.accent)
                                     : (themeMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent)
                                                                : root.tileFill)

            RoundedImage {
              id: themePreview
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: parent.height - Style.space(66)
              // Flush with the card edges: only the top corners are rounded, at
              // the full card radius.
              topRadius: Style.cornerRadius
              bottomRadius: 0
              source: themeTile.model.preview
            }

            Text {
              anchors.top: themePreview.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: Style.space(6)
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              text: themeTile.model.name
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottomMargin: Style.space(4)
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              text: themeTile.model.sections
                + (themeTile.model.sections === 1 ? " section · " : " sections · ")
                + themeTile.model.count + (themeTile.model.count === 1 ? " wallpaper" : " wallpapers")
              color: Util.alpha(root.foreground, 0.75)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            // Border drawn as the last child so it paints on top of the flush
            // thumbnail (a Rectangle's own border is painted below its children).
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: themeCard.radius
              border.color: themeTile.selected ? Style.selectedBorderFor(root.foreground, root.accent)
                                               : (themeMouse.containsMouse ? Style.hoverBorderFor(root.foreground, root.accent)
                                                                           : root.tileBorder)
              border.width: themeTile.selected ? Math.max(1, Style.selectedBorderWidth) : 1
            }

            MouseArea {
              id: themeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.selectedIndex = index
                root.selectTheme(index)
              }
            }
          }
        }
      }

      // ---- wallpapers view --------------------------------------------------
      GridView {
        id: grid
        visible: root.view === "wallpapers"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionBar.top
        anchors.margins: Style.space(18)
        model: wallpapersModel
        clip: true
        focus: root.view === "wallpapers"

        // Grid adapts to the card width: as many columns as fit while keeping
        // each tile at least ~190px wide (so previews stay readable).
        readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
        readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
        cellWidth: Math.floor(width / columnsHint)
        cellHeight: Math.floor(cellWidth * 0.9)

        function moveTo(index) {
          root.selectedIndex = index
          positionViewAtIndex(index, GridView.Contain)
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (!isFinite(root.selectedIndex)) root.selectedIndex = 0
          if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            moveTo(Math.max(0, root.selectedIndex - colCount))
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            moveTo(Math.min(wallpapersModel.count - 1, root.selectedIndex + colCount))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            moveTo(Math.max(0, root.selectedIndex - 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            moveTo(Math.min(wallpapersModel.count - 1, root.selectedIndex + 1))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.showPreview()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.actionRemove()
            event.accepted = true
          } else if (event.key === Qt.Key_D) {
            root.actionSetDefault()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.goBack()
            event.accepted = true
          }
        }

        delegate: Item {
          id: tile
          required property int index
          required property var model
          readonly property bool selected: root.view === "wallpapers" && root.selectedIndex === index

          width: grid.cellWidth - Style.space(10)
          height: grid.cellHeight - Style.space(10)

          Rectangle {
            id: tileCard
            anchors.fill: parent
            radius: Style.cornerRadius
            color: tile.selected ? Style.selectedFillFor(root.foreground, root.accent)
                                 : (tileMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent)
                                                            : root.tileFill)

            RoundedImage {
              id: preview
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: parent.height - Style.space(66)
              // Flush with the card edges: only the top corners are rounded, at
              // the full card radius.
              topRadius: Style.cornerRadius
              bottomRadius: 0
              // Local file when already installed (instant), reduced remote
              // preview otherwise; fall back to the full-res URL if a preview
              // is missing.
              source: tile.model.installed === "1"
                ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + tile.model.filename)
                : (tile.model.preview !== "" ? tile.model.preview : tile.model.url)
            }

            Row {
              anchors.top: preview.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: Style.space(6)
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              Text {
                text: tile.model.code
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                text: tile.model.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - parent.spacing * 2 - 30
              }
            }

            Row {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottomMargin: Style.space(4)
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(6)

              Rectangle {
                visible: tile.model.installed === "1"
                width: installedLabel.implicitWidth + Style.space(12)
                height: installedLabel.implicitHeight + Style.space(4)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.30)
                Text {
                  id: installedLabel
                  anchors.centerIn: parent
                  text: "installed"
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                visible: tile.model.isDefault === "1"
                width: defaultLabel.implicitWidth + Style.space(12)
                height: defaultLabel.implicitHeight + Style.space(4)
                radius: Style.cornerRadius
                color: Util.alpha(root.urgent, 0.32)
                Text {
                  id: defaultLabel
                  anchors.centerIn: parent
                  text: "default"
                  textFormat: Text.PlainText
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Border drawn as the last child so it paints on top of the flush
            // thumbnail (a Rectangle's own border is painted below its children).
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: tileCard.radius
              border.color: tile.selected ? Style.selectedBorderFor(root.foreground, root.accent)
                                          : (tileMouse.containsMouse ? Style.hoverBorderFor(root.foreground, root.accent)
                                                                     : root.tileBorder)
              border.width: tile.selected ? Math.max(1, Style.selectedBorderWidth) : 1
            }

            // Lazy preview via the reduced remote preview URL: GridView only
            // creates visible delegates, so nearby tiles load as you scroll.
            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedIndex = index
              onDoubleClicked: root.actionSetDefault()
            }
          }
        }
      }

      // ---- action bar (wallpapers view) -------------------------------------
      Rectangle {
        id: actionBar
        visible: root.view === "wallpapers"
        anchors.bottom: statusBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(52)
        color: root.barFill
        radius: Style.cornerRadius

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            text: "Install"
            iconText: "󰚌"
            hasCursor: true
            onClicked: root.actionInstall()
          }

          Button {
            text: "Remove"
            iconText: "󰇸"
            hasCursor: true
            onClicked: root.actionRemove()
          }

          Button {
            text: "Default"
            iconText: "󰉁"
            hasCursor: true
            onClicked: root.actionSetDefault()
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            text: "Install all"
            iconText: "󰑬"
            hasCursor: true
            onClicked: root.actionInstallAll()
          }

          Button {
            text: "Remove all"
            iconText: "󰇸"
            hasCursor: true
            onClicked: root.actionRemoveAll()
          }
        }
      }

      // ---- status bar -------------------------------------------------------
      Rectangle {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(36)
        color: root.barFill
        radius: Style.cornerRadius

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          BusyIndicator {
            visible: root.busy
            width: Style.space(18)
            height: Style.space(18)
            running: root.busy
          }

          Text {
            text: root.statusText
            color: Util.alpha(root.foreground, 0.85)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // ---- fullscreen preview -----------------------------------------------
      Item {
        id: previewView
        visible: root.view === "preview"
        anchors.fill: parent
        focus: root.view === "preview"
        z: 10

        // index of the wallpaper currently shown (swaps when the next one is ready)
        property int displayIndex: -1

        // natural size of the wallpaper currently shown; drives the fitted
        // rounded frame so the image corners follow the theme geometry
        property size fittedSize: Qt.size(0, 0)

        // target wallpaper, preloaded in background while the current one stays up
        readonly property string nextSource: {
          var item = root.currentItem()
          if (!item) return ""
          return item.installed === "1"
            ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + item.filename)
            : item.url
        }

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius + Style.space(2)
          color: root.background
          border.color: root.cardBorder
          border.width: Math.max(1, Style.normalBorderWidth)
        }

        // title bar with wallpaper info (name, resolution, state)
        Rectangle {
          id: previewHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(64)
          color: root.barFill
          radius: Style.cornerRadius

          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              spacing: Style.space(10)

              Text {
                text: root.currentItem() ? root.currentItem().code : ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.currentItem() ? root.currentItem().name : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: previewHeader.width - Style.space(280)
              }
            }

            Text {
              text: {
                var item = root.currentItem()
                if (!item) return ""
                if (nextImage.status === Image.Loading)
                  return "Loading " + item.filename + "…"
                if (previewImage.status === Image.Error)
                  return "Failed to load image"
                if (previewImage.status !== Image.Ready)
                  return "Loading " + item.filename + "…"
                return previewImage.implicitWidth + " × " + previewImage.implicitHeight
                  + " px · " + item.filename
              }
              color: Util.alpha(root.foreground, 0.70)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: previewHeader.width - Style.space(180)
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Rectangle {
              visible: root.currentItem() && root.currentItem().installed === "1"
              width: previewInstalledLabel.implicitWidth + Style.space(12)
              height: previewInstalledLabel.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: Util.alpha(root.accent, 0.30)
              Text {
                id: previewInstalledLabel
                anchors.centerIn: parent
                text: "installed"
                textFormat: Text.PlainText
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              visible: root.currentItem() && root.currentItem().isDefault === "1"
              width: previewDefaultLabel.implicitWidth + Style.space(12)
              height: previewDefaultLabel.implicitHeight + Style.space(4)
              radius: Style.cornerRadius
              color: Util.alpha(root.urgent, 0.32)
              Text {
                id: previewDefaultLabel
                anchors.centerIn: parent
                text: "default"
                textFormat: Text.PlainText
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Item {
          id: previewImageFrame
          anchors.top: previewHeader.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(18)

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
              previewView.displayIndex = root.selectedIndex
            } else if (status === Image.Error) {
              previewImage.source = ""
              previewView.displayIndex = root.selectedIndex
            }
          }
        }

        // spinner over the current image while the next one is loading
        BusyIndicator {
          anchors.centerIn: parent
          width: Style.space(48)
          height: Style.space(48)
          running: nextImage.status === Image.Loading
          visible: nextImage.status === Image.Loading
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          text: "←/→ next · Enter install · Esc back"
          color: Util.alpha(root.foreground, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.closePreview()
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.closePreview()
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            root.previewNext(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            root.previewNext(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            root.previewNext(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            root.previewNext(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.actionInstall()
            event.accepted = true
          }
        }
      }
    }
  }
}