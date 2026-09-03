import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
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
  readonly property color muted: Color.muted
  readonly property color scrim: Util.alpha(Color.background, 0.72)
  readonly property string fontFamily: Style.font.family

  ListModel { id: themesModel }
  ListModel { id: wallpapersModel }

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
    setStatus("Caricamento temi…")
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
    setStatus("Caricamento wallpaper di " + themeName + "…")
    wallpapersModel.clear()
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
    if (view !== "wallpapers" || selectedIndex < 0 || selectedIndex >= wallpapersModel.count)
      return null
    return wallpapersModel.get(selectedIndex)
  }

  function actionInstall() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Installazione " + item.name + "…")
    runAction(["install", themeName, item.name])
  }

  function actionRemove() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Rimozione " + item.name + "…")
    runAction(["remove", themeName, item.name])
  }

  function actionSetDefault() {
    var item = currentItem()
    if (!item) return
    busy = true
    setStatus("Imposto default: " + item.name + "…")
    runAction(["set-default", themeName, item.filename, item.url])
  }

  function actionInstallAll() {
    busy = true
    setStatus("Installazione di tutto il tema " + themeName + "…")
    runAction(["install", themeName])
  }

  function actionRemoveAll() {
    busy = true
    setStatus("Rimozione di tutto il tema " + themeName + "…")
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
          if (parts.length >= 2)
            themesModel.append({ name: parts[0], catalogUrl: parts[1] })
        }
        root.busy = false
        root.setStatus(themesModel.count + " tema/i disponibili")
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
          if (parts.length >= 7)
            wallpapersModel.append({
              filename: parts[0],
              name: parts[1],
              code: parts[2],
              url: parts[3],
              sha256: parts[4],
              installed: parts[5],
              isDefault: parts[6],
              previewPath: ""
            })
        }
        root.busy = false
        root.setStatus(wallpapersModel.count + " wallpaper in " + root.themeName)
      }
    }
  }

  // ---- action result --------------------------------------------------------
  Process {
    id: actionProc
    onExited: {
      root.busy = false
      root.setStatus("Operazione completata")
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

      // ---- header -----------------------------------------------------------
      Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(64)
        color: Util.alpha(root.foreground, 0.05)
        radius: Style.cornerRadius

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
          text: root.view === "themes"
            ? "Wallpaper manager"
            : root.themeName + " — sfoglia e gestisci"
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
            text: "Indietro"
            iconText: "󰁍"
            hasCursor: root.view === "wallpapers"
            onClicked: root.goBack()
          }

          Button {
            text: "Aggiorna"
            iconText: "󰑓"
            hasCursor: true
            onClicked: root.refresh()
          }

          Button {
            text: "Chiudi"
            iconText: "󰩍"
            hasCursor: true
            onClicked: root.close()
          }
        }
      }

      // ---- themes view ------------------------------------------------------
      ListView {
        id: themesList
        visible: root.view === "themes"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        anchors.margins: Style.space(18)
        model: themesModel
        clip: true

        delegate: Item {
          id: themeRow
          required property int index
          required property var model
          width: themesList.width
          height: Style.space(56)
          readonly property bool selected: root.view === "themes" && root.selectedIndex === index

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: themeRow.selected ? Style.selectedFillFor(root.foreground, root.accent)
                                     : (mouseArea.containsMouse ? Style.hoverFillFor(root.foreground, root.accent)
                                                                : "transparent")
            border.color: themeRow.selected ? Style.selectedBorderFor(root.foreground, root.accent) : "transparent"
            border.width: themeRow.selected ? Math.max(1, Style.selectedBorderWidth) : 0
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: model.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }

          MouseArea {
            id: mouseArea
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
        cellWidth: Style.space(210)
        cellHeight: Style.space(172)
        focus: root.view === "wallpapers"

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            root.selectedIndex = Math.max(0, root.selectedIndex - grid.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            root.selectedIndex = Math.min(wallpapersModel.count - 1, root.selectedIndex + grid.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            root.selectedIndex = Math.max(0, root.selectedIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            root.selectedIndex = Math.min(wallpapersModel.count - 1, root.selectedIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.actionInstall()
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

          width: grid.cellWidth - Style.space(8)
          height: grid.cellHeight - Style.space(8)
          anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

          property bool _loaded: false

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: tile.selected ? Style.selectedFillFor(root.foreground, root.accent)
                                 : (tileMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent)
                                                            : Util.alpha(root.foreground, 0.04))
            border.color: tile.selected ? Style.selectedBorderFor(root.foreground, root.accent)
                                        : Util.alpha(root.foreground, 0.12)
            border.width: tile.selected ? Math.max(1, Style.selectedBorderWidth) : 1

            Image {
              id: preview
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: Style.space(112)
              anchors.margins: Style.space(6)
              source: tile.model.previewPath ? Util.fileUrl(tile.model.previewPath) : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              sourceSize.width: 512
              clip: true
            }

            Row {
              anchors.top: preview.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Style.space(6)
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
              anchors.margins: Style.space(6)
              spacing: Style.space(6)

              Rectangle {
                visible: tile.model.installed === "1"
                width: Style.space(60)
                height: Style.space(16)
                radius: Style.space(3)
                color: Util.alpha(root.accent, 0.18)
                Text {
                  anchors.centerIn: parent
                  text: "installato"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                visible: tile.model.isDefault === "1"
                width: Style.space(52)
                height: Style.space(16)
                radius: Style.space(3)
                color: Util.alpha(root.urgent, 0.22)
                Text {
                  anchors.centerIn: parent
                  text: "default"
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Lazy preview download (only for items that become visible).
            Process {
              id: previewProc
              property string targetIndex: ""
              command: root.scriptCmd(["preview", root.themeName, tile.model.filename, tile.model.url])
              stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                  var path = String(text || "").trim()
                  if (path && tile.index >= 0 && tile.index < wallpapersModel.count)
                    wallpapersModel.setProperty(tile.index, "previewPath", path)
                }
              }
            }

            Component.onCompleted: {
              if (tile.model.previewPath === "" && !tile._loaded) {
                tile._loaded = true
                previewProc.running = true
              }
            }

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
        color: Util.alpha(root.foreground, 0.05)
        radius: Style.cornerRadius

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Button {
            text: "Installa"
            iconText: "󰚌"
            hasCursor: true
            onClicked: root.actionInstall()
          }

          Button {
            text: "Rimuovi"
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
            text: "Installa tutto"
            iconText: "󰑬"
            hasCursor: true
            onClicked: root.actionInstallAll()
          }

          Button {
            text: "Rimuovi tutto"
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
        color: Util.alpha(root.foreground, 0.04)
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
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}