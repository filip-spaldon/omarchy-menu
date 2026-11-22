// Pinned apps (state.json "pinnedApps"): desktop ids in pin order, shown as
// a highlighted strip at the top of the Apps tab. Pure data in, data out,
// like Tabs.js, so it runs under node.
//
// The saved list keeps ids whose application is gone or hidden: uninstalling
// and reinstalling an app, or a desktop entry that only shows up later, finds
// it pinned again. Only what is installed now is shown (shown()).

var MAX = 50
// A desktop id as DesktopEntries reports it ("firefox", "org.gnome.Nautilus",
// "chrome-abc-Default"). Anything else is not one, and is dropped.
var ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._+@-]{0,254}$/

function validId(id) {
  return typeof id === "string" && ID_PATTERN.test(id)
}

// The saved value as a clean list: desktop ids only, the first of any
// duplicates, at most MAX. Anything but an array is [].
function normalize(value) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < MAX; i++)
    if (validId(value[i]) && out.indexOf(value[i]) < 0) out.push(value[i])
  return out
}

// Whether `value` is already what normalize() would make of it: a saved list
// that is not gets written back clean.
function isNormal(value) {
  return Array.isArray(value) && JSON.stringify(normalize(value)) === JSON.stringify(value)
}

function isPinned(list, id) {
  return normalize(list).indexOf(id) >= 0
}

// Pinned ids unpin; others are appended (pin order is display order). A list
// already holding MAX ids, or an id that is not one, is left as it was.
function toggle(list, id) {
  var out = normalize(list)
  if (!validId(id)) return out
  var at = out.indexOf(id)
  if (at >= 0) out.splice(at, 1)
  else if (out.length < MAX) out.push(id)
  return out
}

// `id` moved `delta` places (-1 earlier, 1 later) among the pinned ids that
// are on show (`shownIds`): it swaps with its shown neighbour, so a gap of
// uninstalled ids between them does not swallow the key press. Unchanged at
// either end, or when `id` is not shown.
function move(list, id, delta, shownIds) {
  var out = normalize(list)
  var shown = (shownIds || out).filter(function(s) { return out.indexOf(s) >= 0 })
  var at = shown.indexOf(id)
  var to = at + (delta < 0 ? -1 : 1)
  if (at < 0 || to < 0 || to >= shown.length) return out
  var a = out.indexOf(id)
  var b = out.indexOf(shown[to])
  out[a] = shown[to]
  out[b] = id
  return out
}

// The pinned ids that `available(id)` says are installed and listed, in pin
// order. The strip is shown only when this is not empty.
function shown(list, available) {
  var ids = normalize(list)
  var out = []
  for (var i = 0; i < ids.length; i++) if (available(ids[i])) out.push(ids[i])
  return out
}

// The grid's pinned rows end on a full row of tiles: this many empty cells
// follow `count` pinned tiles, so the apps start on a row of their own.
function gridPadding(count, columns) {
  var cols = Math.max(1, Math.floor(Number(columns)) || 1)
  var n = Math.max(0, Math.floor(Number(count)) || 0)
  return n === 0 ? 0 : (cols - n % cols) % cols
}

// One of those empty cells as a result row: every role a row carries
// (MenuModel.displayRow), disabled so the cursor and Enter pass it by.
function padRow(n, section) {
  return {
    itemId: "pinned.pad." + n, disabled: true, kind: "pinpad", icon: "", iconFont: "",
    appIcon: "", appId: "", label: "", target: "", detail: "", path: "", imagePath: "",
    childCount: 0, action: "", provider: "", score: 0, section: section || "", trailText: ""
  }
}

// From `index` in the grid, `delta` cells on (±1 sideways, ±columns a row),
// not wrapping, past the empty cells: `selectable(i)` is false on those. A
// move that lands on one keeps going the way it went, one cell at a time;
// with nowhere to go it stays put.
function gridStep(index, delta, total, selectable) {
  if (total <= 0) return 0
  var target = Math.max(0, Math.min(total - 1, index + delta))
  var dir = delta < 0 ? -1 : 1
  while (target >= 0 && target < total && !selectable(target)) target += dir
  return target >= 0 && target < total ? target : index
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX: MAX,
    ID_PATTERN: ID_PATTERN,
    validId: validId,
    normalize: normalize,
    isNormal: isNormal,
    isPinned: isPinned,
    toggle: toggle,
    move: move,
    shown: shown,
    gridPadding: gridPadding,
    padRow: padRow,
    gridStep: gridStep
  }
}
