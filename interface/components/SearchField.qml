import QtQuick
import qs.Commons
import qs.Ui

// Omarchy-style search box: a real bordered surface (not a QQC TextField, so
// arrow keys keep driving the panel cursor). `/` enters it, Esc clears then
// exits, the X empties the filter while staying focused. The focused state
// leans on the accent (not the kit's fainter focus border) so active reads as
// active. The parent owns the state; this atom only renders and reports.
BorderSurface {
  id: field

  property string text: ""
  property string placeholder: ""
  property bool active: false
  property color foreground: "white"
  property color accent: "white"
  property string fontFamily: ""

  signal activated()
  signal cleared()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color idleBorder: Util.alpha(foreground, 0.18)

  height: Math.max(searchGlyph.implicitHeight, searchQuery.implicitHeight)
    + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: active ? Util.alpha(accent, 0.10) : "transparent"
  borderSpec: active
    ? Border.flat(accent, Math.max(1, Style.normalBorderWidth))
    : Border.flat(idleBorder, Math.max(1, Style.normalBorderWidth))
  leftPadding: Style.spacing.controlPaddingX
  rightPadding: Style.spacing.controlPaddingX
  topPadding: Style.spacing.controlPaddingY
  bottomPadding: Style.spacing.controlPaddingY

  // Click anywhere on the field to take over the keyboard.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: field.activated()
  }

  Text {
    id: searchGlyph

    anchors.left: parent.left
    anchors.leftMargin: field.contentLeftInset
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: "󰍉"
    color: field.active ? field.accent : field.dim
    font.family: field.fontFamily
    font.pixelSize: Style.font.icon
  }

  Text {
    id: searchQuery

    anchors.left: searchGlyph.right
    anchors.leftMargin: Style.space(8)
    anchors.right: searchClear.visible ? searchClear.left : parent.right
    anchors.rightMargin: searchClear.visible ? Style.space(6) : field.contentRightInset
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: field.text || field.placeholder
    color: field.text ? field.foreground : field.dim
    opacity: field.text ? 1 : 0.58
    font.family: field.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // Blinking caret, right after the typed text.
  Rectangle {
    id: searchCaret

    visible: field.active
    width: 1
    height: searchQuery.implicitHeight
    color: field.accent
    anchors.verticalCenter: parent.verticalCenter
    x: {
      var pos = field.text === ""
        ? searchQuery.x
        : Math.min(searchQuery.x + searchQuery.contentWidth + Style.space(2),
            searchQuery.x + searchQuery.width)
      if (searchClear.visible) pos = Math.min(pos, searchClear.x - Style.space(4))
      return pos
    }

    SequentialAnimation on opacity {
      running: searchCaret.visible
      loops: Animation.Infinite
      NumberAnimation { to: 0.0; duration: 500 }
      NumberAnimation { to: 1.0; duration: 500 }
    }
  }

  // Clear button: empties the filter but keeps the field focused.
  Text {
    id: searchClear

    visible: field.active && field.text !== ""
    anchors.right: parent.right
    anchors.rightMargin: field.contentRightInset
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: "✕"
    color: clearHover.hovered ? field.foreground : field.dim
    font.family: field.fontFamily
    font.pixelSize: Style.font.icon

    HoverHandler {
      id: clearHover
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      onTapped: field.cleared()
    }
  }
}
