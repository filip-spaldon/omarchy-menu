import QtQuick
import qs.Commons
import qs.Ui

// The Apps tab as a grid of tiles. It shares the menu's row model and cursor
// (selectedIndex / cursorActive), so the keyboard, Enter, Delete (uninstall)
// and the search field behave exactly as they do in the list; only the
// geometry and the arrow keys differ.
GridView {
  id: grid

  required property var menu

  readonly property int columns: Math.max(1, Math.floor(width / cellWidth))

  cellWidth: Math.round(Style.space(112) * grid.menu.menuFontScale)
  cellHeight: Math.round(Style.space(104) * grid.menu.menuFontScale)
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  delegate: BorderSurface {
    id: tile

    required property int index
    required property string label
    required property string appIcon
    required property string kind

    readonly property bool hasCursor: grid.menu.cursorActive && tile.index === grid.menu.selectedIndex

    width: grid.cellWidth - Style.space(6)
    height: grid.cellHeight - Style.space(6)
    radius: grid.menu.cornerRadius
    color: tile.hasCursor ? grid.menu.selectedBackground : "transparent"
    borderSpec: tile.hasCursor ? grid.menu.selectedBorderSpec : Border.none()

    Image {
      id: tileIcon
      width: Math.round(Style.space(44) * grid.menu.menuFontScale)
      height: width
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels, as the list does, or HiDPI blurs them.
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: tile.kind === "app" ? grid.menu.appIconSource(tile.appIcon) : ""
      asynchronous: true
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(10)
    }

    Text {
      textFormat: Text.PlainText
      text: tile.label
      color: tile.hasCursor ? grid.menu.selectedText : grid.menu.foreground
      font.family: grid.menu.fontFamily
      font.pixelSize: grid.menu.scaledFont(Style.font.bodySmall)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      anchors.top: tileIcon.bottom
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
      onEntered: grid.menu.selectFromPointer(tile.index, tile, { x: tileMouse.mouseX, y: tileMouse.mouseY })
      onPositionChanged: function(mouse) { grid.menu.selectFromPointer(tile.index, tile, mouse) }
      onClicked: {
        grid.menu.cursorActive = true
        grid.menu.selectedIndex = tile.index
        grid.menu.activateIndex(tile.index, true)
      }
    }
  }
}
