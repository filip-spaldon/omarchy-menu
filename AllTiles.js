// All's Apps section as tiles (state.json "allAppsView": "grid"). Pure data
// in, data out, like Tabs.js, so it runs under node.
//
// The tiles stay ordinary rows of the result model, one per app: the cursor,
// Enter, Shift+Enter, Delete and the late-results keep-selection-by-id all
// work on them as on any row. Only the delegate of a strip's first row (its
// lead) draws the strip; the others take no room. layout() says which rows
// are tiles and where they sit, the step functions move the cursor through
// them.

// Tile rows the Apps section may fill: it shows up to ROWS * columns apps.
var ROWS = 2

// rows: the composed result list; section: the Apps header (Tabs.headerSection).
// Returns [] when nothing is a tile, else one entry per row: null for a list
// row, or { lead, col, count, first, last } for a tile -- the strip's first
// row, the tile's column, the strip's tile count, and the first and last row
// of the whole tile block. A lead also carries `tiles`, [{ index, col, row }],
// what its delegate draws. Only the first run of app rows under the header
// becomes tiles; the section is contiguous anyway.
function layout(rows, section, columns) {
  var list = rows || []
  var cols = Math.max(1, Math.floor(Number(columns)) || 1)
  var first = -1
  var last = -1
  for (var i = 0; i < list.length; i++) {
    var tile = !!list[i] && list[i].kind === "app" && list[i].section === section
    if (tile && first < 0) first = i
    if (first >= 0) {
      if (!tile) break
      last = i
    }
  }
  if (first < 0) return []

  var out = []
  for (var k = 0; k < list.length; k++) out.push(null)
  for (var j = first; j <= last; j++) {
    var col = (j - first) % cols
    var lead = j - col
    var info = { lead: lead, col: col, count: Math.min(cols, last - lead + 1), first: first, last: last }
    if (col === 0) info.tiles = []
    out[j] = info
    out[lead].tiles.push({ index: j, col: col, row: list[j] })
  }
  return out
}

// The height a tile row's delegate takes: the whole strip on its lead, none
// on the rest. The list still puts `spacing` after each of those empty rows,
// so the lead gives that much back and the strip ends where it should.
function stripHeight(info, index, tileHeight, spacing) {
  if (!info || info.lead !== index) return 0
  return Math.max(0, tileHeight - (info.count - 1) * spacing)
}

// The row the cursor lands on when a move arrives at `index` from outside
// the strip: its first tile, whichever of its rows the move counted to (from
// below that is the last one; Page Up/Down can hit any).
function enter(tiles, index) {
  var info = tiles && tiles[index]
  return info ? info.lead : index
}

// Up and Down (delta -1 / 1), wrapping like the list. From a tile: the same
// column of the next or previous strip (or its last tile, when shorter), and
// past the block the row after or before it. Into a strip: its first tile.
function step(tiles, index, delta, total) {
  if (total <= 0) return 0
  var here = tiles && tiles[index]
  if (here) {
    var near = delta > 0 ? here.lead + here.count : here.lead - 1
    if (near >= here.first && near <= here.last) {
      var strip = tiles[tiles[near].lead]
      return strip.lead + Math.min(here.col, strip.count - 1)
    }
    index = delta > 0 ? here.last : here.first
  }
  var next = ((index + delta) % total + total) % total
  return enter(tiles, next)
}

// Left and Right (delta -1 / 1) within the tile block, stopping at either
// end; -1 when `index` is not a tile, so the key keeps its usual meaning.
function side(tiles, index, delta) {
  var here = tiles && tiles[index]
  if (!here) return -1
  return Math.max(here.first, Math.min(here.last, index + delta))
}

if (typeof module !== "undefined") {
  module.exports = {
    ROWS: ROWS,
    layout: layout,
    stripHeight: stripHeight,
    enter: enter,
    step: step,
    side: side
  }
}
