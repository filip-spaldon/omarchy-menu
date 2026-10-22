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

  delegate: AppTile {
    required property int index
    required property string label
    required property string appIcon
    required property string kind
    required property string appId

    menu: grid.menu
    tileIndex: index
    tileLabel: label
    tileIcon: appIcon
    tileKind: kind
    tileAppId: appId
    width: grid.cellWidth - Style.space(6)
    height: grid.cellHeight - Style.space(6)
  }
}
