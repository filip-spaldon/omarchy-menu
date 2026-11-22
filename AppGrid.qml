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

  cellWidth: Math.max(1, Math.min(Math.round(Style.space(112) * grid.menu.menuFontScale), parent ? parent.width : 100000))
  cellHeight: Math.round(Style.space(104) * grid.menu.menuFontScale)
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // The pinned strip's rows end padded to whole rows, so it follows the
  // column count.
  onColumnsChanged: if (grid.menu.gridActive && grid.menu.pinnedCount > 0) grid.menu.rebuildDisplay(true)

  // Behind the pinned apps (the model's first rows; see Menu.pinnedCount):
  // the accent tint and outline the list's pinned strip has.
  Rectangle {
    parent: grid.contentItem
    z: -1
    visible: grid.menu.pinnedCount > 0
    width: grid.columns * grid.cellWidth
    height: Math.ceil(grid.menu.pinnedCount / grid.columns) * grid.cellHeight
    radius: grid.menu.cornerRadius
    color: grid.menu.pinnedBackground
    border.width: Math.max(1, Style.space(1))
    border.color: grid.menu.pinnedBorder

    PinBadge {
      sizeScale: grid.menu.menuFontScale
      fontFamily: grid.menu.fontFamily
      ring: grid.menu.background
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(6)
    }
  }

  delegate: Item {
    id: cell
    required property int index
    required property string label
    required property string appIcon
    required property string kind
    required property string appId
    required property string section

    width: grid.cellWidth
    height: grid.cellHeight

    // Centred in its cell, so the pinned strip's outline sits evenly
    // around its tiles. The strip's empty cells draw nothing.
    AppTile {
      visible: cell.kind !== "pinpad"
      menu: grid.menu
      tileIndex: cell.index
      tileLabel: cell.label
      tileIcon: cell.appIcon
      tileKind: cell.kind
      tileAppId: cell.appId
      inPinnedStrip: cell.section === grid.menu.pinnedSection
      width: grid.cellWidth - Style.space(6)
      height: grid.cellHeight - Style.space(6)
      anchors.centerIn: parent
    }
  }
}
