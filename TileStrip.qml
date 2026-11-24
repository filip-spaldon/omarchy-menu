import QtQuick
import qs.Commons

// One strip of All's app tiles (AllTiles.js), drawn by the strip's first
// row: up to `columns` tiles across the row, each in the drawn look's design.
// The Apps tab's pinned strip (a block) is one strip of several lines, inset
// by `pad` inside its outline.
Item {
  id: strip
  required property var menu
  // AllTiles.layout's entry for the lead row: { lead, first, tiles: [...] }.
  required property var info
  property real pad: 0
  property bool inPinnedStrip: false

  // The pinned block's tint and outline, as tall as all its lines.
  PinnedFrame {
    menu: strip.menu
    visible: strip.inPinnedStrip && !!strip.info && !!strip.info.tiles
    anchors.fill: parent
  }

  Repeater {
    model: strip.info && strip.info.tiles ? strip.info.tiles : []

    delegate: Item {
      id: cell
      required property var modelData
      readonly property real cellWidth: (strip.width - 2 * strip.pad) / Math.max(1, strip.menu.allTileColumns)

      x: strip.pad + cell.modelData.col * cell.cellWidth
      y: strip.pad + (cell.modelData.line || 0) * strip.menu.allTileHeight
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
        tileRow: strip.info.lines !== undefined ? (cell.modelData.line || 0)
          : Math.floor((strip.info.lead - strip.info.first) / Math.max(1, strip.menu.allTileColumns))
        inPinnedStrip: strip.inPinnedStrip
        width: parent.width - Style.space(6)
        height: parent.height - Style.space(6)
        anchors.centerIn: parent
      }
    }
  }
}
