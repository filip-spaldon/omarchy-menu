import QtQuick
import qs.Commons
import "KeySheet.js" as KeySheet

// The "?" key sheet on the card (Ctrl+?): every key of KeySheet.CHEATSHEET,
// in groups, two columns. The card's looks set it in their own type: classic
// outlined keycaps; Mala bare lowercase words, the keys in full ink and
// what they do dimmed; Wayfinder each group a line with its keys
// as stops, under an interchange hexagon. The full-screen looks draw their
// own sheet (AxisView, KonstruktView).
Rectangle {
  id: sheet
  required property var menu
  readonly property bool mala: sheet.menu.drawnLook === "mala"
  readonly property bool wayfinder: sheet.menu.drawnLook === "wayfinder"
  // Wayfinder's line gutter.
  readonly property int lineGutter: Style.space(22)

  color: Qt.rgba(sheet.menu.background.r, sheet.menu.background.g, sheet.menu.background.b, 1)
  radius: sheet.menu.rowRadius

  Flow {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(18)

    Repeater {
      model: KeySheet.CHEATSHEET
      Column {
        id: group
        required property var modelData
        width: (parent.width - Style.space(18)) / 2
        spacing: sheet.mala ? Style.space(4) : Style.space(6)

        // The title, as the look's section headers.
        Row {
          spacing: Style.space(4)
          Text {
            visible: sheet.wayfinder
            textFormat: Text.PlainText
            text: "\u{F02D9}"
            color: sheet.menu.foreground
            opacity: 0.7
            width: sheet.lineGutter
            horizontalAlignment: Text.AlignHCenter
            font.family: sheet.menu.fontFamily
            font.pixelSize: sheet.menu.scaledFont(Style.font.heading)
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            textFormat: Text.PlainText
            text: sheet.menu.headerLower ? group.modelData.title.toLowerCase() : group.modelData.title.toUpperCase()
            color: sheet.menu.foreground
            opacity: sheet.mala || sheet.wayfinder ? sheet.menu.headerOpacity : 0.5
            font.family: sheet.menu.fontFamily
            font.pixelSize: sheet.menu.scaledFont(Style.font.caption)
            font.weight: sheet.menu.headerWeight
            font.letterSpacing: sheet.menu.headerSpacing
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          width: parent.width
          height: keyColumn.implicitHeight

          // Wayfinder: the group's line, the keys its stops.
          Rectangle {
            visible: sheet.wayfinder
            x: Math.round((sheet.lineGutter - width) / 2)
            width: Math.max(2, Style.space(2))
            height: parent.height
            color: Util.alpha(sheet.menu.foreground, 0.22)
          }

          Column {
            id: keyColumn
            width: parent.width
            spacing: sheet.mala ? Style.space(3) : Style.space(6)

            Repeater {
              model: group.modelData.keys
              Row {
                id: keyRow
                required property var modelData
                spacing: Style.space(8)

                // Wayfinder's stop.
                Item {
                  visible: sheet.wayfinder
                  width: sheet.lineGutter - Style.space(8)
                  height: parent.height
                  Rectangle {
                    width: Style.space(8)
                    height: width
                    radius: width / 2
                    x: Math.round((sheet.lineGutter - width) / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    color: sheet.menu.background
                    border.width: Math.max(1, Style.space(2))
                    border.color: Util.alpha(sheet.menu.foreground, 0.45)
                  }
                }

                // Mala: the key, a bare word in full ink.
                Text {
                  visible: sheet.mala
                  textFormat: Text.PlainText
                  text: KeySheet.keyGlyphs(keyRow.modelData[0].toLowerCase())
                  color: sheet.menu.foreground
                  font.family: sheet.menu.fontFamily
                  font.pixelSize: sheet.menu.scaledFont(Style.font.bodySmall)
                  anchors.verticalCenter: parent.verticalCenter
                }

                // Classic and Wayfinder: the key as a keycap (Wayfinder's in
                // the weight of its map references).
                Rectangle {
                  visible: !sheet.mala
                  width: Math.max(capKey.implicitWidth + Style.space(8), Style.space(30))
                  height: capKey.implicitHeight + Style.space(3)
                  radius: Style.space(3)
                  color: "transparent"
                  border.width: 1
                  border.color: Util.alpha(sheet.menu.foreground, 0.35)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: capKey
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: KeySheet.keyGlyphs(keyRow.modelData[0])
                    color: sheet.menu.foreground
                    opacity: sheet.wayfinder ? 0.7 : 1
                    font.family: sheet.menu.fontFamily
                    font.pixelSize: sheet.menu.scaledFont(Style.font.caption)
                    font.weight: sheet.wayfinder ? Font.DemiBold : Font.Normal
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: sheet.mala ? keyRow.modelData[1].toLowerCase() : keyRow.modelData[1]
                  color: sheet.menu.foreground
                  opacity: sheet.mala ? sheet.menu.categoryDim : 0.75
                  font.family: sheet.menu.fontFamily
                  font.pixelSize: sheet.menu.scaledFont(Style.font.bodySmall)
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }
    }
  }
}
