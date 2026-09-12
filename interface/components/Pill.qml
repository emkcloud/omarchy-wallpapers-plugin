import QtQuick
import qs.Commons
import qs.Ui

// Same anatomy as the `detail` pill in Ui/PanelHero.qml: transparent fill,
// themed border, caption text. The tint carries the meaning instead of a
// colored blob.
BorderSurface {
  id: pill

  property string label: ""
  property color tint: Color.accent
  property string fontFamily: Style.font.menuFamily

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
    font.family: pill.fontFamily
    font.pixelSize: Style.font.caption
  }
}
