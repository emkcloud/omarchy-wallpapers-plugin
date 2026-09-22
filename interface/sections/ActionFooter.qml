import QtQuick
import qs.Commons
import qs.Ui
import "../components"

// Shared card footer: a top rule bled to the card edges and, below it, one row
// per screen — themes (Setup + counts + progress), wallpapers (Install /
// Uninstall), preview (Install / Uninstall), help (Setup / Archive / Star),
// setup (Help / Archive / Star) and custom install (Help / Install / Uninstall
// + progress). Every row keeps the theme progress in the
// middle, fenced by the sidebar divider, and the key hints on the right.
// The panel owns the state; this component renders it and reports clicks
// through signals.
Column {
  id: footer

  property string view: "themes"
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color statusInstalled: accent
  property string fontFamily: Style.font.menuFamily

  property bool actionRunning: false
  property int installedCount: 0
  property int availableCount: 0
  property var progressTheme: null
  property int checkedCount: 0
  property bool storageLimitReached: false
  property bool currentInstalled: false

  // x / width of the top rule, computed by the panel so it bleeds to the card
  // edges (the footer itself is inset by the card padding).
  property real ruleX: 0
  property real ruleWidth: 0
  // Width of the themes/help/setup master pane, so every vertical divider in
  // the footer lines up with the sidebar border.
  property real sidebarWidth: 0
  property bool setupDropdownOpen: false
  property bool setupEditing: false
  property int footerSpacing: Style.space(14)
  // Custom-install screen: width of the previews pane (so its divider lines up)
  // and whether the highlighted card can be installed / removed.
  property real customPaneWidth: 0
  property bool customInstallEnabled: false
  property bool customRemoveEnabled: false

  signal installRequested()
  signal removeRequested()
  signal helpRequested()
  signal setupRequested()
  signal databaseRequested()
  signal openRepoRequested()
  signal customInstallRequested()
  signal customRemoveRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color ruleColor:
    Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  // Key hint: the key in bold foreground, the action in dim, matching the kit's
  // "click select / shift+click range" caption style.
  function keyHint(key, label) {
    return "<font color=\"" + footer.foreground + "\"><b>" + key + "</b></font>"
      + " <font color=\"" + footer.dim + "\">" + label + "</font>"
  }

  spacing: footer.footerSpacing

  // Wrapped so the rule can bleed past the footer's own padding to the card
  // edges (a Column would force its x back to 0).
  Item {
    width: parent.width
    height: 1

    PanelSeparator {
      x: footer.ruleX
      width: footer.ruleWidth
      foreground: footer.foreground
    }
  }

  // Themes footer: installed/available summary on the left, progress of the
  // selected theme in the middle, key hints on the right.
  Item {
    id: themesFooterRow

    visible: footer.view === "themes"
    width: parent.width
    height: Math.max(setupButton.implicitHeight,
      themesSummary.implicitHeight, themeProgress.implicitHeight,
      themesHints.implicitHeight)

    // Settings: setup of the plugin, so the themes footer has the same height
    // as the others.
    Button {
      id: setupButton

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      enabled: !footer.actionRunning
      opacity: enabled ? 1 : 0.4
      text: "Setup"
      iconText: "󰒓"
      bordered: true
      foreground: footer.foreground
      accent: footer.accent
      fontFamily: footer.fontFamily
      onClicked: footer.setupRequested()
    }

    // Installed/available summary, right-aligned against the sidebar rule so it
    // lines up with the detail zone's content.
    Row {
      id: themesSummary

      anchors.right: themesSidebarRule.left
      anchors.rightMargin: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: width
        radius: width / 2
        color: footer.statusInstalled
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: footer.installedCount + " installed · "
          + footer.availableCount + " available"
        color: footer.dim
        font.family: footer.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ThemeProgress {
      id: themeProgress

      anchors.left: parent.left
      anchors.leftMargin: footer.sidebarWidth + Style.space(22)
      anchors.right: hintsRule.left
      anchors.rightMargin: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter
      theme: footer.progressTheme
      busy: footer.actionRunning
      foreground: footer.foreground
      accent: footer.accent
      fontFamily: footer.fontFamily
    }

    Text {
      id: themesHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
      text: footer.actionRunning
        ? footer.keyHint("esc", "stop")
        : footer.keyHint("enter", "browse")
          + "&nbsp;&nbsp;" + footer.keyHint("i", "install")
          + "&nbsp;&nbsp;" + footer.keyHint("/", "search")
          + "&nbsp;&nbsp;" + footer.keyHint("esc", "close")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Vertical rules, as in the original mockup: the first continues the master
    // list's right border into the footer, the second separates the progress
    // from the key hints.
    Rectangle {
      id: themesSidebarRule

      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    Rectangle {
      id: hintsRule

      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: themesHints.left
      anchors.rightMargin: Style.space(20)
      width: 1
      color: footer.ruleColor
    }
  }

  // Wallpapers footer: Install/Uninstall on the left, the open theme's progress
  // in the middle, the key hints on the right.
  Item {
    id: actionRow

    visible: footer.view === "wallpapers"
    width: parent.width
    height: Math.max(primaryActions.implicitHeight,
      wallpapersProgress.implicitHeight, wallpapersHints.implicitHeight)

    Row {
      id: primaryActions

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      // Help, before the actions (the wallpapers header carries none).
      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Help"
        iconText: "󰘥"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.helpRequested()
      }

      Button {
        // A batch install is bulk: disabled while a storage cap is reached (one
        // wallpaper at a time stays available).
        enabled: !footer.actionRunning
          && !(footer.storageLimitReached && footer.checkedCount > 1)
        opacity: enabled ? 1 : 0.4
        text: "Install"
        iconText: "󰮏"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.installRequested()
      }

      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Uninstall"
        iconText: "󰩺"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.removeRequested()
      }
    }

    // First rule: same x as the themes screen's master/detail divider, so the
    // Install/Uninstall section spans the sidebar's width.
    Rectangle {
      id: wallpapersSidebarRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    ThemeProgress {
      id: wallpapersProgress

      anchors.left: wallpapersSidebarRule.right
      anchors.leftMargin: Style.space(22)
      anchors.right: wallpapersBulkRule.left
      anchors.rightMargin: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter
      theme: footer.progressTheme
      busy: footer.actionRunning
      foreground: footer.foreground
      accent: footer.accent
      fontFamily: footer.fontFamily
    }

    // Second rule, between the progress and the key hints.
    Rectangle {
      id: wallpapersBulkRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: wallpapersHints.left
      anchors.rightMargin: Style.space(20)
      width: 1
      color: footer.ruleColor
    }

    Text {
      id: wallpapersHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
      text: footer.actionRunning
        ? footer.keyHint("esc", "stop")
        : footer.keyHint("enter", "browse")
          + "&nbsp;&nbsp;" + footer.keyHint("space", "select")
          + "&nbsp;&nbsp;" + footer.keyHint("i", "install")
          + "&nbsp;&nbsp;" + footer.keyHint("/", "search")
          + "&nbsp;&nbsp;" + footer.keyHint("esc", "back")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Preview footer: Install / Uninstall on the left, the open theme's progress
  // in the middle, the key hints on the right.
  Item {
    id: previewFooterRow

    visible: footer.view === "preview"
    width: parent.width
    height: Math.max(previewPrimaryActions.implicitHeight,
      previewProgress.implicitHeight, previewHints.implicitHeight)

    Row {
      id: previewPrimaryActions

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      // Help, before the actions (the big preview's only Help button: the
      // header carries none).
      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Help"
        iconText: "󰘥"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.helpRequested()
      }

      Button {
        id: previewInstall

        enabled: !footer.actionRunning && !footer.currentInstalled
        opacity: enabled ? 1 : 0.4
        text: "Install"
        iconText: "󰮏"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.installRequested()
      }

      // Same label and theme-red tint as the themes screen's Uninstall;
      // `Color.urgent` is the theme's red (color1), not a fixed danger. The
      // border is forced to urgent too (the kit's normal border would use
      // `foreground` at a low alpha).
      Button {
        text: "Uninstall"
        iconText: "󰩺"
        enabled: !footer.actionRunning && footer.currentInstalled
        opacity: enabled ? 1 : 0.4
        bordered: true
        foreground: footer.urgent
        accent: footer.urgent
        borderSpec: Border.flat(footer.urgent, Math.max(1, Style.normalBorderWidth))
        fontFamily: footer.fontFamily
        onClicked: footer.removeRequested()
      }
    }

    ThemeProgress {
      id: previewProgress

      anchors.left: previewSidebarRule.right
      anchors.leftMargin: Style.space(22)
      anchors.right: previewHints.left
      anchors.rightMargin: Style.space(34)
      anchors.verticalCenter: parent.verticalCenter
      theme: footer.progressTheme
      busy: footer.actionRunning
      foreground: footer.foreground
      accent: footer.accent
      fontFamily: footer.fontFamily
    }

    // First rule: same x as the themes screen's master/detail divider, so the
    // Install/Uninstall section spans the sidebar's width.
    Rectangle {
      id: previewSidebarRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    Rectangle {
      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: previewProgress.right
      anchors.leftMargin: Style.space(14)
      width: 1
      color: footer.ruleColor
    }

    Text {
      id: previewHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      // `&nbsp;` (not plain spaces: StyledText collapses runs of them).
      text: footer.keyHint("enter", "install")
        + "&nbsp;&nbsp;" + footer.keyHint("d", "default")
        + "&nbsp;&nbsp;" + footer.keyHint("u", "uninstall")
        + "&nbsp;&nbsp;" + footer.keyHint("esc", "back")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Help footer: Setup plus a direct link to the version dataset, then the same
  // master/detail divider as the other screens.
  Item {
    id: helpFooterRow

    visible: footer.view === "help"
    width: parent.width
    height: Math.max(helpFooterActions.implicitHeight,
      helpHints.implicitHeight)

    Row {
      id: helpFooterActions

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      // Same button as the themes footer, so the help footer keeps the same
      // height as the other screens.
      Button {
        id: helpFooterButton

        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Setup"
        iconText: "󰒓"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.setupRequested()
      }

      // Direct link to the version dataset (derived from `base`).
      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Archive RAW"
        iconText: "󰆼"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.databaseRequested()
      }

      // Star the project on GitHub. There is no direct "star" URL, so this opens
      // the repo (URL from config.links).
      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Star"
        iconText: "󰓎"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.openRepoRequested()
      }
    }

    // The master/detail divider used by every other footer, continuing the Help
    // sidebar border.
    Rectangle {
      id: helpSidebarRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    Text {
      id: helpHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      text: footer.keyHint("enter", "open")
        + "&nbsp;&nbsp;" + footer.keyHint("arrows", "move")
        + "&nbsp;&nbsp;" + footer.keyHint("pgup/pgdn", "scroll")
        + "&nbsp;&nbsp;" + footer.keyHint("p", "propose")
        + "&nbsp;&nbsp;" + footer.keyHint("d", "database")
        + "&nbsp;&nbsp;" + footer.keyHint("esc", "back")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Setup footer: the Help/links group on the left and the keyboard hints on the
  // right, mirroring the Help footer.
  Item {
    id: setupFooterRow

    visible: footer.view === "setup"
    width: parent.width
    height: Math.max(setupFooterLeft.implicitHeight,
      setupHints.implicitHeight)

    Row {
      id: setupFooterLeft

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Help "
        iconText: "󰘥"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.helpRequested()
      }

      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Archive RAW"
        iconText: "󰆼"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.databaseRequested()
      }

      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Star"
        iconText: "󰓎"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.openRepoRequested()
      }
    }

    // The master/detail divider used by every other footer, continuing the
    // sidebar border.
    Rectangle {
      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    Text {
      id: setupHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      text: footer.setupDropdownOpen
        ? footer.keyHint("arrows", "move")
          + "&nbsp;&nbsp;" + footer.keyHint("enter", "select")
          + "&nbsp;&nbsp;" + footer.keyHint("esc", "close")
        : footer.setupEditing
          ? footer.keyHint("arrows", "change")
            + "&nbsp;&nbsp;" + footer.keyHint("enter", "confirm")
            + "&nbsp;&nbsp;" + footer.keyHint("esc", "cancel")
          : footer.keyHint("enter", "open")
          + "&nbsp;&nbsp;" + footer.keyHint("arrows", "move")
          + "&nbsp;&nbsp;" + footer.keyHint("d", "defaults")
          + "&nbsp;&nbsp;" + footer.keyHint("?", "help")
          + "&nbsp;&nbsp;" + footer.keyHint("q", "close")
          + "&nbsp;&nbsp;" + footer.keyHint("esc", "back")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Custom install footer: Help / Install / Uninstall on the left, the theme's
  // progress in the middle, the key hints on the right — the wallpapers footer
  // shape, with the divider lining up with the previews pane.
  Item {
    id: customFooterRow

    visible: footer.view === "custom"
    width: parent.width
    height: Math.max(customPrimaryActions.implicitHeight,
      customProgress.implicitHeight, customHints.implicitHeight)

    Row {
      id: customPrimaryActions

      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap

      Button {
        enabled: !footer.actionRunning
        opacity: enabled ? 1 : 0.4
        text: "Help"
        iconText: "󰘥"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.helpRequested()
      }

      // Runs the highlighted choice (same as Enter on the card).
      Button {
        enabled: !footer.actionRunning && footer.customInstallEnabled
        opacity: enabled ? 1 : 0.4
        text: "Install"
        iconText: "󰮏"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.customInstallRequested()
      }

      // Removes the highlighted scope (theme or collection).
      Button {
        enabled: !footer.actionRunning && footer.customRemoveEnabled
        opacity: enabled ? 1 : 0.4
        text: "Uninstall"
        iconText: "󰩺"
        bordered: true
        foreground: footer.foreground
        accent: footer.accent
        fontFamily: footer.fontFamily
        onClicked: footer.customRemoveRequested()
      }
    }

    // First rule: the same master-pane divider as every other screen, so the
    // Help / Install / Uninstall section is as wide as the themes sidebar.
    Rectangle {
      id: customSidebarRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.sidebarWidth - 1
      width: 1
      color: footer.ruleColor
    }

    ThemeProgress {
      id: customProgress

      anchors.left: customSidebarRule.right
      anchors.leftMargin: Style.space(22)
      anchors.right: customBulkRule.left
      anchors.rightMargin: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter
      theme: footer.progressTheme
      busy: footer.actionRunning
      foreground: footer.foreground
      accent: footer.accent
      fontFamily: footer.fontFamily
    }

    // Second rule: lines up with the previews/cards boundary, so the progress
    // ends where the right sidebar begins.
    Rectangle {
      id: customBulkRule

      z: 2
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      x: footer.customPaneWidth
      width: 1
      color: footer.ruleColor
    }

    Text {
      id: customHints

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      text: footer.actionRunning
        ? footer.keyHint("esc", "stop")
        : footer.keyHint("enter", "install")
          + "&nbsp;&nbsp;" + footer.keyHint("b", "browse")
          + "&nbsp;&nbsp;" + footer.keyHint("esc", "back")
      color: footer.dim
      font.family: footer.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
