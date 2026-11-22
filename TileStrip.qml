import QtQuick
import qs.Commons

// One strip of All's app tiles (AllTiles.js), drawn by the strip's first
// row: up to `columns` tiles across the row, each in the drawn look's design.
Item {
  id: strip
  required property var menu
  // AllTiles.layout's entry for the lead row: { lead, first, tiles: [...] }.
  required property var info

  Repeater {
    model: strip.info && strip.info.tiles ? strip.info.tiles : []

    delegate: Item {
      id: cell
      required property var modelData
      readonly property real cellWidth: strip.width / Math.max(1, strip.menu.allTileColumns)

      x: cell.modelData.col * cell.cellWidth
      width: cell.cellWidth
      height: strip.menu.allTileHeight

      LookTile {
        menu: strip.menu
        tileIndex: cell.modelData.index
        tileLabel: cell.modelData.row.label
        tileIcon: cell.modelData.row.appIcon
        tileKind: cell.modelData.row.kind
        tileAppId: cell.modelData.row.appId
        tileCol: cell.modelData.col
        tileRow: Math.floor((strip.info.lead - strip.info.first) / Math.max(1, strip.menu.allTileColumns))
        width: parent.width - Style.space(6)
        height: parent.height - Style.space(6)
        anchors.centerIn: parent
      }
    }
  }
}
