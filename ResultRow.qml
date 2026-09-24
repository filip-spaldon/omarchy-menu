import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One row of the result list: icon or app icon, label, detail line,
// right-hand text (a file's mtime) and a chevron for submenus. Roles come
// from the menu's row model; pointer handling goes back to the menu.
BorderSurface {
  id: row
  required property var menu

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
  readonly property bool isApp: row.kind === "app"
  readonly property bool hasIcon: row.icon.length > 0 || row.isApp

  // Command examples are a read-only hint.
  opacity: row.kind === "example" ? 0.7 : 1
  width: ListView.view.width
  height: row.menu.rowHeightForDetail(row.detail)
  radius: row.menu.cornerRadius
  color: row.hasCursor ? row.menu.selectedBackground : "transparent"
  borderSpec: row.hasCursor ? row.menu.selectedBorderSpec : Border.none()

  Rectangle {
    visible: false
    width: Style.space(4)
    height: parent.height - Style.space(18)
    radius: Math.min(row.menu.cornerRadius, Style.space(4))
    color: row.menu.selectedBackground
    anchors.left: parent.left
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    id: iconText
    textFormat: Text.PlainText
    visible: row.hasIcon && !row.isApp
    text: row.icon
    color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
    font.family: row.iconFont.length > 0 ? row.iconFont : row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.iconLarge)
    width: row.menu.iconSlotWidth
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    anchors.left: parent.left
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8)
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
  }

  Image {
    id: appIconImage
    visible: row.isApp
    width: row.menu.scaledFont(Style.font.iconLarge)
    height: row.menu.scaledFont(Style.font.iconLarge)
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels — a logical-size decode leaves
    // PNG icons upscaled and blurry on HiDPI displays.
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: row.isApp ? row.menu.appIconSource(row.appIcon) : ""
    asynchronous: true
    anchors.left: parent.left
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8) + (row.menu.iconSlotWidth - width) / 2
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
  }

  Column {
    id: contentColumn
    anchors.left: row.hasIcon ? iconText.right : parent.left
    anchors.leftMargin: row.hasIcon ? Style.space(6) : row.menu.rowReservedBorderLeft + Style.space(18)
    anchors.right: trailLabel.visible ? trailLabel.left : trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      id: labelText
      textFormat: Text.PlainText
      width: parent.width
      text: row.label
      color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.heading)
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: row.detail
      visible: row.menu.showsDetail(row.kind, row.detail)
      color: row.menu.foreground
      opacity: 0.52
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
      elide: Text.ElideRight
    }
  }

  Text {
    id: trailLabel
    textFormat: Text.PlainText
    visible: row.trailText.length > 0
    text: row.trailText
    color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
    opacity: 0.45
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
  }

  Row {
    id: trail
    width: Style.space(14)
    anchors.right: parent.right
    anchors.rightMargin: row.menu.rowReservedBorderRight + Style.space(8)
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
    spacing: 0

    Text {
      textFormat: Text.PlainText
      visible: false
      text: row.childCount
      color: row.menu.foreground
      opacity: 0.45
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.body)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: row.kind === "menu" || row.kind === "link" ? "›" : ""
      color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
      opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.heading)
      font.weight: Font.Normal
      anchors.verticalCenter: parent.verticalCenter
    }
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
