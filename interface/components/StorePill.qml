import QtQuick
import qs.Commons
import qs.Ui

// Global store pill: "<N> available | <M> installed". Optionally appends an
// accent cap warning (the bulk-install storage limit) that opens Setup →
// Download. Shared by the themes/wallpapers header and the preview header, so
// the same counters read everywhere. Height follows `controlHeight` so the pill
// lines up with a sibling Button.
BorderSurface {
  id: store

  property int wallpapers: 0
  property int installed: 0
  // Accent segment text; empty hides it (e.g. on the Setup screen).
  property string limitReason: ""
  // Height of the sibling control to match (a Button's implicitHeight).
  property real controlHeight: 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  // The cap warning was clicked: jump to the caps in Setup → Download.
  signal limitActivated()

  width: storeRow.implicitWidth + leftPadding + rightPadding
  height: controlHeight > 0 ? controlHeight : storeRow.implicitHeight
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.controlSpec("normal", store.foreground, store.accent)
  leftPadding: Style.spacing.controlPaddingX
  rightPadding: Style.spacing.controlPaddingX

  Row {
    id: storeRow

    anchors.centerIn: parent
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: store.wallpapers + " available"
      color: store.foreground
      font.family: store.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, Style.normalBorderWidth)
      height: storeRow.implicitHeight
      color: Util.alpha(store.foreground, 0.25)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: store.installed + " installed"
      color: store.foreground
      font.family: store.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      visible: store.limitReason !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, Style.normalBorderWidth)
      height: storeRow.implicitHeight
      color: Util.alpha(store.foreground, 0.25)
    }

    Text {
      visible: store.limitReason !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: store.limitReason
      color: store.accent
      font.family: store.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.capitalization: Font.AllUppercase

      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: store.limitActivated() }
    }
  }
}
