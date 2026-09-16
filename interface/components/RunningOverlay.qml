import QtQuick
import QtQuick.Shapes
import qs.Commons

// Running overlay: an opaque scrim with an accent spinner and a pulsing caption,
// shown over a frame while an install/remove action runs. Shared by the themes
// detail pane and the fullscreen preview so both feedbacks stay identical.
Rectangle {
  id: overlay

  property bool running: false
  property string label: ""
  property color foreground: "white"
  property color background: "black"
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily

  visible: running
  color: Util.alpha(background, 0.82)

  // Swallow every click under the scrim: no action is accepted while one runs
  // (Esc cancels, handled by the panel's state machine).
  MouseArea {
    anchors.fill: parent
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(18)

    Item {
      id: spinner

      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(64)
      height: width

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Util.alpha(overlay.foreground, 0.15)
          strokeWidth: Style.space(4)
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap

          PathAngleArc {
            centerX: spinner.width / 2
            centerY: spinner.height / 2
            radiusX: spinner.width / 2 - Style.space(2)
            radiusY: spinner.height / 2 - Style.space(2)
            startAngle: 0
            sweepAngle: 359.9
          }
        }
      }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: overlay.accent
          strokeWidth: Style.space(4)
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap

          PathAngleArc {
            centerX: spinner.width / 2
            centerY: spinner.height / 2
            radiusX: spinner.width / 2 - Style.space(2)
            radiusY: spinner.height / 2 - Style.space(2)
            startAngle: 0
            sweepAngle: 90
          }
        }

        RotationAnimator on rotation {
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
          running: overlay.visible
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: overlay.label
      color: overlay.foreground
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true

      SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: overlay.visible
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
      }
    }
  }
}
