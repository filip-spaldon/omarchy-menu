// Konstrukt's data mapping: every result is also a flat shape, and every
// property of the shape is data. Pure data in, data out, so it runs under
// node; only KonstruktView.qml (one view, not a row) imports it.

// the shape for a row's kind.
function shapeFor(kind) {
  if (kind === "app") return "circle"
  if (kind === "file") return "square"
  if (kind === "folder") return "triangle"
  if (kind === "window") return "bar"
  return "cross"
}

// how old a file row is, in days, from its date text ("Today
// 12:38", "Yesterday 20:09", "08/09 18:49", "08/09/2024"). Rows carry only
// the text, and this keeps the model as it is. Unknown: 0.
function ageDays(trail, now) {
  var t = String(trail || "").trim()
  if (!t || /^today/i.test(t)) return 0
  if (/^yesterday/i.test(t)) return 1
  var m = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?/.exec(t)
  if (!m) return 0
  var today = new Date(now)
  var year = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : today.getFullYear()
  var when = new Date(year, Number(m[2]) - 1, Number(m[1]))
  if (!m[3] && when > today) when.setFullYear(year - 1)
  return Math.max(0, Math.floor((today - when) / 86400000))
}

// tilt from age on a log scale, 0 degrees now to 45 at a year.
function tiltFor(days) {
  return Math.min(45, 45 * Math.log(1 + Math.max(0, days)) / Math.log(366))
}

// where the n-th ranked shape sits on a sunflower spiral, as an
// offset from the centre in units of `step`.
function spiral(n, step) {
  var r = step * Math.sqrt(n)
  var a = n * 2.39996
  return { x: r * Math.cos(a), y: r * Math.sin(a) }
}

// whether two flat maps hold the same keys and values (the rows' middles,
// measured again on every scroll step and row laid out).
function sameMap(a, b) {
  var n = 0
  for (var key in a) {
    if (a[key] !== b[key]) return false
    n++
  }
  return n === Object.keys(b || {}).length
}

if (typeof module !== "undefined") {
  module.exports = {
    shapeFor: shapeFor,
    ageDays: ageDays,
    tiltFor: tiltFor,
    spiral: spiral,
    sameMap: sameMap
  }
}
