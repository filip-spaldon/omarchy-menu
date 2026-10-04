// The card's key help: the "?" sheet with every key, and Alt+1…9, which
// opens the row shown with that number. Pure data in, data out, so it runs
// under node.

// Every key, for the "?" sheet: groups of [keys, what they do].
var CHEATSHEET = [
  { title: "Anywhere", keys: [["↑ ↓", "move"], ["↵", "open"], ["alt 1…9", "open that row"], ["⇥ / shift ⇥", "next / previous tab"], ["^1…9", "tab by position"], ["esc", "clear, then close"], ["ai …", "ask the AI"], ["/", "commands"], ["alt L / alt shift L", "next / previous look"]] },
  { title: "Where the card sits", keys: [["alt ← → ↑ ↓", "move it"], ["alt shift ← → ↑ ↓", "nudge it"], ["alt 0", "back to the default"]] },
  { title: "Files and folders", keys: [["alt ↵", "open the folder"], ["^C", "copy the path"], ["^T", "terminal there"], ["^F / ^S / ^L", "type / sort / limit"], ["^R", "where (search roots)"]] },
  { title: "Apps and System", keys: [["shift ↵", "new window"], ["^G", "list or grid"], ["del", "uninstall"], ["→ / ←", "into / out of a menu"], ["^↑ ^↓", "next System match"]] }
]

// Alt+1…9 picks the row shown with that number: the n-th row from the top of
// what is visible. Returns the row index, or -1.
function rowForNumber(firstVisible, count, n) {
  if (n < 1 || n > 9) return -1
  var index = firstVisible + n - 1
  return index >= 0 && index < count ? index : -1
}

if (typeof module !== "undefined") {
  module.exports = {
    CHEATSHEET: CHEATSHEET,
    rowForNumber: rowForNumber
  }
}
