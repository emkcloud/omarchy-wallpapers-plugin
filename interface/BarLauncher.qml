import QtQuick
import qs.Ui

// Bar launcher: one click opens/closes this plugin's own overlay through the
// scoped shell facade, so no id is hardcoded. The developer install shares this
// file but is rendered under the `-developer` moduleName, so it gets a distinct
// glyph and tooltip and the two icons never look alike.
BarWidget {
  id: root

  readonly property bool dev: String(root.moduleName).indexOf("-developer") !== -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dev ? "󰒓" : "󰸌"
    horizontalMargin: 7.5
    tooltipText: root.dev ? "Wallpaper manager (dev)" : "Wallpaper manager"
    onPressed: function(button) {
      if (!root.bar || !root.bar.shell) return
      root.bar.shell.toggle(root.bar.shell.pluginId, "{}")
    }
  }
}
