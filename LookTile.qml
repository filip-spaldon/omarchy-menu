import QtQuick

// One app tile in the drawn look's own design: the Apps grid (AppGrid.qml,
// and the full-screen looks' grids) and All's app strips (TileStrip.qml) all
// make this. The look's tile reads what it shows from here (`tile`), so each
// design is a file of its own and the card's tile (AppTile.qml) carries none
// of them. tileCol / tileRow place it on the grid, for the looks that draw
// the grid itself (Wayfinder's map references).
Item {
  id: host
  required property var menu
  property int tileIndex: -1
  property string tileLabel: ""
  property string tileIcon: ""
  property string tileKind: ""
  property string tileAppId: ""
  property int tileCol: 0
  property int tileRow: 0
  readonly property bool hasCursor: host.menu.cursorActive && host.tileIndex === host.menu.selectedIndex

  // The pointer, the same for every design: hover moves the cursor, a click
  // opens.
  function hover(item, mouse) { host.menu.selectFromPointer(host.tileIndex, item, mouse) }
  function open() {
    host.menu.cursorActive = true
    host.menu.selectedIndex = host.tileIndex
    host.menu.activateIndex(host.tileIndex, true)
  }

  Loader {
    anchors.fill: parent
    sourceComponent: ({ mala: malaTile, wayfinder: wayfinderTile, axis: axisTile, konstrukt: konstruktTile })[host.menu.drawnLook] || classicTile
  }

  Component {
    id: classicTile
    AppTile {
      menu: host.menu
      tileIndex: host.tileIndex
      tileLabel: host.tileLabel
      tileIcon: host.tileIcon
      tileKind: host.tileKind
      tileAppId: host.tileAppId
    }
  }
  Component { id: malaTile; MalaTile { tile: host } }
  Component { id: wayfinderTile; WayfinderTile { tile: host } }
  Component { id: axisTile; AxisTile { tile: host } }
  Component { id: konstruktTile; KonstruktTile { tile: host } }
}
