import QtQuick
import qs.Commons

// An app in the Wayfinder look's grid: a stop on a line. Each row of the grid
// is one line running through its stops; the route is lit in accent up to
// the selected stop, which is an interchange ring with its name on a filled
// plate. The map reference (column letter, row number) sits in the corner,
// as on a printed map.
Item {
  id: t
  required property var tile
  readonly property var menu: t.tile.menu
  readonly property int lineY: Style.space(48)
  readonly property bool passed: t.menu.cursorActive && t.tile.tileIndex < t.menu.selectedIndex
  readonly property int windows: t.tile.tileKind === "app" ? t.menu.appWindowCount(t.tile.tileAppId) : 0

  // The line, a little past the tile on both sides so a row of stops reads
  // as one line.
  Rectangle {
    x: -Style.space(3)
    width: parent.width + Style.space(6)
    y: t.lineY - height / 2
    height: t.passed || t.tile.hasCursor ? Style.space(3) : Style.space(2)
    color: t.passed ? Color.accent : Util.alpha(t.menu.foreground, 0.22)
  }
  // The route stops at the selected stop: lit up to its middle only.
  Rectangle {
    visible: t.tile.hasCursor
    x: -Style.space(3)
    width: parent.width / 2 + Style.space(3)
    y: t.lineY - height / 2
    height: Style.space(3)
    color: Color.accent
  }

  Image {
    id: icon
    width: Math.round(Style.space(30) * t.menu.menuFontScale)
    height: width
    fillMode: Image.PreserveAspectFit
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: t.tile.tileKind === "app" ? t.menu.appIconSource(t.tile.tileIcon) : ""
    asynchronous: true
    anchors.horizontalCenter: parent.horizontalCenter
    y: t.lineY - height - Style.space(12)
    opacity: t.tile.hasCursor ? 1 : 0.85
  }

  RunningBadge {
    count: t.windows
    sizeScale: t.menu.menuFontScale
    ring: t.menu.background
    x: icon.x + icon.width - width * 0.6
    y: icon.y + icon.height - height * 0.6
  }

  Rectangle {
    id: ring
    readonly property int size: t.tile.hasCursor ? Style.space(16) : Style.space(9)
    width: size
    height: size
    radius: size / 2
    anchors.horizontalCenter: parent.horizontalCenter
    y: t.lineY - size / 2
    color: t.menu.background
    border.width: t.tile.hasCursor ? Style.space(3) : Math.max(1, Style.space(2))
    border.color: t.tile.hasCursor || t.passed ? Color.accent : Util.alpha(t.menu.foreground, 0.45)
    Rectangle {
      visible: t.tile.hasCursor
      anchors.centerIn: parent
      width: Style.space(4)
      height: width
      radius: width / 2
      color: Color.accent
    }
  }

  // The stop's name; the selected one on a plate in the selection colours.
  Rectangle {
    visible: t.tile.hasCursor
    x: name.x + (name.width - name.contentWidth) / 2 - Style.space(6)
    y: name.y - Style.space(2)
    width: name.contentWidth + Style.space(12)
    height: name.contentHeight + Style.space(4)
    radius: t.menu.rowRadius
    color: t.menu.selectedBackground
  }
  Text {
    id: name
    x: Style.space(4)
    width: parent.width - Style.space(8)
    y: t.lineY + Style.space(14)
    textFormat: Text.PlainText
    text: t.tile.tileLabel
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    color: t.tile.hasCursor ? t.menu.selectedText : t.menu.foreground
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.bodySmall)
    font.weight: t.tile.hasCursor ? Font.DemiBold : Font.Normal
  }

  // The map reference: column letter, row number.
  Text {
    x: Style.space(4)
    y: Style.space(2)
    textFormat: Text.PlainText
    text: String.fromCharCode(65 + (t.tile.tileCol % 26)) + (t.tile.tileRow + 1)
    color: t.tile.hasCursor ? Color.accent : t.menu.foreground
    opacity: t.tile.hasCursor ? 1 : 0.35
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 1
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: t.tile.hover(t, { x: mouse.mouseX, y: mouse.mouseY })
    onPositionChanged: function(m) { t.tile.hover(t, m) }
    onClicked: t.tile.open()
  }
}
