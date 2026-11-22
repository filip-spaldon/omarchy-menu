import QtQuick
import qs.Commons

// An app in the Axis look's grid: an icon and its name in spaced capitals,
// no box. The grid's rows move through the horizontal line (AxisView.qml);
// the selected app is in full ink and underlined in accent, the rest recede.
Item {
  id: t
  required property var tile
  readonly property var menu: t.tile.menu
  readonly property int windows: t.tile.tileKind === "app" ? t.menu.appWindowCount(t.tile.tileAppId) : 0

  Image {
    id: icon
    width: Math.round(Style.space(36) * t.menu.menuFontScale)
    height: width
    fillMode: Image.PreserveAspectFit
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: t.tile.tileKind === "app" ? t.menu.appIconSource(t.tile.tileIcon) : ""
    asynchronous: true
    anchors.horizontalCenter: parent.horizontalCenter
    y: Style.space(12)
    opacity: t.tile.hasCursor ? 1 : 0.5
    scale: t.tile.hasCursor ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  RunningBadge {
    count: t.windows
    sizeScale: t.menu.menuFontScale
    ring: t.menu.background
    x: icon.x + icon.width - width * 0.6
    y: icon.y + icon.height - height * 0.6
  }

  Text {
    id: name
    x: Style.space(4)
    width: parent.width - Style.space(8)
    y: icon.y + icon.height + Style.space(10)
    textFormat: Text.PlainText
    text: t.tile.tileLabel.toUpperCase()
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    color: t.menu.foreground
    opacity: t.tile.hasCursor ? 1 : 0.45
    font.family: t.menu.fontFamily
    font.pixelSize: t.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 1.5
  }

  Rectangle {
    visible: t.tile.hasCursor
    anchors.horizontalCenter: parent.horizontalCenter
    y: name.y + name.contentHeight + Style.space(5)
    width: Math.min(name.contentWidth, name.width)
    height: Math.max(2, Style.spacing.hairline * 2)
    color: Color.accent
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
