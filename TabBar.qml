import QtQuick
import qs.Commons

// The row of tab chips under the search field. Purely presentational: the
// menu owns which tab is active and what switching means; this only draws
// the chips and reports clicks. A Flow, so a narrow card (style.json
// "cardWidth") wraps the chips onto a second line instead of spilling out.
Flow {
  id: bar

  required property var tabs
  required property string activeTab
  required property string fontFamily
  required property color foreground
  required property color accent
  required property int fontSize

  signal tabClicked(string id)

  spacing: Style.space(6)
  width: parent ? parent.width : implicitWidth

  Repeater {
    model: bar.tabs

    Rectangle {
      id: chip

      required property var modelData
      readonly property bool active: chip.modelData.id === bar.activeTab

      width: chipRow.implicitWidth + Style.space(20)
      height: chipRow.implicitHeight + Style.space(10)
      radius: height / 2
      color: chip.active
        ? Util.alpha(bar.accent, 0.22)
        : (chipMouse.containsMouse ? Util.alpha(bar.accent, 0.10) : Util.alpha(bar.foreground, 0.07))

      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: chip.modelData.icon
          color: chip.active ? bar.accent : bar.foreground
          opacity: chip.active ? 1 : 0.7
          font.family: bar.fontFamily
          font.pixelSize: bar.fontSize
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: chip.modelData.label
          color: chip.active ? bar.accent : bar.foreground
          opacity: chip.active ? 1 : 0.8
          font.family: bar.fontFamily
          font.pixelSize: bar.fontSize
          font.weight: chip.active ? Font.DemiBold : Font.Normal
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: bar.tabClicked(chip.modelData.id)
      }
    }
  }
}
