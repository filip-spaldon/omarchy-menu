import QtQuick
import qs.Commons
import "Windows.js" as Windows

// One row in the Mala look: no icon, no box. The number in the margin (the
// selected row's gives way to the accent bead, Menu.qml selMarker), the
// label dimmed with the query's match in full ink, the detail line, and the
// date or running windows on the right. Same roles and pointer handling as
// ResultRow; a row of its own so that classic rows carry none of this.
Item {
  id: row
  // Made by the list from Looks.js "rows", so the menu comes through it.
  readonly property var menu: ListView.view.lookMenu

  required property int index
  required property string itemId
  required property string kind
  required property string icon
  required property string iconFont
  required property string appIcon
  required property string appId
  required property string label
  required property string target
  required property string detail
  required property string path
  required property string action
  required property int childCount
  required property string trailText

  readonly property bool hasCursor: row.menu.cursorActive && row.index === row.menu.selectedIndex && row.kind !== "example"
    && (!row.menu.systemTwoPane || row.menu.systemPane === "right")
  readonly property int windowCount: row.kind === "app" ? row.menu.appWindowCount(row.appId) : 0
  readonly property string trailShown: row.trailText.length > 0 ? row.trailText : Windows.runningLabel(row.windowCount)
  // The row's place among those on screen, 1-9; Alt+n opens it.
  readonly property int ordinal: row.index - row.menu.firstVisibleRow + 1
  readonly property bool numbered: row.kind !== "example" && row.ordinal >= 1 && row.ordinal <= 9
  readonly property int gutter: Style.space(22)
  // Where the label's middle sits, for the number and the bead.
  readonly property real labelCenterY: contentColumn.y + labelText.y + labelText.height / 2
  // The label with the match marked, worked out once per row (Menu.markRow).
  required property string marked

  // The bead follows the row with the cursor (Menu.qml, selMarker).
  onHasCursorChanged: if (row.hasCursor) row.menu.cursorRow = row
  Component.onCompleted: if (row.hasCursor) row.menu.cursorRow = row

  opacity: row.kind === "example" ? 0.7 : 1
  width: ListView.view.width
  height: row.menu.rowHeightForDetail(row.detail, row.kind)

  Text {
    visible: row.numbered && !row.hasCursor
    textFormat: Text.PlainText
    text: String(row.ordinal)
    color: row.menu.foreground
    opacity: 0.32
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.caption)
    width: row.gutter
    horizontalAlignment: Text.AlignHCenter
    y: Math.round(row.labelCenterY - height / 2)
  }

  Column {
    id: contentColumn
    anchors.left: parent.left
    anchors.leftMargin: row.menu.rowReservedBorderLeft + row.gutter + Style.space(8)
    anchors.right: trailLabel.visible ? trailLabel.left : trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      id: labelText
      textFormat: row.marked ? Text.StyledText : Text.PlainText
      width: parent.width
      text: row.marked || row.label
      // Dimmed, with the match in full ink (Menu.markRow); the
      // selected row is lit throughout.
      color: row.hasCursor ? row.menu.foreground : Util.alpha(row.menu.foreground, 0.55)
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(row.kind === "example" ? Style.font.body : Style.font.heading)
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: row.detail
      visible: row.menu.showsDetail(row.kind, row.detail)
      color: row.menu.foreground
      opacity: 0.4
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(row.kind === "example" ? Style.font.caption : Style.font.bodySmall)
      elide: Text.ElideRight
    }
  }

  Text {
    id: trailLabel
    textFormat: Text.PlainText
    visible: row.trailShown.length > 0
    text: row.trailShown
    color: row.menu.foreground
    opacity: 0.45
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    id: trail
    width: Style.space(14)
    anchors.right: parent.right
    anchors.rightMargin: row.menu.rowReservedBorderRight + Style.space(8)
    y: Math.round(row.labelCenterY - height / 2)
    textFormat: Text.PlainText
    text: row.kind === "menu" || row.kind === "link" ? "›" : ""
    color: row.menu.foreground
    opacity: 0.36
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.heading)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.menu.selectFromPointer(row.index, row, {
      x: mouseArea.mouseX,
      y: mouseArea.mouseY
    })
    onPositionChanged: function(mouse) {
      row.menu.selectFromPointer(row.index, row, mouse)
    }
    onClicked: {
      row.menu.cursorActive = true
      row.menu.selectedIndex = row.index
      row.menu.activateIndex(row.index, true)
    }
  }
}
