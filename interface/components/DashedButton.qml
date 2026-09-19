import QtQuick
import QtQuick.Shapes
import qs.Commons

// Dashed-outline action button (the "+ Add remote source" treatment): a dotted
// rounded border with a centred caption. Rectangle borders cannot dash, so the
// outline is a Shape. Reused by the Help sidebar for "Propose a feature".
Item {
  id: root

  property string text: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  property bool active: false

  signal clicked()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color markColor: root.active ? root.accent : root.dim

  // Same control height as the plugin's regular buttons (and the themes
  // screen's "Add remote source" dashed button), so the two dashed actions are
  // the same size.
  implicitHeight: Style.space(36)
  height: implicitHeight

  Shape {
    id: outline

    anchors.fill: parent

    readonly property real r: Math.max(0, Style.cornerRadius)
    readonly property real w: width - outlinePath.strokeWidth
    readonly property real h: height - outlinePath.strokeWidth
    readonly property real inset: outlinePath.strokeWidth / 2

    ShapePath {
      id: outlinePath
      strokeColor: root.markColor
      strokeWidth: 1
      fillColor: "transparent"
      strokeStyle: ShapePath.DashLine
      dashPattern: [3, 3]
      capStyle: ShapePath.FlatCap

      startX: outline.inset + outline.r
      startY: outline.inset
      PathLine {
        x: outline.inset + outline.w - outline.r
        y: outline.inset
      }
      PathArc {
        x: outline.inset + outline.w
        y: outline.inset + outline.r
        radiusX: outline.r
        radiusY: outline.r
      }
      PathLine {
        x: outline.inset + outline.w
        y: outline.inset + outline.h - outline.r
      }
      PathArc {
        x: outline.inset + outline.w - outline.r
        y: outline.inset + outline.h
        radiusX: outline.r
        radiusY: outline.r
      }
      PathLine {
        x: outline.inset + outline.r
        y: outline.inset + outline.h
      }
      PathArc {
        x: outline.inset
        y: outline.inset + outline.h - outline.r
        radiusX: outline.r
        radiusY: outline.r
      }
      PathLine {
        x: outline.inset
        y: outline.inset + outline.r
      }
      PathArc {
        x: outline.inset + outline.r
        y: outline.inset
        radiusX: outline.r
        radiusY: outline.r
      }
    }
  }

  Text {
    id: label

    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.markColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  HoverHandler { cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
