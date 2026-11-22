import QtQuick
import qs.Commons

// An app in the Konstrukt look's grid: its shape (an app is a circle, in the
// accent, as in the field) and its name. The selected one gets the list's
// tint and accent edge, and its circle turns to ink like its shape.
Item {
  id: t
  required property var tile
  readonly property var menu: t.tile.menu
  readonly property int windows: t.tile.tileKind === "app" ? t.menu.appWindowCount(t.tile.tileAppId) : 0

  Rectangle {
    visible: t.tile.hasCursor
    anchors.fill: parent
    color: Util.alpha(Color.accent, 0.12)
  }
  Rectangle {
    visible: t.tile.hasCursor
    width: Math.max(3, Style.space(3))
    height: parent.height
    color: Color.accent
  }

  Rectangle {
    id: disc
    readonly property int size: Style.space(t.tile.hasCursor ? 14 : 11)
    x: Style.space(12) + (Style.space(14) - size) / 2
    anchors.verticalCenter: parent.verticalCenter
    width: size
    height: size
    radius: size / 2
    color: t.tile.hasCursor ? t.menu.foreground : Color.accent
    antialiasing: true
  }

  Text {
    id: name
    x: Style.space(34)
    width: parent.width - x - Style.space(6) - (count.visible ? count.implicitWidth + Style.space(4) : 0)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: t.tile.tileLabel
    elide: Text.ElideRight
    color: t.menu.foreground
    opacity: t.tile.hasCursor ? 1 : 0.7
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.body)
  }

  Text {
    id: count
    visible: t.windows > 0
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: "■".repeat(Math.min(3, t.windows))
    color: Color.accent
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.caption) * 0.7
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
