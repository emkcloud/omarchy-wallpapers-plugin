import QtQuick
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

// Renders the constrained Markdown subset produced by `Model.parseMarkdown`
// (headings, paragraphs, fenced code, tables, notes, lists, rules) as a
// scrolling column of typed blocks. QML has no Markdown engine, so the parser
// lives in JS and each block type gets a purpose-built delegate here: that is
// what keeps the typography on the Omarchy tokens instead of the rich-text
// defaults.
Item {
  id: view

  property var blocks: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string accentString: String(accent)
  readonly property int blockSpacing: Style.space(16)
  // Extra air above a heading, on top of `blockSpacing`, so a new section
  // reads as a break (a table or paragraph right above it no longer crowds it).
  readonly property int headingTopGap: Style.space(10)

  // Scroll by (roughly) one visible page; used by PageUp/PageDown on Help.
  function pageBy(direction) {
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    var page = Math.max(1, flick.height - Style.space(24))
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * page))
  }

  Flickable {
    id: flick

    anchors.fill: parent
    contentWidth: width
    contentHeight: column.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: flick.width
      spacing: view.blockSpacing

      Repeater {
        model: view.blocks

        delegate: Item {
          id: blockHost
          required property var modelData

          width: column.width
          height: loader.item ? loader.item.height : 0

          Loader {
            id: loader

            width: blockHost.width
            sourceComponent: {
              var type = blockHost.modelData ? blockHost.modelData.type : ""
              if (type === "heading") return headingComp
              if (type === "code") return codeComp
              if (type === "table") return tableComp
              if (type === "note") return noteComp
              if (type === "list") return listComp
              if (type === "rule") return ruleComp
              return paragraphComp
            }
            onLoaded: if (item) item.block = blockHost.modelData
          }
        }
      }
    }
  }

  // ---- blocks --------------------------------------------------------------

  Component {
    id: paragraphComp

    Item {
      id: paragraphRoot
      property var block

      width: parent ? parent.width : 0
      implicitHeight: paragraphText.implicitHeight
      height: implicitHeight

      Text {
        id: paragraphText
        width: parent.width
        textFormat: Text.StyledText
        text: Model.inlineMarkdown(paragraphRoot.block ? paragraphRoot.block.text : "",
          view.accentString)
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        lineHeight: 1.4
        lineHeightMode: Text.ProportionalHeight
        wrapMode: Text.WordWrap
        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
      }
    }
  }

  Component {
    id: headingComp

    Item {
      id: headingRoot
      property var block

      width: parent ? parent.width : 0
      implicitHeight: headingText.implicitHeight + view.headingTopGap
      height: implicitHeight

      Text {
        id: headingText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        textFormat: Text.StyledText
        text: Model.inlineMarkdown(
          headingRoot.block ? String(headingRoot.block.text).toUpperCase() : "",
          view.accentString)
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: headingRoot.block && headingRoot.block.level <= 2
          ? Style.font.heading : Style.font.subtitle
        font.bold: true
        wrapMode: Text.WordWrap
        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
      }
    }
  }

  Component {
    id: codeComp

    BorderSurface {
      id: codeRoot
      property var block

      width: parent ? parent.width : 0
      implicitHeight: codeColumn.implicitHeight + topPadding + bottomPadding
      height: implicitHeight
      padding: Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(view.foreground, 0.06)
      borderSpec: Border.flat(Util.alpha(view.foreground, 0.14),
        Math.max(1, Style.normalBorderWidth))

      // Off-screen editor used only to place the code on the system clipboard.
      TextEdit {
        id: copier
        visible: false
        text: codeRoot.block ? codeRoot.block.text : ""
      }

      Column {
        id: codeColumn
        width: codeRoot.width - codeRoot.leftPadding - codeRoot.rightPadding
        spacing: Style.space(8)

        Row {
          id: codeHeader
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: codeLang
            textFormat: Text.PlainText
            text: codeRoot.block && codeRoot.block.lang ? codeRoot.block.lang : "shell"
            color: view.dim
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Item {
            width: Math.max(0, codeHeader.width - codeLang.width - copyLabel.width
              - codeHeader.spacing * 2)
            height: 1
          }

          Text {
            id: copyLabel

            property bool copied: false

            textFormat: Text.PlainText
            text: copied ? "copied" : "copy"
            color: copied ? view.accent : (copyHover.hovered ? view.foreground : view.dim)
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption

            HoverHandler {
              id: copyHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              onTapped: {
                copier.selectAll()
                copier.copy()
                copyLabel.copied = true
                copyReset.restart()
              }
            }

            Timer {
              id: copyReset
              interval: 1500
              onTriggered: copyLabel.copied = false
            }
          }
        }

        Text {
          id: codeText
          width: parent.width
          textFormat: Text.PlainText
          text: codeRoot.block ? codeRoot.block.text : ""
          color: view.foreground
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.35
          lineHeightMode: Text.ProportionalHeight
          wrapMode: Text.WrapAnywhere
        }
      }
    }
  }

  Component {
    id: tableComp

    BorderSurface {
      id: tableRoot
      property var block

      width: parent ? parent.width : 0
      implicitHeight: tableColumn.implicitHeight
        + tableRoot.contentTopInset + tableRoot.contentBottomInset
      height: implicitHeight
      // No outer padding: the cells pad themselves so the row separators can
      // bleed to the table's inner edge.
      padding: 0
      radius: Style.cornerRadius
      color: "transparent"
      borderSpec: Border.flat(Util.alpha(view.foreground, 0.14),
        Math.max(1, Style.normalBorderWidth))

      readonly property int cellPadX: Style.space(16)
      readonly property int cellPadY: Style.space(12)
      readonly property int cellGap: Style.space(16)

      // The first column (keys/commands) stays narrow; every other column
      // shares the rest, so descriptions get the room. 0.28 keeps "pageup /
      // pagedown" on one line.
      function columnWidth(index, count, total) {
        var usable = total - cellGap * (count - 1)
        if (count <= 1) return Math.max(0, usable)
        var first = usable * 0.28
        return index === 0 ? first : (usable - first) / (count - 1)
      }

      Column {
        id: tableColumn

        anchors.left: parent.left
        anchors.leftMargin: tableRoot.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: tableRoot.contentRightInset
        anchors.top: parent.top
        anchors.topMargin: tableRoot.contentTopInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: tableRoot.contentBottomInset
        spacing: 0

        // Header: dim uppercase labels over a faint fill.
        Item {
          id: tableHeader

          width: parent.width
          height: tableHeaderRow.implicitHeight + tableRoot.cellPadY * 2

          Rectangle {
            anchors.fill: parent
            color: Util.alpha(view.foreground, 0.04)
            topLeftRadius: Math.max(0, Style.cornerRadius - tableRoot.borderTop)
            topRightRadius: Math.max(0, Style.cornerRadius - tableRoot.borderTop)
          }

          Row {
            id: tableHeaderRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: tableRoot.cellPadX
            anchors.rightMargin: tableRoot.cellPadX
            anchors.verticalCenter: parent.verticalCenter
            spacing: tableRoot.cellGap

            readonly property int cellCount: tableRoot.block && tableRoot.block.headers
              ? tableRoot.block.headers.length : 0

            Repeater {
              model: tableRoot.block ? tableRoot.block.headers : []

              delegate: Text {
                required property var modelData
                required property int index

                width: tableRoot.columnWidth(index, tableHeaderRow.cellCount,
                  tableHeaderRow.width)
                textFormat: Text.StyledText
                text: Model.inlineMarkdown(String(modelData).toUpperCase(),
                  view.accentString)
                color: view.dim
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: view.foreground
          strength: 0.12
        }

        Repeater {
          model: tableRoot.block ? tableRoot.block.rows : []

          delegate: Column {
            id: tableRow

            required property var modelData
            required property int index

            width: tableColumn.width
            spacing: 0

            Item {
              width: parent.width
              height: tableRowCells.implicitHeight + tableRoot.cellPadY * 2

              Row {
                id: tableRowCells

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: tableRoot.cellPadX
                anchors.rightMargin: tableRoot.cellPadX
                anchors.verticalCenter: parent.verticalCenter
                spacing: tableRoot.cellGap

                readonly property int cellCount: tableRow.modelData
                  ? tableRow.modelData.length : 0

                Repeater {
                  model: tableRow.modelData || []

                  delegate: Text {
                    required property var modelData
                    required property int index

                    width: tableRoot.columnWidth(index, tableRowCells.cellCount,
                      tableRowCells.width)
                    textFormat: Text.StyledText
                    text: Model.inlineMarkdown(modelData, view.accentString)
                    // The first column carries the key/command: keep it accented.
                    color: index === 0 ? view.accent : view.foreground
                    font.family: view.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            PanelSeparator {
              visible: tableRoot.block
                && tableRow.index < tableRoot.block.rows.length - 1
              width: parent.width
              foreground: view.foreground
              strength: 0.07
            }
          }
        }
      }
    }
  }

  Component {
    id: noteComp

    BorderSurface {
      id: noteRoot
      property var block

      width: parent ? parent.width : 0
      implicitHeight: noteRow.implicitHeight + topPadding + bottomPadding
      height: implicitHeight
      padding: Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(view.accent, 0.08)
      borderSpec: Border.flat(Util.alpha(view.accent, 0.35),
        Math.max(1, Style.normalBorderWidth))

      Row {
        id: noteRow
        width: parent.width
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(3)
          height: noteText.implicitHeight
          radius: width / 2
          color: view.accent
        }

        Text {
          id: noteText
          width: noteRow.width - Style.space(3) - noteRow.spacing
          textFormat: Text.StyledText
          text: Model.inlineMarkdown(noteRoot.block ? noteRoot.block.text : "",
            view.accentString)
          color: view.dim
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.35
          lineHeightMode: Text.ProportionalHeight
          wrapMode: Text.WordWrap
          onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }
      }
    }
  }

  Component {
    id: listComp

    Item {
      id: listRoot
      property var block

      // A list of multi-line items reads as a stack of blocks and gets a little
      // air between them; one-line entries stay compact, like plain lines.
      readonly property bool blocky: {
        var items = listRoot.block ? listRoot.block.items : []
        for (var i = 0; i < items.length; i++)
          if (items[i] && items[i].multiline) return true
        return false
      }

      width: parent ? parent.width : 0
      implicitHeight: listColumn.implicitHeight
      height: implicitHeight

      Column {
        id: listColumn
        width: parent.width
        spacing: listRoot.blocky ? Style.space(6) : Style.space(2)

        Repeater {
          model: listRoot.block ? listRoot.block.items : []

          delegate: Row {
            id: listRow

            required property var modelData
            required property int index

            readonly property int depth: modelData && modelData.depth ? modelData.depth : 0

            x: depth * Style.space(18)
            width: listColumn.width - x
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: listRoot.block && listRoot.block.ordered ? (index + 1) + "." : "•"
              color: view.accent
              font.family: view.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: listRow.width - Style.space(22)
              textFormat: Text.StyledText
              text: Model.inlineMarkdown(modelData ? modelData.text : "",
                view.accentString)
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.body
              // Same line height as the paragraphs and notes, so a list does not
              // read tighter than the rest of the guide.
              lineHeight: 1.4
              lineHeightMode: Text.ProportionalHeight
              wrapMode: Text.WordWrap
              onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            }
          }
        }
      }
    }
  }

  Component {
    id: ruleComp

    Item {
      property var block

      width: parent ? parent.width : 0
      implicitHeight: Style.space(1)
      height: implicitHeight

      PanelSeparator {
        anchors.fill: parent
        foreground: view.foreground
      }
    }
  }
}
