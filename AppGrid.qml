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

  cellWidth: Math.max(1, Math.min(grid.menu.tileWidth, parent ? parent.width : 100000))
  cellHeight: grid.menu.tileHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Behind the pinned apps (the model's first rows; see Menu.pinnedCount):
  // the accent tint and outline the list's pinned strip has. The menu pads
  // the strip to whole rows of this grid (Menu.gridColumns).
  PinnedFrame {
    parent: grid.contentItem
    z: -1
    menu: grid.menu
    visible: grid.menu.pinnedCount > 0
    width: grid.columns * grid.cellWidth
    height: Math.ceil(grid.menu.pinnedCount / grid.columns) * grid.cellHeight
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
    // around its tiles. The strip's empty cells draw nothing. The tile is
    // the drawn look's own (LookTile.qml).
    LookTile {
      visible: cell.kind !== "pinpad"
      menu: grid.menu
      tileIndex: cell.index
      tileLabel: cell.label
      tileIcon: cell.appIcon
      tileKind: cell.kind
      tileAppId: cell.appId
      tileCol: cell.index % grid.columns
      tileRow: Math.floor(cell.index / grid.columns)
      inPinnedStrip: cell.section === grid.menu.pinnedSection
      width: grid.cellWidth - Style.space(6)
      height: grid.cellHeight - Style.space(6)
      anchors.centerIn: parent
    }
  }
}
