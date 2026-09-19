import QtQuick
import qs.Commons
import qs.Ui

// Roadmap column shared by Help and Setup: the roadmap title, subtitle and
// upcoming items, with an optional "Propose a feature" action pinned at the
// bottom. The parent owns the surrounding divider and the width.
Item {
  id: roadmapPane

  property var roadmap: ({ title: "Roadmap", subtitle: "", items: [] })
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily
  // Label + visibility of the pinned feature action. Hidden when the label is
  // empty, so Setup can show just the roadmap.
  property string featureLabel: ""
  property int bodyPadY: Style.space(24)
  property int gutter: Style.space(28)

  signal featureClicked()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property var items: roadmap && roadmap.items ? roadmap.items : []
  readonly property string roadmapTitle: (roadmap && roadmap.title)
    ? roadmap.title : "Roadmap"
  readonly property string roadmapSubtitle: (roadmap && roadmap.subtitle)
    ? roadmap.subtitle : ""

  Flickable {
    id: roadmapFlick

    anchors.top: parent.top
    anchors.topMargin: roadmapPane.bodyPadY
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: roadmapPane.gutter
    anchors.bottom: featureButton.top
    anchors.bottomMargin: roadmapPane.bodyPadY
    contentWidth: width
    contentHeight: roadmapColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: roadmapColumn

      width: roadmapFlick.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: roadmapPane.roadmapTitle.toUpperCase()
        color: roadmapPane.dim
        font.family: roadmapPane.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        font.letterSpacing: 1.2
      }

      Item {
        width: parent.width
        height: Style.space(6)
      }

      Text {
        width: parent.width
        visible: roadmapPane.roadmapSubtitle !== ""
        textFormat: Text.PlainText
        text: roadmapPane.roadmapSubtitle
        color: roadmapPane.foreground
        font.family: roadmapPane.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Item {
        width: parent.width
        height: Style.space(12)
      }

      Repeater {
        model: roadmapPane.items

        delegate: Item {
          id: roadmapItem

          required property var modelData

          width: roadmapColumn.width
          height: roadmapItemColumn.implicitHeight + Style.space(14)

          Rectangle {
            id: roadmapDot

            x: 0
            y: Style.space(4)
            width: Style.space(9)
            height: width
            radius: width / 2
            color: roadmapPane.accent
          }

          Column {
            id: roadmapItemColumn

            anchors.left: roadmapDot.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(3)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: roadmapItem.modelData.title
              color: roadmapPane.foreground
              font.family: roadmapPane.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: roadmapItem.modelData.description
              color: roadmapPane.dim
              font.family: roadmapPane.fontFamily
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.25
              lineHeightMode: Text.ProportionalHeight
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  // Feature request: pinned at the bottom of the roadmap column.
  DashedButton {
    id: featureButton

    visible: roadmapPane.featureLabel !== ""
    anchors.left: parent.left
    anchors.right: parent.right
    // Same width and height as the themes screen's "Add remote source" button.
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.bottom: parent.bottom
    anchors.bottomMargin: roadmapPane.bodyPadY
    text: roadmapPane.featureLabel
    foreground: roadmapPane.foreground
    accent: roadmapPane.accent
    fontFamily: roadmapPane.fontFamily
    onClicked: roadmapPane.featureClicked()
  }
}
