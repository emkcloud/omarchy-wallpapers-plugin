import QtQuick
import qs.Commons

// emkcloud brand mark, same size slot as the nerd-font glyph it replaces
// (`Style.font.displayLarge`) and rounded like every other image here. The
// glyph stays as fallback if the file is missing (plugin dir not resolved).
Item {
  id: heroLogo

  property string glyph: ""
  property url source: ""
  property color foreground: Color.menu.text
  property string fontFamily: Style.font.menuFamily

  readonly property bool ready: heroLogoImage.status === Image.Ready

  implicitWidth: Style.font.displayLarge
  implicitHeight: Style.font.displayLarge

  RoundedImage {
    id: heroLogoImage
    anchors.fill: parent
    visible: heroLogo.ready
    source: heroLogo.source
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    visible: !heroLogo.ready
    text: heroLogo.glyph
    color: heroLogo.foreground
    font.family: heroLogo.fontFamily
    font.pixelSize: Style.font.display
  }
}
