import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
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

  // emkcloud logo shipped with the plugin, used as the hero icon in every view.
  readonly property string logoPath: {
    var p = pluginDir
    return p ? Util.fileUrl(p.replace(/\/$/, "") + "/logo.png") : ""
  }

  // ---- view state -----------------------------------------------------------
  readonly property string stateHome: Quickshell.env("HOME") + "/.local/state"
  readonly property string currentBgLink: stateHome + "/omarchy/current/background"
  readonly property string backgroundsDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds"

  property bool opened: false
  property string view: "themes"          // "themes" | "wallpapers" | "preview"
  property string themeName: ""
  property string themeCatalogUrl: ""
  property int selectedIndex: 0
  property bool busy: false
  property string statusText: ""

  // Cursor model (see Ui/CursorSurface.qml): mouse hover and keyboard share a
  // single cursor. Items derive their visuals from `hasCursor`, never from
  // `containsMouse`, so only one tile is ever highlighted.
  property bool cursorActive: true

  // ---- theme tokens ---------------------------------------------------------
  // Overlay chrome follows the first-party overlays (menu / clipboard /
  // emojis): a single flat `Color.menu.*` surface, no per-region fills, and
  // borders built from the theme spec so Hyprland gradients survive.
  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color scrim: Color.menu.scrim
  readonly property color dim: Qt.darker(Color.menu.text, 1.4)
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md
  readonly property int minTileWidth: Style.space(190)
  readonly property int tileGap: Style.space(4)
  readonly property int tileInset: Math.max(1, Style.normalBorderWidth)
  readonly property string fontFamily: Style.font.menuFamily

  // The two heroes (grid / fullscreen preview) are pinned to the same height so
  // switching view — or a title that grows a resolution suffix — never shifts
  // the separator and the content below it.
  readonly property int heroHeight: Math.max(hero.implicitHeight, previewHero.implicitHeight)

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
  // (`r_inner = r_outer - gap`) keeps the padding visually uniform.
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

  // ---- hero logo ------------------------------------------------------------
  // emkcloud brand mark, same size slot as the nerd-font glyph it replaces
  // (`Style.font.displayLarge`) and rounded like every other image here. The
  // glyph stays as fallback if the file is missing (plugin dir not resolved).
  component HeroLogo: Item {
    id: heroLogo

    property string glyph: ""
    readonly property bool ready: heroLogoImage.status === Image.Ready

    implicitWidth: Style.font.displayLarge
    implicitHeight: Style.font.displayLarge

    RoundedImage {
      id: heroLogoImage
      anchors.fill: parent
      visible: heroLogo.ready
      source: root.logoPath
      fillMode: Image.PreserveAspectFit
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      visible: !heroLogo.ready
      text: heroLogo.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
    }
  }

  // ---- state pill -----------------------------------------------------------
  // Same anatomy as the `detail` pill in Ui/PanelHero.qml: transparent fill,
  // themed border, caption text. The tint carries the meaning instead of a
  // colored blob.
  component Pill: BorderSurface {
    id: pill

    property string label: ""
    property color tint: root.accent

    implicitWidth: pillText.implicitWidth + Style.space(10)
    implicitHeight: pillText.implicitHeight + Style.space(4)
    color: "transparent"
    radius: Style.cornerRadius
    borderSpec: Border.flat(pill.tint, Math.max(1, Style.normalBorderWidth))

    Text {
      id: pillText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: pill.label
      color: pill.tint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- lifecycle ------------------------------------------------------------
  function open(payload) {
    opened = true
    view = "themes"
    selectedIndex = 0
    cursorActive = true
    statusText = ""
    loadThemes()
  }

  function close() {
    opened = false
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { keys.forceActiveFocus() })

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

  // The dataset carries a readable `title` ("Tokyo Night"); the tiles show it
  // uppercased. Fallback for older datasets: normalize the slug.
  function themeLabel(item) {
    var label = item && item.title ? item.title : (item ? item.name : "")
    return String(label).replace(/[-_]+/g, " ").toUpperCase()
  }

  function selectTheme(index) {
    if (index < 0 || index >= themesModel.count) return
    var item = themesModel.get(index)
    // Drop the previous theme's rows first: the wallpapers GridView delegates
    // survive the trip through the themes view, so leaving them alive while
    // `themeName` changes makes them re-resolve their local file path against
    // the new theme and log a pile of "Cannot open" warnings.
    wallpapersModel.clear()
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

  // ---- cursor state machine -------------------------------------------------
  // Ui/PanelKeyCatcher.qml turns raw keys into semantic signals; the panel
  // keeps the state machine. GridView has no `columns` in Qt 6, so the column
  // count is computed by hand (see AGENTS.md).
  function activeGrid() {
    return view === "themes" ? themesGrid : grid
  }

  function activeCount() {
    return view === "themes" ? themesModel.count : wallpapersModel.count
  }

  function stepCursor(step) {
    var count = activeCount()
    if (count === 0) return

    var g = activeGrid()
    if (!isFinite(selectedIndex)) selectedIndex = 0

    cursorActive = true
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + step))
    g.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function moveCursor(dx, dy) {
    if (view === "preview") {
      previewNext(dx !== 0 ? dx : dy)
      return
    }

    stepCursor(dx !== 0 ? dx : dy * activeGrid().colCount)
  }

  // PageUp/PageDown: jump a whole visible page of tiles (rows on screen ×
  // columns). PanelKeyCatcher does not map these keys, so they bubble up to
  // the card's Keys.onPressed fallback.
  function pageCursor(dir) {
    if (view === "preview") {
      previewNext(dir)
      return
    }

    var g = activeGrid()
    var rows = Math.max(1, Math.floor(g.height / g.cellHeight))
    stepCursor(dir * rows * g.colCount)
  }

  function activateCursor() {
    if (view === "themes") selectTheme(selectedIndex)
    else if (view === "wallpapers") showPreview()
    else actionInstall()
  }

  function dismissCursor() {
    if (view === "preview") closePreview()
    else if (view === "wallpapers") goBack()
    else close()
  }

  function handleTextKey(text) {
    if (text === "d" || text === "D") actionSetDefault()
    else if (text === "r" || text === "R") refresh()
  }

  function takeCursor(index) {
    cursorActive = true
    selectedIndex = index
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
          if (parts.length >= 6)
            themesModel.append({
              name: parts[0],
              title: parts[1],
              catalogUrl: parts[2],
              sections: parseInt(parts[3], 10),
              count: parseInt(parts[4], 10),
              preview: parts[5]
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

    // Single flat card, exactly like the first-party overlays: no header or
    // footer fills, separation comes from spacing and Ui/PanelSeparator.
    BorderSurface {
      id: card

      visible: root.opened
      anchors.centerIn: parent
      width: Math.min(Style.space(1180), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), parent.height - Style.gapsOut * 2)
      color: root.background
      radius: Style.cornerRadius
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Del/Backspace are not part of the canonical key set (PanelKeyCatcher
      // maps removal to x/X); PageUp/PageDown are not mapped either. Both
      // bubble up here.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
          root.actionRemove()
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.pageCursor(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.pageCursor(-1)
          event.accepted = true
        }
      }

      PanelKeyCatcher {
        id: keys

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
        onActivateRequested: root.activateCursor()
        onCloseRequested: root.dismissCursor()
        onDeleteRequested: root.actionRemove()
        onTextKey: function(text) { root.handleTextKey(text) }

        // ---- hero -----------------------------------------------------------
        Component {
          id: heroIcon

          HeroLogo {
            glyph: root.view === "themes" ? "󰸌" : ""
          }
        }

        Component {
          id: heroActions

          Row {
            spacing: Style.spacing.controlGap

            Button {
              visible: root.view === "wallpapers"
              text: "Back"
              iconText: "󰁍"
              tooltipText: "Esc"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.goBack()
            }

            Button {
              text: "Refresh"
              iconText: "󰑓"
              tooltipText: "r"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }

            Button {
              text: "Close"
              iconText: "󰩍"
              tooltipText: "Esc"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.close()
            }
          }
        }

        PanelHero {
          id: hero

          visible: root.view !== "preview"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.heroHeight
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: heroIcon
          trailingControl: heroActions
          title: root.view === "themes" ? "Wallpaper manager" : root.themeName
          detail: root.view === "themes"
            ? (themesModel.count > 0 ? String(themesModel.count) : "")
            : (wallpapersModel.count > 0 ? String(wallpapersModel.count) : "")
          meta: root.view === "themes"
            ? "remote collections"
            : "browse and manage"
        }

        PanelSeparator {
          id: heroRule
          visible: root.view !== "preview"
          anchors.top: hero.bottom
          anchors.topMargin: root.contentSpacing
          foreground: root.foreground
        }

        // ---- themes view ----------------------------------------------------
        GridView {
          id: themesGrid

          visible: root.view === "themes"
          anchors.top: heroRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing
          model: themesModel
          clip: true

          readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
          readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
          cellWidth: Math.floor(width / columnsHint)
          cellHeight: Math.floor(cellWidth * 0.9)

          delegate: Item {
            id: themeTile
            required property int index
            required property var model

            width: themesGrid.cellWidth
            height: themesGrid.cellHeight

            CursorSurface {
              id: themeCard

              anchors.fill: parent
              anchors.margins: root.tileGap
              foreground: root.foreground
              accent: root.accent
              bordered: true
              hasCursor: root.cursorActive && root.view === "themes" && root.selectedIndex === themeTile.index

              RoundedImage {
                id: themePreview
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: root.tileInset
                height: parent.height - Style.space(60)
                inset: root.tileInset
                bottomRadius: 0
                source: themeTile.model.preview
              }

              Text {
                anchors.top: themePreview.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: root.themeLabel(themeTile.model)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }

              Text {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: themeTile.model.sections
                  + (themeTile.model.sections === 1 ? " section · " : " sections · ")
                  + themeTile.model.count + (themeTile.model.count === 1 ? " wallpaper" : " wallpapers")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered) root.takeCursor(themeTile.index)
              }

              TapHandler {
                onTapped: {
                  root.takeCursor(themeTile.index)
                  root.selectTheme(themeTile.index)
                }
              }
            }
          }
        }

        // ---- wallpapers view ------------------------------------------------
        GridView {
          id: grid

          visible: root.view === "wallpapers"
          anchors.top: heroRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing
          model: wallpapersModel
          clip: true

          // Grid adapts to the card width: as many columns as fit while keeping
          // each tile at least ~190px wide (so previews stay readable).
          readonly property int columnsHint: Math.max(2, Math.floor(width / root.minTileWidth))
          readonly property int colCount: Math.max(1, Math.floor(width / cellWidth))
          cellWidth: Math.floor(width / columnsHint)
          cellHeight: Math.floor(cellWidth * 0.9)

          delegate: Item {
            id: tile
            required property int index
            required property var model

            width: grid.cellWidth
            height: grid.cellHeight

            CursorSurface {
              id: tileCard

              anchors.fill: parent
              anchors.margins: root.tileGap
              foreground: root.foreground
              accent: root.accent
              bordered: true
              hasCursor: root.cursorActive && root.view === "wallpapers" && root.selectedIndex === tile.index
              // Persistent state: this is the theme's default background.
              current: tile.model.isDefault === "1"

              RoundedImage {
                id: preview
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: root.tileInset
                height: parent.height - Style.space(60)
                inset: root.tileInset
                bottomRadius: 0
                // Local file when already installed (instant), reduced remote
                // preview otherwise; fall back to the full-res URL if a preview
                // is missing. GridView only creates visible delegates, so
                // nearby tiles load lazily as you scroll.
                source: tile.model.installed === "1"
                  ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + tile.model.filename)
                  : (tile.model.preview !== "" ? tile.model.preview : tile.model.url)
              }

              Row {
                id: tileLabels
                anchors.top: preview.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)

                Text {
                  id: tileCode
                  textFormat: Text.PlainText
                  text: tile.model.code
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: tile.model.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: Math.max(0, tileLabels.width - tileCode.width - tileLabels.spacing)
                }
              }

              Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: Style.space(6)
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(6)

                Pill {
                  visible: tile.model.installed === "1"
                  label: "installed"
                  tint: root.accent
                }

                Pill {
                  visible: tile.model.isDefault === "1"
                  label: "default"
                  tint: root.urgent
                }
              }

              HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered) root.takeCursor(tile.index)
              }

              TapHandler {
                onTapped: root.takeCursor(tile.index)
                onDoubleTapped: {
                  root.takeCursor(tile.index)
                  root.actionSetDefault()
                }
              }
            }
          }
        }

        // ---- footer: actions + status ---------------------------------------
        // No footer bar: a separator, borderless controls on the flat surface
        // and a dim caption for status, as in the first-party panels.
        Column {
          id: footer

          visible: root.view !== "preview"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: root.contentSpacing

          PanelSeparator { foreground: root.foreground }

          Item {
            id: actionRow
            visible: root.view === "wallpapers"
            width: parent.width
            height: Math.max(primaryActions.implicitHeight, bulkActions.implicitHeight)

            Row {
              id: primaryActions
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              Button {
                text: "Install"
                iconText: "󰚌"
                tooltipText: "Enter in preview"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionInstall()
              }

              Button {
                text: "Remove"
                iconText: "󰇸"
                tooltipText: "x"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionRemove()
              }

              Button {
                text: "Default"
                iconText: "󰉁"
                tooltipText: "d"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionSetDefault()
              }
            }

            Row {
              id: bulkActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.controlGap

              Button {
                text: "Install all"
                iconText: "󰑬"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionInstallAll()
              }

              Button {
                text: "Remove all"
                iconText: "󰇸"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.actionRemoveAll()
              }
            }
          }

          Text {
            id: statusLabel
            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.statusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // ---- fullscreen preview ---------------------------------------------
        Item {
          id: previewView

          visible: root.view === "preview"
          anchors.fill: parent
          z: 10

          // natural size of the wallpaper currently shown; drives the fitted
          // rounded frame so the image corners follow the theme geometry
          property size fittedSize: Qt.size(0, 0)

          // last source that failed to load, so the hero meta can report it
          property string failedSource: ""

          // target wallpaper, preloaded in background while the current one stays up
          readonly property string nextSource: {
            var item = root.currentItem()
            if (!item) return ""
            return item.installed === "1"
              ? Util.fileUrl(root.backgroundsDir + "/" + root.themeName + "/" + item.filename)
              : item.url
          }

          // true only when the visible image is the one of the selected item,
          // so the title never pairs a name with the previous resolution
          readonly property bool shown: previewImage.status === Image.Ready
            && String(previewImage.source) === String(nextSource)

          readonly property bool failed: failedSource !== ""
            && String(failedSource) === String(nextSource)

          Component {
            id: previewIcon

            HeroLogo {
              glyph: ""
            }
          }

          Component {
            id: previewActions

            Row {
              spacing: Style.spacing.controlGap

              Pill {
                visible: root.currentItem() && root.currentItem().installed === "1"
                anchors.verticalCenter: parent.verticalCenter
                label: "installed"
                tint: root.accent
              }

              Pill {
                visible: root.currentItem() && root.currentItem().isDefault === "1"
                anchors.verticalCenter: parent.verticalCenter
                label: "default"
                tint: root.urgent
              }

              Button {
                text: "Back"
                iconText: "󰁍"
                tooltipText: "Esc"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.closePreview()
              }
            }
          }

          PanelHero {
            id: previewHero

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.heroHeight
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: previewIcon
            trailingControl: previewActions
            // "AD - Andorra (2000x1000)": code, name, then the real resolution
            title: {
              var item = root.currentItem()
              if (!item) return ""
              var label = item.code !== "" ? item.code + " - " + item.name : item.name
              if (previewView.shown && previewImage.implicitWidth > 0)
                return label + " (" + previewImage.implicitWidth
                  + "x" + previewImage.implicitHeight + ")"
              return label
            }
            // no `detail` pill: the code is inline in the title
            meta: {
              var item = root.currentItem()
              if (!item) return ""
              if (previewView.failed) return "failed to load " + item.filename
              if (!previewView.shown) return "loading " + item.filename
              return item.filename
            }
          }

          PanelSeparator {
            id: previewRule
            anchors.top: previewHero.bottom
            anchors.topMargin: root.contentSpacing
            foreground: root.foreground
          }

          Text {
            id: previewHint
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            textFormat: Text.PlainText
            text: "h/l or arrows to walk · Enter to install · Esc to go back"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            id: previewImageFrame

            anchors.top: previewRule.bottom
            anchors.topMargin: root.contentSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: previewHint.top
            anchors.bottomMargin: root.contentSpacing

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
            onTapped: root.closePreview()
          }
        }
      }
    }
  }
}
