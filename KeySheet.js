// The key help: the "?" sheet with every key, the footers' keys for the
// current tab, the tab numbers shown while Ctrl is held, and Alt+1…9, which
// opens the row shown with that number. Pure data in, data out, so it runs
// under node.

// Every key, for the "?" sheet: groups of [keys, what they do].
var CHEATSHEET = [
  { title: "Anywhere", keys: [["↑ ↓", "move"], ["↵", "open"], ["alt 1…9", "open that row"], ["⇥ / shift ⇥", "next / previous tab"], ["^1…9", "tab by position (hold ^ to see)"], ["esc", "clear, then close"], ["ai …", "ask the AI"], ["/", "commands"], ["alt L / alt shift L", "next / previous look"], ["^?", "this sheet"]] },
  { title: "Where the card sits", keys: [["alt ← → ↑ ↓", "move it"], ["alt shift ← → ↑ ↓", "nudge it"], ["alt 0", "back to the default"]] },
  { title: "Files and folders", keys: [["alt ↵", "open the folder"], ["^C", "copy the path"], ["^T", "terminal there"], ["^F / ^S / ^L", "type / sort / limit"], ["^R", "where (search roots)"]] },
  { title: "Apps and System", keys: [["shift ↵", "new window"], ["^P", "pin or unpin"], ["^shift ← →", "move a pin"], ["^G", "list or grid"], ["del", "uninstall"], ["→ / ←", "into / out of a menu"], ["^↑ ^↓", "next System match"]] },
  { title: "Clipboard", keys: [["↵ / ^C / ^O", "paste / copy / open"], ["^F", "type"]] }
]

// The sheet as one list of lines, for a look that sets it as a single
// column: { title } starts a group, { key, does } is one of its keys.
function sheetLines(sheet) {
  var out = []
  var groups = sheet || CHEATSHEET
  groups.forEach(function(group) {
    out.push({ title: group.title })
    group.keys.forEach(function(k) { out.push({ key: k[0], does: k[1] }) })
  })
  return out
}

// What the current tab can do, as [key, what it does, core] in the order
// the footers show them. Every footer is cut from this one list: the card's
// keycaps and the short text footer take the core keys, the full-screen
// views (more room) take them all. The keys are the ones Menu.qml's key
// handler answers. s: { tab, cheatOpen, altHeld, twoPane, matches (System
// search matches to step through), pinned, canReorder, appsView, allAppsView,
// hasRoots }.
function tabKeys(s) {
  if (s.cheatOpen) return [["any key", "close", true]]
  if (s.altHeld)
    return [["alt 1–9", "open that row", true], ["alt ←→↑↓", "move the card", true], ["alt 0", "reset", true],
            ["alt L", "next look", false]]
  var all = ["^?", "all keys", true]
  var tab = ["⇥", "next tab", false]
  if (s.tab === "apps")
    return [["↵", "open", true], ["shift ↵", "new window", true], ["^P", s.pinned ? "unpin" : "pin", true],
            ["^G", s.appsView === "grid" ? "list" : "grid", true]]
      .concat(s.canReorder ? [["^shift ←→", "move the pin", false]] : [], [["del", "uninstall", false], tab, all])
  if (s.tab === "clipboard")
    return [["↵", "paste", true], ["^C", "copy", true], ["^O", "open", true], ["^F", "type", true], tab, all]
  if (s.tab === "windows") return [["↵", "go to", true], ["⇥", "next tab", true], all]
  if (s.tab === "files" || s.tab === "folders")
    return [["↵", "open", true], ["alt ↵", "folder", false], ["^C", "path", false], ["^T", "terminal", false],
            ["^F", "type", true]].concat(s.hasRoots ? [["^R", "where", true]] : [],
                                         [["^S", "sort", true], ["^L", "limit", true], tab, all])
  if (s.tab === "system" && s.twoPane)
    return [["↑↓", "browse", true], ["→", "open", true], ["←", "back", true]]
      .concat(s.matches ? [["^↑↓", "next match", true]] : [], [tab, all])
  if (s.tab === "system") return [["↵", "open", true], ["←", "back", false], ["⇥", "next tab", true], all]
  return [["↑↓", "move", true], ["↵", "open", true], ["⇥", "next tab", true],
          ["^G", "apps " + (s.allAppsView === "grid" ? "list" : "grid"), false], ["ai", "ask", true], all]
}

// The keycaps: the core keys, as [key, what it does].
function coreKeys(keys) {
  return keys.filter(function(k) { return k[2] }).map(function(k) { return [k[0], k[1]] })
}

// A text footer: "↵ open   ^C copy   …   esc close". full takes every key
// rather than the core ones; jump adds Alt+1…9 after Enter, for a
// look whose rows are always numbered.
function footerText(keys, full, jump) {
  var shown = keys.filter(function(k) { return full || k[2] })
  var parts = shown.map(function(k) { return k[0] + " " + k[1] })
  var enter = shown.findIndex(function(k) { return k[0] === "↵" })
  if (jump && enter >= 0) parts.splice(enter + 1, 0, "alt 1–9 jump")
  if (shown.length !== 1 || shown[0][0] !== "any key") parts.push("esc close")
  return parts.join("   ")
}

// Ctrl+1…9 picks the tab at that place in the bar: the number a tab shows
// while Ctrl is held, or "" past the ninth.
function tabNumber(index) {
  return index >= 0 && index < 9 ? String(index + 1) : ""
}

// Holding Ctrl alone shows the tab numbers: a Ctrl press with no other
// modifier down. Qt key and modifier codes, so this runs under node too.
var KEY_CONTROL = 0x01000021
var CONTROL_MODIFIER = 0x04000000
var KEYPAD_MODIFIER = 0x20000000
function ctrlAlone(key, modifiers) {
  return key === KEY_CONTROL && (modifiers & ~(CONTROL_MODIFIER | KEYPAD_MODIFIER)) === 0
}

// Alt+1…9 picks the row shown with that number: the n-th row from the top of
// what is visible. Returns the row index, or -1.
function rowForNumber(firstVisible, count, n) {
  if (n < 1 || n > 9) return -1
  var index = firstVisible + n - 1
  return index >= 0 && index < count ? index : -1
}

// A modifier pressed on its own (Shift, Ctrl, Alt, AltGr, Super, Meta,
// Hyper, Caps Lock) is the start of a chord, not a key: it leaves the "?"
// sheet open. Qt key codes, so this runs under node too.
var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01001103,
                     0x01000053, 0x01000054, 0x01000056, 0x01000057]
function closesSheet(key) {
  return MODIFIER_KEYS.indexOf(key) < 0
}

if (typeof module !== "undefined") {
  module.exports = {
    CHEATSHEET: CHEATSHEET,
    rowForNumber: rowForNumber,
    closesSheet: closesSheet,
    sheetLines: sheetLines,
    tabKeys: tabKeys,
    coreKeys: coreKeys,
    footerText: footerText,
    tabNumber: tabNumber,
    ctrlAlone: ctrlAlone
  }
}
