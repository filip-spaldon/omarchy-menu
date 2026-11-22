import QtQuick
import qs.Commons

// An app in the Mala look's grid: only its name, a word among words. No icon
// or box; names are dimmed and the selected one is in full ink with the
// accent bead before it, as Mala's rows are. Open windows are a small count
// after the name.
Item {
  id: t
  required property var tile
  readonly property var menu: t.tile.menu
  readonly property int windows: t.tile.tileKind === "app" ? t.menu.appWindowCount(t.tile.tileAppId) : 0

  Text {
    id: bead
    visible: t.tile.hasCursor
    textFormat: Text.PlainText
    text: "●"
    color: Color.accent
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.caption)
    width: Style.space(16)
    horizontalAlignment: Text.AlignHCenter
    anchors.verticalCenter: label.verticalCenter
  }

  Text {
    id: label
    x: Style.space(16)
    width: Math.min(implicitWidth, parent.width - x - (count.visible ? count.implicitWidth + Style.space(6) : 0))
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: t.tile.tileLabel
    elide: Text.ElideRight
    color: t.menu.foreground
    opacity: t.tile.hasCursor ? 1 : 0.55
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.body)
  }

  Text {
    id: count
    visible: t.windows > 0
    x: label.x + label.width + Style.space(4)
    y: label.y
    textFormat: Text.PlainText
    text: String(t.windows)
    color: Color.accent
    opacity: 0.8
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.caption)
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
