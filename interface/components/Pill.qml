import QtQuick
import qs.Commons
import qs.Ui

// Same anatomy as the `detail` pill in Ui/PanelHero.qml: transparent fill,
// themed border, caption text. The tint carries the meaning instead of a
// colored blob. `glyph` is an optional leading mark (e.g. a check).
BorderSurface {
  id: pill

  property string label: ""
  property string glyph: ""
  property color tint: Color.accent
  property color fill: "transparent"
  property string fontFamily: Style.font.menuFamily
  // Sizing knobs so the same pill can shrink down to a grid thumbnail.
  property int labelPixelSize: Style.font.caption
  property int hPadding: Style.space(22)
  property int vPadding: Style.space(12)

  implicitWidth: pillRow.implicitWidth + pill.hPadding
  implicitHeight: pillRow.implicitHeight + pill.vPadding
  color: pill.fill
  radius: Style.cornerRadius
  borderSpec: Border.flat(pill.tint, Math.max(1, Style.normalBorderWidth))

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      visible: pill.glyph !== ""
      textFormat: Text.PlainText
      text: pill.glyph
      color: pill.tint
      font.family: pill.fontFamily
      font.pixelSize: pill.labelPixelSize
    }

    Text {
      id: pillText
      textFormat: Text.PlainText
      text: pill.label
      color: pill.tint
      font.family: pill.fontFamily
      font.pixelSize: pill.labelPixelSize
    }
  }
}
