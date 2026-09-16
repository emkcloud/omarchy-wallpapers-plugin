import QtQuick
import qs.Commons
import "../js/Model.js" as Model

// Install progress of one theme: "NAME · N/M" caption with the percentage on
// the right, over a thin accent bar. Shared by the themes footer and the
// wallpapers footer, so the state of the theme being browsed is always visible.
Column {
  id: progress

  property var theme: null
  property color foreground: "white"
  property color accent: "white"
  property string fontFamily: ""
  // True while an install/remove runs: shows a "please wait" caption between
  // the label and the percentage.
  property bool busy: false

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property real ratio: {
    if (!theme || !theme.count) return 0
    return Math.max(0, Math.min(1, (theme.installed || 0) / theme.count))
  }

  spacing: Style.space(4)

  Item {
    width: parent.width
    height: progressLabel.implicitHeight

    Text {
      id: progressLabel

      anchors.left: parent.left
      textFormat: Text.PlainText
      text: {
        if (!progress.theme) return ""
        return Model.themeLabel(progress.theme) + " · "
          + (progress.theme.installed || 0) + "/" + (progress.theme.count || 0)
      }
      color: progress.dim
      font.family: progress.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      id: progressBusy

      visible: progress.busy
      anchors.left: progressLabel.right
      anchors.leftMargin: Style.space(12)
      anchors.right: progressPercent.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "• (Request in progress, please wait…)"
      color: progress.dim
      font.family: progress.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      id: progressPercent

      anchors.right: parent.right
      textFormat: Text.PlainText
      text: Model.formatPercent(progress.ratio)
      color: progress.dim
      font.family: progress.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    width: parent.width
    height: Style.space(4)
    radius: height / 2
    color: Util.alpha(progress.foreground, 0.12)

    Rectangle {
      width: parent.width * progress.ratio
      height: parent.height
      radius: parent.radius
      color: progress.accent
    }
  }
}
