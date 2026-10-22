import QtQuick
import qs.Commons
import qs.Ui

// One application as a tile: icon, running badge and name, the cursor's
// highlight when it is on `tileIndex`. The Apps tab grid (AppGrid.qml) and
// All's app strips (ResultRow.qml) both draw it; the index is a row of the
// menu's row model, so hover and click go through the same cursor and
// activateIndex as a list row.
BorderSurface {
  id: tile

  required property var menu
  property int tileIndex: -1
  property string tileLabel: ""
  property string tileIcon: ""
  property string tileKind: ""
  property string tileAppId: ""

  readonly property bool hasCursor: tile.menu.cursorActive && tile.tileIndex === tile.menu.selectedIndex

  radius: tile.menu.cornerRadius
  color: tile.hasCursor ? tile.menu.selectedBackground : "transparent"
  borderSpec: tile.hasCursor ? tile.menu.selectedBorderSpec : Border.none()

  Image {
    id: iconImage
    width: Math.round(Style.space(44) * tile.menu.menuFontScale)
    height: width
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels, as the list does, or HiDPI blurs them.
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: tile.tileKind === "app" ? tile.menu.appIconSource(tile.tileIcon) : ""
    asynchronous: true
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(10)
  }

  RunningBadge {
    count: tile.tileKind === "app" ? tile.menu.appWindowCount(tile.tileAppId) : 0
    sizeScale: tile.menu.menuFontScale
    ring: tile.hasCursor ? tile.menu.selectedBackground : tile.menu.background
    x: iconImage.x + iconImage.width - width * 0.6
    y: iconImage.y + iconImage.height - height * 0.6
  }

  Text {
    textFormat: Text.PlainText
    text: tile.tileLabel
    color: tile.hasCursor ? tile.menu.selectedText : tile.menu.foreground
    font.family: tile.menu.fontFamily
    font.pixelSize: tile.menu.scaledFont(Style.font.bodySmall)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    anchors.top: iconImage.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
  }

  MouseArea {
    id: tileMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: tile.menu.selectFromPointer(tile.tileIndex, tile, { x: tileMouse.mouseX, y: tileMouse.mouseY })
    onPositionChanged: function(mouse) { tile.menu.selectFromPointer(tile.tileIndex, tile, mouse) }
    onClicked: {
      tile.menu.cursorActive = true
      tile.menu.selectedIndex = tile.tileIndex
      tile.menu.activateIndex(tile.tileIndex, true)
    }
  }
}
