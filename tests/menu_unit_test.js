#!/usr/bin/env node
// Plain-Node tests for the launcher's pure logic: Tabs.js (tabs, routes,
// sections), FileSearch.js (fd argv, parsing, ranking) and the untrusted-text
// gate in MenuModel.js. The QML is exercised live; this covers what can be
// checked without a shell.
//
// Run with: node tests/menu_unit_test.js

const path = require("path")
const root = path.join(__dirname, "..")
const Tabs = require(path.join(root, "Tabs.js"))
const AllTiles = require(path.join(root, "AllTiles.js"))
const Pinned = require(path.join(root, "Pinned.js"))
const FileSearch = require(path.join(root, "FileSearch.js"))
const MenuModel = require(path.join(root, "MenuModel.js"))
const Settings = require(path.join(root, "Settings.js"))
const Roots = require(path.join(root, "Roots.js"))
const Windows = require(path.join(root, "Windows.js"))
const Clipboard = require(path.join(root, "Clipboard.js"))
const SystemShortcuts = require(path.join(root, "SystemShortcuts.js"))

let pass = 0
let fail = 0

function eq(actual, expected, msg) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (ok) pass++
  else {
    fail++
    console.log("FAIL " + msg + "\n  expected " + JSON.stringify(expected) + "\n  actual   " + JSON.stringify(actual))
  }
}

function assert(cond, msg) {
  eq(!!cond, true, msg)
}

// ------------------------------------------------------------------- tabs --

eq(Tabs.TABS.map(t => t.id), ["all", "apps", "windows", "clipboard", "system", "files", "folders"], "default tab order")
eq(Tabs.DEFAULT_ALL_SECTIONS, ["apps", "windows", "system", "files", "folders"], "default All section order matches the tabs")
eq(Tabs.orderTabs(["files", "all"]).map(t => t.id), ["files", "all", "apps", "windows", "clipboard", "system", "folders"],
   "a partial tab order reorders and appends the rest")
eq(Tabs.orderTabs(["bogus", "apps", "apps", 7]).map(t => t.id), ["apps", "all", "windows", "clipboard", "system", "files", "folders"],
   "unknown and repeated ids are dropped")
eq(Tabs.orderTabs("not an array").map(t => t.id), Tabs.DEFAULT_TAB_ORDER, "a malformed order falls back to the default")
eq(Tabs.orderSections(["folders", "apps"]).map(s => s.id), ["folders", "apps", "windows", "system", "files"], "All sections reorder")
eq(Tabs.cycleTab("all", 1, Tabs.orderTabs(["all", "folders"])), "folders", "Tab follows the order on screen")
eq(Tabs.tabForRoute("root"), { tab: "all", menu: "root" }, "SUPER+SPACE opens All")
eq(Tabs.tabForRoute(""), { tab: "all", menu: "root" }, "an empty route opens All")
eq(Tabs.tabForRoute("apps"), { tab: "apps", menu: "root" }, "SUPER+ALT+SPACE opens Apps")
eq(Tabs.tabForRoute("windows"), { tab: "windows", menu: "root" }, "the windows route opens Windows")
eq(Tabs.tabForRoute("system"), { tab: "system", menu: "system" }, "the system route opens System power actions")
assert(!Tabs.shortcutSwitchesDestination("root", "apps", "root"), "root shortcut always toggles the whole panel")
assert(Tabs.shortcutSwitchesDestination("clipboard", "apps", "root"), "shortcut switches tabs")
assert(!Tabs.shortcutSwitchesDestination("clipboard", "clipboard", "root"), "same tab shortcut toggles")
assert(Tabs.shortcutSwitchesDestination("trigger.capture", "system", "trigger.share"), "shortcut switches System submenus")
assert(!Tabs.shortcutSwitchesDestination("trigger.capture", "system", "trigger.capture"), "same submenu shortcut toggles")
assert(Tabs.shortcutSwitchesDestination("system", "system", "trigger.capture"), "power shortcut switches from another submenu")
eq(Tabs.rootShortcutTab("all", "all", ""), "system", "root cycles from All to System")
eq(Tabs.rootShortcutTab("apps", "apps", ""), "system", "root cycles from the configured opening tab to System")
eq(Tabs.rootShortcutTab("system", "apps", "apps"), "apps", "root returns to the configured opening tab")
eq(Tabs.rootShortcutTab("clipboard", "apps", ""), "all", "root goes to All from another tab")
eq(Tabs.rootShortcutTab("all", "apps", ""), "system", "root goes to System after the All fallback")
eq(Tabs.rootShortcutTab("system", "apps", "all"), "all", "root returns to All when that was the starting tab")
eq(Tabs.rootShortcutTab("system", "system", ""), "all", "a System default pairs with All")
eq(Tabs.tabForRoute("capture"), { tab: "system", menu: "capture" }, "other routes open System, drilled in")
eq(Tabs.tabForRoute("style.theme"), { tab: "system", menu: "style.theme" }, "dotted routes open System, drilled in")
eq(Tabs.cycleTab("all", 1), "apps", "Tab moves forward")
eq(Tabs.cycleTab("all", -1), "folders", "Shift+Tab wraps backwards")
eq(Tabs.cycleTab("folders", 1), "all", "Tab wraps forwards")
eq(Tabs.cycleTab("nonsense", 1), "apps", "an unknown tab cycles from the first")
assert(Tabs.isTab("files") && !Tabs.isTab("root"), "isTab")
eq(Tabs.normalizeDisabled(["files", "bogus", "files", "folders"]), ["files", "folders"], "disabledTabs keeps valid ids once")
eq(Tabs.normalizeDisabled(Tabs.DEFAULT_TAB_ORDER), [], "disabling every tab is ignored")
eq(Tabs.normalizeDisabled("files"), [], "a malformed disabledTabs is ignored")
eq(Tabs.visibleTabs(null, ["windows", "clipboard", "files", "folders"], "all").map(t => t.id), ["all", "apps", "system"], "disabled tabs leave the bar")
eq(Tabs.visibleTabs(null, ["system"], "system").map(t => t.id), Tabs.DEFAULT_TAB_ORDER,
   "a disabled tab opened by route stays visible while active")
eq(Tabs.firstEnabledTab(null, ["all"]), "apps", "with All off, the first tab that is on opens")
eq(Tabs.firstEnabledTab(["system", "all"], ["all"]), "system", "first enabled follows the user's order")
eq(Tabs.openTabFor("first", ["apps", "system", "files", "folders", "all"], []), "apps",
   "openTab first opens the first tab of the order, not All")
eq(Tabs.openTabFor(undefined, null, []), "all", "a missing openTab opens the first default tab")
eq(Tabs.openTabFor("first", ["apps", "system", "all"], ["apps"]), "system", "openTab first skips disabled tabs")
eq(Tabs.openTabFor("files", null, []), "files", "openTab names a tab")
eq(Tabs.openTabFor("files", ["system", "all"], ["files"]), "system", "a disabled openTab falls back to the first tab on")
eq(Tabs.openTabFor("bogus", ["folders"], []), "folders", "an unknown openTab falls back to the first tab on")
eq(Settings.OPEN_TABS, ["first"].concat(Tabs.DEFAULT_TAB_ORDER), "OPEN_TABS is first plus every tab")

const sections = Tabs.composeSections([
  { title: "Apps", rows: [{ itemId: "a1" }, { itemId: "a2" }, { itemId: "a3" }] },
  { title: "Files", rows: [] },
  { title: "System", rows: [{ itemId: "s1", section: "drilldown" }] }
], 2)
eq(sections.map(r => r.itemId), ["a1", "a2", "s1"], "sections are capped and empty ones vanish")
eq(sections.map(r => Tabs.headerTitle(r.section)), ["Apps", "Apps", "System"], "every row carries its header")
assert(sections.every(r => Tabs.isHeaderSection(r.section)), "headers never collide with the drilldown divider")
const original = { itemId: "x", section: "" }
Tabs.composeSections([{ title: "T", rows: [original] }], 5)
eq(original.section, "", "composeSections does not stamp the caller's row objects")
eq(Tabs.indexOfItem(sections, "s1"), 2, "indexOfItem finds a row by id")
eq(Tabs.indexOfItem(sections, "gone"), -1, "indexOfItem misses cleanly")
eq(Tabs.indexOfItem(sections, ""), -1, "indexOfItem ignores an empty id")
eq(Tabs.composeSections([
  { title: "Apps", rows: [{ itemId: "a1" }, { itemId: "a2" }, { itemId: "a3" }], limit: 3 },
  { title: "System", rows: [{ itemId: "s1" }, { itemId: "s2" }], limit: 0 }
], 1).map(r => r.itemId), ["a1", "a2", "a3", "s1"], "a section's own limit overrides perSection")
eq(Tabs.sectionHeader("apps"), Tabs.headerSection("Apps"), "sectionHeader names a section by id")
eq(Tabs.sectionHeader("bogus"), "", "sectionHeader of an unknown id is empty")

// ------------------------------------------------------------ All's tiles --

{
  const H = Tabs.sectionHeader("apps")
  const app = id => ({ itemId: id, kind: "app", section: H, label: id })
  // answer, 5 apps (3 columns: strips of 3 and 2), then two System rows.
  const rows = [{ itemId: "calc", kind: "calc", section: "" }, app("a"), app("b"), app("c"), app("d"), app("e"),
    { itemId: "s1", kind: "action", section: Tabs.sectionHeader("system") },
    { itemId: "s2", kind: "action", section: Tabs.sectionHeader("system") }]
  const t = AllTiles.layout(rows, H, 3)
  eq(t.length, rows.length, "the tile layout has an entry per row")
  eq([t[0], t[6], t[7]], [null, null, null], "rows outside the Apps section are not tiles")
  eq(t.slice(1, 6).map(x => [x.lead, x.col, x.count]), [[1, 0, 3], [1, 1, 3], [1, 2, 3], [4, 0, 2], [4, 1, 2]],
     "apps fill strips of `columns` tiles, the last one shorter")
  eq(t[1].tiles.map(x => x.index), [1, 2, 3], "a strip's lead carries its tiles")
  eq(t[2].tiles, undefined, "only the lead carries tiles")
  eq([t[3].first, t[3].last], [1, 5], "every tile knows the block's ends")
  eq(AllTiles.layout(rows, H, 0)[2].col, 0, "a zero column count still lays out one per strip")
  eq(AllTiles.layout([{ kind: "app", section: "" }, { kind: "file", section: H }], H, 3), [],
     "no app under the Apps header: no tiles")
  eq(AllTiles.layout(null, H, 3), [], "no rows: no tiles")

  eq(AllTiles.stripHeight(t[1], 1, 100, 4), 92, "a lead gives back the spacing after its empty rows")
  eq(AllTiles.stripHeight(t[4], 4, 100, 4), 96, "a shorter strip gives back less")
  eq(AllTiles.stripHeight(t[2], 2, 100, 4), 0, "the rest of a strip takes no room")
  eq(AllTiles.stripHeight(null, 0, 100, 4), 0, "a list row has no strip height")

  const step = (i, d) => AllTiles.step(t, i, d, rows.length)
  eq(step(0, 1), 1, "Down into the tiles takes the first tile")
  eq(step(1, 1), 4, "Down from a tile keeps its column in the next strip")
  eq(step(3, 1), 5, "Down into a shorter strip takes its last tile")
  eq(step(5, 1), 6, "Down from the last strip leaves the block")
  eq(step(6, -1), 4, "Up into the tiles takes the last strip's first tile")
  eq(step(5, -1), 2, "Up from a tile keeps its column in the strip above")
  eq(step(2, -1), 0, "Up from the first strip leaves the block")
  eq(step(0, -1), 7, "Up from the top still wraps to the bottom")
  eq(step(7, 1), 0, "Down from the bottom still wraps to the top")
  eq(AllTiles.step([], 2, 1, 3), 0, "without tiles a step is the list's wrap")
  eq(AllTiles.step(t, 0, 1, 0), 0, "an empty list steps nowhere")
  const onlyTiles = AllTiles.layout([app("a"), app("b")], H, 3)
  eq(AllTiles.step(onlyTiles, 1, 1, 2), 0, "Down from the only strip wraps to its first tile")
  eq(AllTiles.step(onlyTiles, 1, -1, 2), 0, "Up from the only strip wraps to its first tile")

  eq(AllTiles.enter(t, 5), 4, "landing inside a strip takes its first tile")
  eq(AllTiles.enter(t, 6), 6, "landing on a row stays there")

  eq(AllTiles.side(t, 2, 1), 3, "Right moves to the next tile")
  eq(AllTiles.side(t, 3, 1), 4, "Right crosses into the next strip")
  eq(AllTiles.side(t, 5, 1), 5, "Right stops at the last tile")
  eq(AllTiles.side(t, 1, -1), 1, "Left stops at the first tile")
  eq(AllTiles.side(t, 6, 1), -1, "Left and Right leave list rows alone")
  eq(AllTiles.ROWS * 3 >= 5, true, "the Apps section may fill more than one strip")
  eq(Settings.ALL_APPS_VIEWS, ["list", "grid"], "allAppsView is list or grid, list first (the default)")
}

// ------------------------------------------------------------ pinned apps --

{
  // state.json value: desktop ids only, deduped, capped, order kept.
  eq(Pinned.normalize(["firefox", "org.gnome.Nautilus", "firefox", "chrome-abc-Default"]),
     ["firefox", "org.gnome.Nautilus", "chrome-abc-Default"], "pins are deduped, first one kept, in pin order")
  eq(Pinned.normalize(["ok", 3, null, "", "../etc", "a b", "-x", "x;rm", "<b>", "y"]), ["ok", "y"],
     "anything but a desktop id is dropped")
  eq(Pinned.normalize("firefox"), [], "a non-array is no pins")
  eq(Pinned.normalize(undefined), [], "a missing key is no pins")
  eq(Pinned.normalize(["a".repeat(256)]), [], "an overlong id is dropped")
  const many = Array.from({ length: 80 }, (_, i) => "app" + i)
  eq(Pinned.normalize(many).length, Pinned.MAX, "at most MAX pins are kept")
  eq(Pinned.MAX, 50, "MAX is 50")
  assert(Pinned.isNormal(["a", "b"]), "a clean list is normal")
  assert(!Pinned.isNormal(["a", "a"]), "a list with duplicates is rewritten")
  assert(!Pinned.isNormal("a"), "a non-array is rewritten")
  assert(Pinned.isNormal([]), "no pins is normal")

  // Pin and unpin.
  eq(Pinned.toggle([], "firefox"), ["firefox"], "pinning appends")
  eq(Pinned.toggle(["a", "b"], "c"), ["a", "b", "c"], "a new pin goes last: pin order")
  eq(Pinned.toggle(["a", "b", "c"], "b"), ["a", "c"], "toggling a pinned id unpins it")
  eq(Pinned.toggle(["a"], "bad id"), ["a"], "an invalid id is not pinned")
  eq(Pinned.toggle(many.slice(0, 50), "new"), many.slice(0, 50), "a full list takes no more pins")
  eq(Pinned.toggle(many.slice(0, 50), "app3").length, 49, "a full list still unpins")
  const before = ["a", "b"]
  Pinned.toggle(before, "c")
  eq(before, ["a", "b"], "toggle does not change its input")
  assert(Pinned.isPinned(["a", "b"], "b") && !Pinned.isPinned(["a"], "b"), "isPinned")

  // Reorder among the shown pins.
  eq(Pinned.move(["a", "b", "c"], "b", -1), ["b", "a", "c"], "earlier swaps with the one before")
  eq(Pinned.move(["a", "b", "c"], "b", 1), ["a", "c", "b"], "later swaps with the one after")
  eq(Pinned.move(["a", "b", "c"], "a", -1), ["a", "b", "c"], "the first stays first")
  eq(Pinned.move(["a", "b", "c"], "c", 1), ["a", "b", "c"], "the last stays last")
  eq(Pinned.move(["a", "gone", "c"], "c", -1, ["a", "c"]), ["c", "gone", "a"],
     "a hidden pin between two shown ones does not swallow the move")
  eq(Pinned.move(["a", "b"], "x", 1), ["a", "b"], "an id not pinned does not move")
  eq(Pinned.move(["a", "gone"], "gone", -1, ["a"]), ["a", "gone"], "an id not shown does not move")

  // What the strip shows.
  const installed = id => ["a", "c", "d"].indexOf(id) >= 0
  eq(Pinned.shown(["c", "gone", "a"], installed), ["c", "a"], "only installed pins show, in pin order")
  eq(Pinned.shown(["gone"], installed), [], "no installed pin: no strip")
  eq(Pinned.shown([], installed), [], "no pins: no strip")
  eq(Pinned.normalize(["c", "gone", "a"]), ["c", "gone", "a"], "uninstalled pins stay saved")

  // Grid padding and moves over it.
  eq([Pinned.gridPadding(0, 4), Pinned.gridPadding(1, 4), Pinned.gridPadding(4, 4), Pinned.gridPadding(5, 4)],
     [0, 3, 0, 3], "the grid's pinned rows are padded to whole rows")
  eq(Pinned.gridPadding(3, 0), 0, "one column needs no padding")
  // 2 pinned, 2 pads, then apps at 4.. (4 columns, 10 cells).
  const selectable = i => i !== 2 && i !== 3
  eq(Pinned.gridStep(1, 1, 10, selectable), 4, "Right past the last pin skips the empty cells")
  eq(Pinned.gridStep(4, -1, 10, selectable), 1, "Left from the first app lands on the last pin")
  eq(Pinned.gridStep(7, -4, 10, selectable), 1, "Up under an empty cell lands on the last pin")
  eq(Pinned.gridStep(6, -4, 10, selectable), 1, "Up under the other empty cell too")
  eq(Pinned.gridStep(0, 4, 10, selectable), 4, "Down from a pin keeps its column")
  eq(Pinned.gridStep(9, 1, 10, selectable), 9, "the grid does not wrap at the end")
  eq(Pinned.gridStep(0, -1, 10, selectable), 0, "nor at the start")
  eq(Pinned.gridStep(0, 1, 0, selectable), 0, "an empty grid steps nowhere")
  eq(Pinned.gridStep(1, 1, 4, selectable), 1, "nothing past the pads: stays put")
  eq(Pinned.gridStep(3, 1, 8, () => true), 4, "without pads a step is the plain grid's")

  // A pad row has exactly a row's roles (syncRows keeps one role set).
  const entry = { id: "apps.firefox", kind: "app", icon: "", appId: "firefox", label: "Firefox" }
  const appRow = MenuModel.displayRow({ "apps.firefox": entry }, ["apps.firefox"], {}, {}, entry, "", 0, "pinned")
  eq(Object.keys(Pinned.padRow(0, "pinned")).sort(), Object.keys(appRow).sort(), "a pad row carries every row role")
  const pad = Pinned.padRow(2, "pinned")
  eq([pad.disabled, pad.kind, pad.section, pad.itemId], [true, "pinpad", "pinned", "pinned.pad.2"],
     "a pad is disabled, in the pinned section, with its own id")

  // The list's pinned block: one strip on several lines of tiles.
  const app = id => ({ itemId: id, kind: "app", section: "pinned" })
  const rest = id => ({ itemId: id, kind: "app", section: "" })
  // 5 pins (3 columns: lines of 3 and 2), then the alphabetical list.
  const rows = [app("p1"), app("p2"), app("p3"), app("p4"), app("p5"), rest("a"), rest("b")]
  const t = AllTiles.layout(rows, "pinned", 3, true)
  eq(t.slice(0, 5).map(x => [x.lead, x.col, x.line, x.count]),
     [[0, 0, 0, 5], [0, 1, 0, 5], [0, 2, 0, 5], [0, 0, 1, 5], [0, 1, 1, 5]], "a block has one lead for all its lines")
  eq([t[0].lines, t[0].columns], [2, 3], "a block knows its lines and columns")
  eq(t[0].tiles.map(x => [x.index, x.col, x.line]), [[0, 0, 0], [1, 1, 0], [2, 2, 0], [3, 0, 1], [4, 1, 1]],
     "the lead draws every tile of the block")
  eq([t[5], t[6]], [null, null], "the list under the strip stays rows")
  eq(AllTiles.layout([rest("a")], "pinned", 3, true), [], "no pinned rows: no strip")
  eq(AllTiles.stripHeight(t[0], 0, 100, 4, 6), 2 * 100 + 12 - 4 * 4, "a block is its lines tall plus padding, less the spacing given back")
  eq(AllTiles.stripHeight(t[2], 2, 100, 4, 6), 0, "the block's other rows take no room")
  eq(AllTiles.drawnHeight(t[3], 100, 6), 212, "the block is drawn its full height")
  eq(AllTiles.drawnHeight(AllTiles.layout(rows, "pinned", 3)[0], 100), 100, "a plain strip is drawn one tile tall")
  const step = (i, d) => AllTiles.step(t, i, d, rows.length)
  eq(step(1, 1), 4, "Down in a block keeps the column on the next line")
  eq(step(2, 1), 4, "Down onto a shorter line takes its last tile")
  eq(step(4, -1), 1, "Up in a block keeps the column on the line above")
  eq(step(4, 1), 5, "Down from the last line leaves the block")
  eq(step(0, -1), 6, "Up from the first line wraps like the list")
  eq(step(5, -1), 0, "Up into the block takes its first tile")
  eq(AllTiles.side(t, 2, 1), 3, "Right wraps onto the block's next line")
  eq(AllTiles.side(t, 4, 1), 4, "Right stops at the last pin")
  const one = AllTiles.layout([app("p1"), app("p2"), rest("a")], "pinned", 3, true)
  eq([one[0].lines, AllTiles.step(one, 1, 1, 3), AllTiles.step(one, 2, -1, 3)], [1, 2, 0],
     "a one-line block steps like a strip")
}

// ------------------------------------------------------------ file search --

const home = "/home/u"
const argv = FileSearch.buildArgv("a.b (c", FileSearch.FILE_FILTERS[1], false, home)
eq(argv[0], "fd", "argv starts with fd")
assert(argv.indexOf("--and") !== -1, "multiple terms are ANDed")
eq(argv[argv.indexOf("--") + 1], "[aáàãâä]\\.b", "the first term is escaped and accent-folded")
eq(argv[argv.indexOf("--and") + 1], "\\([cç]", "later terms ride on --and, escaped too")
eq(argv.filter(x => x === "-e").length, FileSearch.FILE_FILTERS[1].exts.length, "a type filter passes each extension")
assert(argv.indexOf("--hidden") === -1, "type filters skip hidden paths")
eq(argv[argv.length - 1], home, "user searches are rooted at $HOME")
assert(argv.indexOf("dosdevices") !== -1, "Wine drive links are excluded")
assert(argv.indexOf(".local/share/Steam") !== -1, "the Steam library is excluded")
assert(argv.indexOf("--max-results") !== -1, "fd output is bounded")

const all = FileSearch.buildArgv("", FileSearch.ALL_FILTER, true, home)
assert(all.indexOf("--hidden") !== -1, "All searches hidden paths (config folders)")
eq(all[all.indexOf("--") + 1], ".", "an empty query matches everything")

const sys = FileSearch.buildArgv("", FileSearch.FOLDER_FILTERS[1], true, home)
eq(sys.slice(-2), [home + "/.config", home + "/.local/share"], "System folders roots")
assert(sys.indexOf("--max-depth") !== -1, "System folders are depth-limited")
assert(sys.indexOf("chromium") === -1, "browser folders are not excluded whole")
assert(sys.indexOf("**/chromium/*") !== -1, "only a browser folder's contents are excluded")

const parsed = FileSearch.parseLines(home + "/Docs/\0" + home + "/.config/hypr/\0relative\0\0", true, home)
eq(parsed.map(i => i.name), ["Docs", "hypr"], "parseLines keeps absolute paths and strips the trailing slash")
eq(parsed.map(i => i.dir), ["~", "~/.config"], "parent dirs are shown relative to home")
eq(parsed.map(i => i.isSystem), [false, true], "dotted paths are system paths")

const items = [
  { name: "notes.md", path: home + "/notes.md", isDir: false, mtimeMs: 20 },
  { name: "Notes", path: home + "/Notes", isDir: true, mtimeMs: 10 },
  { name: "old-notes.txt", path: home + "/a/old-notes.txt", isDir: false, mtimeMs: 30 },
  { name: "notes", path: home + "/.config/notes", isDir: true, mtimeMs: 40 }
]
eq(FileSearch.rankResults(items, "notes", 9, home, "relevance").map(i => i.path),
   [home + "/Notes", home + "/.config/notes", home + "/notes.md", home + "/a/old-notes.txt"],
   "relevance: exact before prefix before inner match; folders first on ties")
eq(FileSearch.rankResults(items, "", 9, home, "mtime_desc").map(i => i.name),
   ["old-notes.txt", "notes.md", "Notes", "notes"], "most recent, user files before system ones")
eq(FileSearch.rankResults(items, "", 2, home, "relevance").length, 2, "results are limited")
eq(FileSearch.rankResults(items, "zzz", 9, home, "relevance"), [], "non-matching queries rank nothing")
eq(FileSearch.scoreItem({ name: "Príloha.pdf", path: home + "/Príloha.pdf" }, "priloha"), 1, "matching ignores accents")

eq(FileSearch.parseStatLines("1700000000\t/x\0garbage\0000\t/y\0005\trelative\0"), { "/x": 1700000000000 }, "parseStatLines keeps valid lines only")
assert(argv.indexOf("--print0") !== -1, "fd prints NUL-separated paths")
const tricky = FileSearch.parseLines(home + "/dl/evil\n/etc/passwd\0" + home + "/ok.txt\0", false, home)
eq(tricky.map(i => i.path), [home + "/dl/evil\n/etc/passwd", home + "/ok.txt"], "a newline in a file name never splits it into another path")
eq(FileSearch.parseStatLines("1700000000\t/a\nb\0"), { "/a\nb": 1700000000000 }, "stat output keeps names with newlines whole")
for (const n of ["app.desktop", "tool.AppImage", "x.pkg.tar.zst", "setup.sh", "a.EXE", "i.deb"])
  assert(FileSearch.isLaunchableName(n), n + " opens its folder, not itself")
for (const n of ["doc.pdf", "notes.txt", ".bashrc", "README", "photo.jpg", "app.js"])
  assert(!FileSearch.isLaunchableName(n), n + " opens normally")
eq(FileSearch.formatMtime(new Date(2026, 8, 23, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "Today 09:05", "today")
eq(FileSearch.formatMtime(new Date(2026, 8, 22, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "Yesterday 09:05", "yesterday")
eq(FileSearch.formatMtime(new Date(2025, 0, 2, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "02/01/25 09:05", "older years")
eq(FileSearch.nextSortMode("name_desc"), "relevance", "sort modes wrap")
eq(FileSearch.nextDisplayLimit(200), 15, "display limits wrap")

// ------------------------------------------------------ file rows memo --
{
  const fs = require("fs")
  const files = fs.readFileSync(path.join(root, "FileSearchController.qml"), "utf8")
  const body = (src, name) => { const i = src.indexOf("function " + name + "("); return i < 0 ? "" : src.slice(i, src.indexOf("\n  function ", i + 1)) }
  const rows = body(files, "fileRows")
  eq(/searcher\.rowsMemo\.key !== key/.test(rows), true, "ranked file rows are memoized")
  eq(/zoxideMode/.test(rows), true, "the file rows memo is keyed on zoxide's mode")
  eq(/onFileResultsChanged: searcher\.fileResultsVersion \+= 1/.test(files), true, "new results bump the file results version")
  eq(/onFrecencyChanged: searcher\.fileResultsVersion \+= 1/.test(files), true, "new zoxide scores bump the file results version")
  eq(/fileResultsVersion \+= 1/.test(body(files, "applyFileMtimes")), true, "new mtimes bump the file results version")
}

// ----------------------------------------------------- path-aware search --
{
  const items = {
    root: { id: "root", parent: "", label: "Go", kind: "menu" },
    update: { id: "update", parent: "root", label: "Update", kind: "menu" },
    "update.omarchy": { id: "update.omarchy", parent: "update", label: "Omarchy", kind: "action" },
    learn: { id: "learn", parent: "root", label: "Learn", kind: "menu" },
    "learn.omarchy": { id: "learn.omarchy", parent: "learn", label: "Omarchy", kind: "action" }
  }
  eq(MenuModel.pathMatchTerms(items, items["update.omarchy"], "update omarchy", true), "omarchy",
     "a term found in the parent lets the child match on its own terms")
  eq(MenuModel.pathMatchTerms(items, items["update.omarchy"], "omarchy update", true), "omarchy", "term order does not matter")
  eq(MenuModel.pathMatchTerms(items, items["learn.omarchy"], "update omarchy", true), null, "a term found nowhere on the path rejects the entry")
  eq(MenuModel.pathMatchTerms(items, items["update.omarchy"], "update", true), null, "the parent alone does not make every child match")
  eq(MenuModel.pathMatchTerms(items, items["update.omarchy"], "update omarchy", false), null, "hidden entries never match")
}

// ---------------------------------------------------- in-place list sync --
{
  // A stand-in for QML's ListModel: set() merges like the real one, so a
  // role the new row lacks would keep its old value unless syncRows fills it.
  function stubModel() {
    const m = {
      items: [], log: [],
      get count() { return this.items.length },
      get(i) { return this.items[i] },
      set(i, row) { this.log.push("set " + i); Object.assign(this.items[i], row) },
      setProperty(i, role, value) { this.log.push("setProperty " + i); this.items[i][role] = value },
      insert(i, row) { this.log.push("insert " + i); this.items.splice(i, 0, Object.assign({}, row)) },
      remove(i, n) { this.log.push("remove " + i + " " + (n || 1)); this.items.splice(i, n || 1) },
      append(row) { this.log.push("append"); this.items.push(Object.assign({}, row)) },
      clear() { this.log.push("clear"); this.items = [] }
    }
    return m
  }
  const r = (id, extra) => Object.assign({ itemId: id, label: id.toUpperCase(), disabled: false, score: 1 }, extra || {})
  const ids = m => m.items.map(x => x.itemId)

  const model = stubModel()
  const roles = {}
  MenuModel.syncRows(model, [r("a"), r("b")], roles)
  eq(ids(model), ["a", "b"], "sync fills an empty model")
  eq(model.log, ["append", "append"], "an empty model is filled by appending")

  model.log = []
  MenuModel.syncRows(model, [r("a"), r("b"), r("c"), r("d")], roles)
  eq(ids(model), ["a", "b", "c", "d"], "sync grows the list")
  eq(model.log, ["append", "append"], "unchanged rows are left alone when the list grows")

  model.log = []
  MenuModel.syncRows(model, [r("a"), r("b")], roles)
  eq(ids(model), ["a", "b"], "sync shrinks the list")
  eq(model.log, ["remove 2 2"], "surplus rows are removed in one call")

  model.log = []
  MenuModel.syncRows(model, [r("b"), r("a")], roles)
  eq(ids(model), ["b", "a"], "sync reorders the list")
  eq(model.items.map(x => x.label), ["B", "A"], "reordered rows carry their own roles")
  eq(model.log, ["set 0", "set 1"], "reordered rows are set in place, never cleared")

  model.log = []
  MenuModel.syncRows(model, [r("b", { trailText: "3 min", detail: "x" }), r("a")], roles)
  eq(model.items[0].trailText, "3 min", "a new role reaches the model")
  eq(model.items[1].trailText, "", "a row without a new role gets it empty")

  MenuModel.syncRows(model, [r("b", { disabled: true }), r("a")], roles)
  eq(model.items[0].trailText, "", "a string role missing from the new row does not keep its old value")
  eq(model.items[0].detail, "", "every missing string role is reset")
  MenuModel.syncRows(model, [{ itemId: "b", label: "B" }, r("a")], roles)
  eq(model.items[0].disabled, false, "a missing bool role resets to false")
  eq(model.items[0].score, 0, "a missing number role resets to 0")

  model.log = []
  MenuModel.syncRows(model, [{ itemId: "b", label: "B" }, r("a")], roles)
  eq(model.log, [], "a row equal to its filled-out form is not set again")

  MenuModel.syncRows(model, [], roles)
  eq(model.count, 0, "an empty result empties the list")
}

// --------------------------------------------------------- untrusted text --

const rlo = String.fromCharCode(0x202e)
const row = MenuModel.sanitizeRow({ label: "evil" + rlo + "txt.exe", detail: "a\nb", trailText: "x" })
assert(row.label.indexOf(rlo) === -1, "bidi overrides are stripped from labels")
assert(row.detail.indexOf("\n") === -1, "line breaks are stripped from details")
eq(MenuModel.displayRow({}, [], {}, { id: "x", kind: "action", label: "X" }, "", 0, "").trailText, "",
   "menu rows declare the trailText role")

// Re-reading every source on every open cost six guarded processes; the
// reads now wait for a change (FileWatch).
{
  const fs = require("fs")
  const read = file => fs.readFileSync(path.join(root, file), "utf8")
  const menuSource = read("Menu.qml")
  const loadSources = menuSource.slice(menuSource.indexOf("function loadMenuSources("), menuSource.indexOf("\n  }\n", menuSource.indexOf("function loadMenuSources(")))
  eq(/defaultMenuWatch\.stale/.test(loadSources) && /userMenuWatch\.stale/.test(loadSources), true, "menu sources are re-read only when changed")
  const store = read("SettingsStore.qml")
  eq(/!styleWatch\.stale/.test(store) && /!stateWatch\.stale/.test(store), true, "style.json and state.json are re-read only when changed")
  const ai = read("AiController.qml")
  eq(/!aiConfigWatch\.stale && !aiAgentWatch\.stale/.test(ai), true, "the AI config is re-read only when changed")
  const watch = read("FileWatch.qml")
  eq(/preload: false/.test(watch) && /watchChanges: true/.test(watch), true, "FileWatch watches without loading the file")
}

// ------------------------------------------------------ settings popup --

eq(Settings.parseObject(""), {}, "a missing settings file reads as empty")
eq(Settings.parseObject("[1]"), null, "a settings file that is not an object is refused")
eq(Settings.parseObject("{oops"), null, "a settings file that does not parse is refused")
eq(Settings.withKey({ _help: 1, a: 1 }, "a", 2), { _help: 1, a: 2 }, "withKey keeps the other keys")
eq(Settings.withKey({ a: 1, b: 2 }, "a", undefined), { b: 2 }, "withKey removes a key set to undefined")
eq(Object.keys(Settings.withKey({ a: 1, b: 2, c: 3 }, "a", 9)), ["a", "b", "c"], "withKey keeps the key order")
eq(Settings.cycle(["x", "y", "z"], "z", 1), "x", "cycle wraps forward")
eq(Settings.cycle(["x", "y", "z"], "x", -1), "z", "cycle wraps backward")
eq(Settings.cycle(["x", "y"], "?", -1), "y", "cycle from an unknown value")
eq(Settings.stepNumber(0.8, Settings.STYLE_RANGES.fontScale, 1), 0.85, "font scale steps without drift")
eq(Settings.stepNumber(2, Settings.STYLE_RANGES.fontScale, 1), 2, "font scale stops at its maximum")
eq(Settings.stepNumber(650, Settings.STYLE_RANGES.cardWidth, -1), 640, "card width steps by 10")
eq(Settings.styleTop({ top: 0.12 }), 0.12, "top as a share of the screen")
eq(Settings.styleTop({ top: "center" }), -1, "top \"center\" centres")
eq(Settings.styleTop({}), -1, "a missing top centres, as the menu reads it")

// Launcher position
const P = (ax, ay, ox, oy) => ({ anchorX: ax, anchorY: ay, offsetX: ox, offsetY: oy })
eq(Settings.stylePosition({ top: 0.2 }), P("center", "top", 0, 0.2), "a legacy top becomes a top anchor")
eq(Settings.stylePosition({ top: "center" }), P("center", "middle", 0, 0), "a legacy centred top becomes the middle")
eq(Settings.stylePosition({ top: 0.3, position: P("right", "bottom", 0.05, 0.1) }), P("right", "bottom", 0.05, 0.1), "position wins over top")
eq(Settings.stylePosition({ position: P("right", "bottom", 5, -1) }), P("right", "bottom", 0.9, 0), "offsets are clamped to the anchor's range")
eq(Settings.stylePosition({ top: 0.2, position: P("up", "bottom", 0, 0) }), P("center", "top", 0, 0.2), "an unknown anchor falls back to top")
eq(Settings.stylePosition({ position: { anchorX: "left", anchorY: "top" } }), P("left", "top", 0, 0), "missing offsets are 0")
eq(Settings.snapPosition(Settings.DEFAULT_POSITION, -1, 0), P("left", "top", 0.03, 0.2), "snap left keeps the vertical offset")
eq(Settings.snapPosition(P("left", "top", 0.03, 0.2), -1, 0), P("left", "top", 0.03, 0.2), "snap past the edge stays put")
eq(Settings.snapPosition(Settings.DEFAULT_POSITION, 0, 1), P("center", "middle", 0, 0), "snap down from the top lands in the middle")
eq(Settings.snapPosition(P("center", "middle", 0, 0), 1, 1), P("right", "bottom", 0.03, 0.12), "snap diagonally from the centre")
eq(Settings.nudgePosition(P("left", "top", 0.03, 0.2), 1, 1), P("left", "top", 0.05, 0.22), "nudge right and down from the top left")
eq(Settings.nudgePosition(P("right", "bottom", 0.03, 0.12), 1, 1), P("right", "bottom", 0.01, 0.1), "nudge right and down toward the bottom right edges")
eq(Settings.nudgePosition(P("right", "bottom", 0.01, 0), 1, 1), P("right", "bottom", 0, 0), "nudge stops at the edge")
eq(Settings.nudgePosition(P("center", "middle", 0, 0), -1, -1), P("center", "middle", -0.02, -0.02), "nudge from the centre is signed")
const left = (pos) => Settings.cardLeft(pos, 1000, 400, 10)
eq(left(Settings.DEFAULT_POSITION), 300, "the default sits centred")
eq(left(P("right", "bottom", 0, 0)), 590, "pinned right, the card keeps the margin")
eq(left(P("left", "middle", 0, 0)), 10, "pinned left, the card keeps the margin")
eq(left(P("center", "middle", 0.45, 0)), 590, "a card pushed past the side is kept on screen")
eq(Settings.cardVertical(Settings.DEFAULT_POSITION, 800, 10), { top: 160, bottom: -1, shift: 0 }, "the default asks for a top edge 20% down")
eq(Settings.cardVertical(P("right", "bottom", 0.03, 0.1), 800, 10), { top: -1, bottom: 710, shift: 0 }, "pinned to the bottom, the card asks for a bottom edge")
eq(Settings.cardVertical(P("center", "middle", 0, -0.1), 800, 10), { top: -1, bottom: -1, shift: -80 }, "in the middle, the card is centred and shifted")
eq(Settings.positionPatch(P("right", "bottom", 0.03, 0.12)),
   [{ path: ["position"], value: P("right", "bottom", 0.03, 0.12) }, { path: ["top"], remove: true }],
   "saving a moved card patches the position key and drops the older top")
{
  const fs = require("fs"), os = require("os"), { spawnSync } = require("child_process")
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omni-position-"))
  const file = path.join(dir, "style.json")
  const before = { fontScale: 0.9, top: 0.3, tabSlide: false, custom: { keep: [1, 2] }, position: P("left", "top", 0, 0) }
  fs.writeFileSync(file, JSON.stringify(before, null, 2))
  const command = Settings.writeCommand(dir, file, Settings.positionPatch(P("right", "bottom", 0.03, 0.12)), 8192)
  const run = spawnSync(command[0], command.slice(1), { encoding: "utf8" })
  eq(run.status, 0, "the position patch is written")
  // The helper writes keys sorted; compare without their order.
  const sorted = (o) => Object.keys(o).sort().reduce((out, k) => (out[k] = o[k], out), {})
  eq(sorted(JSON.parse(fs.readFileSync(file, "utf8"))), sorted(Object.assign({}, before, { position: P("right", "bottom", 0.03, 0.12), top: undefined })),
     "a position save removes the stale top and leaves every other style.json key as it was")
  fs.rmSync(dir, { recursive: true, force: true })
}
eq(Settings.positionLabel(P("right", "bottom", 0, 0)), "↘ bottom right", "a corner is named with its arrow")
eq(Settings.positionLabel(Settings.DEFAULT_POSITION), "↑ top", "the default reads as top")
eq(Settings.positionLabel(P("center", "middle", 0, 0)), "● centre", "the middle of the screen is the centre")
eq(Settings.positionPresets().length, 9, "nine presets")
eq(Settings.moveAnim({}), Settings.MOVE_DEFAULTS, "move slide defaults")
eq(Settings.moveAnim({ moveMs: 200, moveEasing: "OutBack" }), { moveMs: 200, moveEasing: "OutBack" }, "move slide from style.json")
eq(Settings.moveAnim({ moveMs: -1, moveEasing: "Wobbly" }), Settings.MOVE_DEFAULTS, "bad move values fall back")
eq(Settings.cyclePosition(Settings.DEFAULT_POSITION, 1), P("right", "top", 0.03, 0.12), "the popup steps from top centre to top right")
eq(Settings.cyclePosition(P("left", "top", 0.05, 0.3), -1), P("right", "bottom", 0.03, 0.12), "the popup wraps from the first preset to the last")
eq(Settings.cyclePosition(P("left", "top", 0, 0), 1), Settings.DEFAULT_POSITION, "top centre is the default")
eq(Settings.stepTop(-1, 1), 0, "stepping up from centred starts at 0")
eq(Settings.stepTop(0, -1), -1, "stepping below 0 centres")
eq(Settings.stepTop(0.12, 1), 0.14, "top steps by 0.02")
eq(Settings.styleNumber({ bodyHeight: 5 }, "bodyHeight"), Settings.STYLE_DEFAULTS.bodyHeight, "an out-of-range value falls back")
eq(Settings.tabAnim({}), Settings.TAB_ANIM_DEFAULTS, "tab animation falls back to its defaults")
eq(Settings.tabAnim({ tabSlideMs: 200, tabEasing: "OutBack", tabPop: 0 }).tabEasing, "OutBack", "a known easing is kept")
eq(Settings.tabAnim({ tabEasing: "Wobbly", tabSlideMs: -5 }), Settings.TAB_ANIM_DEFAULTS, "unknown easing and out-of-range ms fall back")
assert(!("tabSlideMs" in Settings.STYLE_DEFAULTS), "tab animation keys are opt-in")
eq(Settings.tabAnim({ tabBezier: [0.2, 1.5, 0.35, 1] }).tabBezier, [0.2, 1.5, 0.35, 1], "a bezier curve is kept")
eq(Settings.tabAnim({ tabBezier: [1.5, 1, 0.35, 1] }).tabBezier, null, "a bezier x outside 0..1 is refused")
eq(Settings.tabAnim({ tabBezier: [0.2, "1.5", 0.35, 1] }).tabBezier, null, "a bezier with a non-number is refused")
eq(Settings.tabAnim({ tabBezier: [0.2, 1.5] }).tabBezier, null, "a short bezier is refused")
eq(Settings.tabAnim({ tabSweep: false }).tabSweep, false, "the sweep can be turned off")
eq(Settings.tabAnim({ tabSweep: "no" }).tabSweep, true, "a non-boolean sweep falls back")
eq(Settings.STYLE_DEFAULTS.tabSlide, true, "the tab switch is a style default, on")
eq(Settings.tabAnim({ tabSlide: false, tabSlideMs: 300, tabPop: 0.5 }).tabSlideMs, 0, "switching tab animations off makes the slide jump")
eq(Settings.tabAnim({ tabSlide: false, tabSlideMs: 300, tabPop: 0.5 }).tabPop, 0, "switching tab animations off drops the pop")
eq(Settings.tabAnim({ tabSlide: "off", tabSlideMs: 300 }).tabSlideMs, 300, "a non-boolean switch falls back to on")
eq(Settings.moveInOrder(["a", "b", "c"], "b", -1), ["b", "a", "c"], "moveInOrder moves left")
eq(Settings.moveInOrder(["a", "b", "c"], "c", 1), ["a", "b", "c"], "moveInOrder stops at the end")
eq(Settings.toggleDisabled([], "files", ["all", "files"]), ["files"], "a tab switches off")
eq(Settings.toggleDisabled(["files"], "files", ["all", "files"]), [], "a tab switches back on")
eq(Settings.toggleDisabled(["files"], "all", ["all", "files"]), ["files"], "the last tab that is on stays on")
eq(Settings.toggleListed(["files"], "folders"), ["files", "folders"], "a section leaves All")
eq(Settings.toggleListed(["files", "folders"], "files"), ["folders"], "a section returns to All")
eq(Tabs.normalizeSectionsOff(["files", "bogus", "files", "apps", "system", "folders"]), ["files", "apps", "system", "folders"],
   "every section may leave All; unknown and repeated ids are dropped")
eq(Tabs.normalizeSectionsOff("files"), [], "allSectionsOff must be a list")
assert(Settings.MODEL_PATTERN.test("openai-codex/gpt-6-luna"), "model names with a provider are accepted")
assert(!Settings.MODEL_PATTERN.test("x; rm -rf ~"), "model names with shell syntax are refused")
const write = Settings.writeCommand("/d", "/d/f.json", Settings.patch("label", "$(boom)"), 1000)
eq(write.slice(-4), ["/d", "/d/f.json", "1000", JSON.stringify(Settings.patch("label", "$(boom)"))], "written values reach the helper as arguments")
assert(write[6].indexOf("boom") === -1, "written content never enters the script text")
eq(Settings.readFileCommand("/p", 10, 3).slice(-3), ["--", "/p", "10"], "read path reaches perl as an argument")

// ------------------------------------------------------- open-time cost --
// Opening the menu must not run the guard batch (every `when:`/`checked:`
// expression, ~200 processes): only an open that shows System rows does,
// through ensureGuards, so the default open does not start ~200 processes.
{
  const fs = require("fs")
  const menuSource = fs.readFileSync(path.join(root, "Menu.qml"), "utf8")
  const functionBody = name => {
    const start = menuSource.indexOf("function " + name + "(")
    if (start < 0) return ""
    const next = menuSource.indexOf("\n  function ", start + 1)
    return menuSource.slice(start, next < 0 ? undefined : next)
  }
  eq(/evaluateGuards\(\)/.test(functionBody("openExistingMenu")), false, "opening the menu does not evaluate guards")
  eq(/evaluateGuards\(\)/.test(functionBody("rebuildItemsFromSources")), false, "reloading menu sources does not evaluate guards")
  eq(/showsSystemRows\(\)\) root\.ensureGuards\(\)/.test(functionBody("rebuildDisplay")), true, "showing System rows evaluates guards")
  eq(/root\.activeTab === "apps"/.test(functionBody("showsSystemRows")), false, "Apps never counts as System rows")
  eq(/panel\.maxRowsHeight = -1/.test(functionBody("openDmenu")), true, "a dmenu prompt does not keep the launcher's frozen rows height")
  eq(/panel\.cardTop = -1/.test(functionBody("openDmenu")), true, "a dmenu prompt does not keep the launcher's frozen top line")
}

// ------------------------------------------------------------ kill rows --

{
  const list = "  42 1234 1 12.5 2048 Web Content\n7 99 1 0.0 10 bash\nbad line\n"
  eq(MenuModel.parseProcessList(list, "web", 8),
     [{ pid: 42, start: "1234", name: "Web Content", cpu: 12.5, rss: 2048, count: 1 }], "a listed process keeps its start time and a name with spaces")
  eq(MenuModel.parseProcessList(list, "", 8).length, 2, "malformed lines are skipped")

  // pid start ppid pcpu rss comm: a browser with helpers, two separate
  // terminals, and a helper whose parent is gone from the listing.
  const tree = [
    "300 30 100 5.0 1000 chromium",
    "100 10 1 2.0 4000 chromium",
    "101 11 100 1.5 500 chromium",
    "400 40 300 0.5 100 chromium",
    "150 15 100 0.1 50 chrome_crashpad",
    "200 20 1 0.2 30 foot",
    "201 21 1 0.1 30 foot",
    "500 50 999 0.3 70 chromium"
  ].join("\n")
  const grouped = MenuModel.parseProcessList(tree, "chromium", 8)
  eq(grouped.map((g) => [g.pid, g.count]), [[100, 4], [500, 1]], "an app's same-named helpers fold into its top process")
  eq([grouped[0].cpu, grouped[0].rss, grouped[0].start], [9, 5600, "10"], "a group sums its CPU and memory and is killed by its top process")
  eq(MenuModel.parseProcessList(tree, "foot", 8).length, 2, "separate instances with other parents stay separate")
  eq(MenuModel.parseProcessList(tree, "chrom", 8).map((g) => [g.pid, g.name]), [[100, "chromium"], [500, "chromium"], [150, "chrome_crashpad"]],
     "a differently named child is its own row; groups go by total CPU")
  eq(MenuModel.parseProcessList(tree, "chromium", 8, true).map((p) => p.pid), [300, 100, 101, 400, 500],
     "expanded lists every matching process in ps order")
  assert(MenuModel.parseProcessList("1 1 2 0 0 x\n2 2 1 0 0 x", "x", 8).length <= 2, "a parent cycle in a torn listing still ends")
  eq(MenuModel.killTarget(42, "1234"), "42:1234", "a kill row carries pid and start time")

  const { spawn, spawnSync, execFileSync } = require("child_process")
  const fs = require("fs")
  const startOf = (pid) => fs.readFileSync("/proc/" + pid + "/stat", "utf8").replace(/^.*\)\s/s, "").split(" ")[19]
  const alive = (pid) => { try { process.kill(pid, 0); return true } catch (e) { return false } }
  const kill = (target) => spawnSync("perl", ["-e", MenuModel.KILL_PROGRAM, "--", target]).status

  const listed = execFileSync("bash", ["-c", MenuModel.PROCESS_LIST_SCRIPT], { encoding: "utf8" })
  const self = MenuModel.parseProcessList(listed, "", 100000).find((p) => p.pid === process.pid)
  assert(self && self.start === startOf(process.pid), "the listing reports each process's /proc start time")

  // A process that names itself to look like extra fields: perl's $0 sets
  // the kernel comm. It must list as itself, with its own pid and start.
  const odd = spawn("perl", ["-e", '$0 = "x) 9 9 (y"; sleep 30'], { stdio: "ignore" })
  spawnSync("sleep", ["0.3"])
  const oddListed = MenuModel.parseProcessList(execFileSync("bash", ["-c", MenuModel.PROCESS_LIST_SCRIPT], { encoding: "utf8" }), "x) 9", 8, true)
  eq(oddListed.map((p) => [p.pid, p.start, p.name]), [[odd.pid, startOf(odd.pid), "x) 9 9 (y"]], "a name made to look like fields lists as itself")
  odd.kill("SIGKILL")

  const child = spawn("sleep", ["30"], { stdio: "ignore" })
  const start = startOf(child.pid)
  eq(kill(child.pid + ":" + (Number(start) + 1)), 4, "a start time that does not match sends nothing")
  assert(alive(child.pid), "the process whose pid only matched is left alone")
  eq(kill("not-a-target"), 2, "a malformed target is refused")
  eq(kill(child.pid + ":" + start), 0, "the listed process is signalled")
  spawnSync("sleep", ["0.2"])
  assert(!alive(child.pid) || fs.readFileSync("/proc/" + child.pid + "/stat", "utf8").includes(") Z "), "the listed process is gone")
  child.kill("SIGKILL")

  const gone = spawnSync("sh", ["-c", "echo $$"], { encoding: "utf8" }).stdout.trim()
  eq(kill(gone + ":1"), 3, "a pid with no process sends nothing")
}

// ------------------------------------------------------ keystroke cost --
// A keystroke rebuilds the list several times; each must reuse what did not
// change.
{
  const fs = require("fs")
  const menuSource = fs.readFileSync(path.join(root, "Menu.qml"), "utf8")
  const body = (src, name) => { const i = src.indexOf("function " + name + "("); return i < 0 ? "" : src.slice(i, src.indexOf("\n  function ", i + 1)) }
  eq(/memo\.systemKey !== key/.test(body(menuSource, "systemSearchRows")), true, "System search results are memoized")
  eq(/memo\.visibleRevision !== root\.menuRevision/.test(body(menuSource, "isVisible")), true, "visibility is memoized per menu revision")
  eq(["onItemsChanged", "onItemOrderChanged", "onWhenResultsChanged", "onCheckedResultsChanged"].every(h => new RegExp(h + ": root\\.menuRevision\\+\\+").test(menuSource)), true,
     "every input of the search bumps menuRevision")
}

// --------------------------------------------------- opening a file ------
{
  const fs = require("fs"), os = require("os"), { spawnSync } = require("child_process")
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omni-open-"))
  const bin = path.join(dir, "bin"); fs.mkdirSync(bin)
  fs.writeFileSync(path.join(bin, "gio"), '#!/bin/sh\nprintf "%s\\n" "$2"\n', { mode: 0o755 })
  const plain = path.join(dir, "notes.txt"); fs.writeFileSync(plain, "x")
  const exe = path.join(dir, "tool"); fs.writeFileSync(exe, "#!/bin/sh\n", { mode: 0o755 })
  const open = (p) => spawnSync("bash", ["-c", FileSearch.OPEN_FILE_SCRIPT, "bash", p, dir],
    { encoding: "utf8", env: Object.assign({}, process.env, { PATH: bin + ":" + process.env.PATH }) }).stdout.trim()
  eq(open(plain), plain, "an ordinary file opens itself")
  eq(open(exe), dir, "a file with the executable bit opens its folder")
  fs.rmSync(dir, { recursive: true, force: true })
}

// ------------------------------------------------------ search roots ------
{
  const home = "/home/u"
  eq(Roots.cleanPath("~/NAS/", home), "/home/u/NAS", "~ is expanded and the trailing slash dropped")
  eq(Roots.cleanPath("/mnt//nas///docs", home), "/mnt/nas/docs", "repeated slashes collapse")
  eq(Roots.cleanPath("relative/path", home), "", "a relative path is refused")
  eq(Roots.cleanPath("/mnt/../etc", home), "", "a .. segment is refused")
  eq(Roots.cleanPath("/mnt/./x", home), "", "a . segment is refused")
  eq(Roots.cleanPath("/", home), "", "/ itself is refused")
  eq(Roots.cleanPath("/home/u", home), "", "$HOME itself is refused (searched already)")
  eq(Roots.cleanPath("/mnt/a\nb", home), "", "control characters are refused")
  eq(Roots.cleanPath(42, home), "", "a non-path is refused")

  const roots = Roots.normalizeRoots([
    { path: "/mnt/nas", label: "NAS", cacheMinutes: 60 },
    { path: "/mnt/nas/" },
    "junk", null, [],
    { path: "../x" },
    { path: "/media/disk", enabled: false, cacheMinutes: -3 },
    { path: "/mnt/cloud", label: "  \u0007 ", cacheMinutes: 2 }
  ], home)
  eq(roots.map(r => r.path), ["/mnt/nas", "/media/disk", "/mnt/cloud"], "invalid and duplicate roots are dropped")
  eq(roots.map(r => r.label), ["NAS", "disk", "cloud"], "a missing or blank label falls back to the folder name")
  eq(roots.map(r => r.enabled), [true, false, true], "enabled defaults to true")
  eq(roots.map(r => r.cacheMinutes), [60, 0, 5], "cache minutes: negative is live, tiny is raised to 5")
  assert(/^r[0-9a-f]{8}$/.test(roots[0].id) && roots[0].id === Roots.rootId("/mnt/nas"), "ids are stable path hashes")
  eq(Roots.normalizeRoots(Array.from({ length: 40 }, (_, i) => ({ path: "/mnt/r" + i })), home).length, Roots.MAX_ROOTS, "the root count is capped")
  eq(Roots.serializeRoots(roots)[0], { path: "/mnt/nas", label: "NAS", enabled: true, cacheMinutes: 60 }, "serialized roots carry no id")

  eq(Roots.addRoot([], "/mnt/share", home, "cifs")[0].cacheMinutes, 60, "a network share is added with an index")
  eq(Roots.addRoot([], "/mnt/disk", home, "ext4")[0].cacheMinutes, 0, "a local disk is added live")
  eq(Roots.addRoot([], "/mnt/r", home, "fuse.rclone")[0].cacheMinutes, 60, "fuse.* counts as network")
  eq(Roots.addRoot([], "/mnt/w", home, "fuseblk")[0].cacheMinutes, 0, "fuseblk (NTFS) counts as local")
  eq(Roots.addRoot([{ path: "/mnt/a" }], "/mnt/a/", home, "").length, 1, "adding a known root changes nothing")
  eq(Roots.addRoot([], "etc", home, "").length, 0, "adding an invalid path changes nothing")
  const id = Roots.rootId("/mnt/nas")
  eq(Roots.updateRoot([{ path: "/mnt/nas" }], home, id, r => { r.enabled = false; return r })[0].enabled, false, "updateRoot changes one root")
  eq(Roots.updateRoot([{ path: "/mnt/nas" }, { path: "/mnt/b" }], home, id, () => null).map(r => r.path), ["/mnt/b"], "updateRoot removes on null")
  eq(Roots.nextCache(0, 1), 15, "cache cycles forward")
  eq(Roots.nextCache(0, -1), 1440, "cache cycles backward and wraps")
  eq([0, 15, 60, 1440].map(Roots.cacheLabel), ["Live", "Index 15 min", "Index 1 h", "Index 1 d"], "cache labels")

  eq(Roots.rootFor("/mnt/nas/a/b", roots).path, "/mnt/nas", "rootFor finds the root of a path")
  eq(Roots.rootFor("/mnt/nasty", roots), null, "a sibling with a shared prefix is not inside")
  eq(Roots.homeExcludes([{ path: "/home/u/NAS" }, { path: "/mnt/x" }, { path: "/home/u/a*b" }], home), ["/NAS", "/a\\*b"],
     "roots inside $HOME become anchored, glob-escaped fd excludes")

  const now = Date.parse("2026-09-26T12:00:00Z")
  const due = (r, at, failed) => Roots.indexDue(Object.assign({ enabled: true, cacheMinutes: 60 }, r), at, failed, now)
  assert(due({}, 0, 0), "a missing index is due")
  assert(!due({}, now - 30 * 60000, 0), "a fresh index is not due")
  assert(due({}, now - 61 * 60000, 0), "a stale index is due")
  assert(!due({}, 0, now - 60000), "a failed rebuild waits before retrying")
  assert(due({}, 0, now - 11 * 60000), "and retries after the wait")
  assert(!due({ cacheMinutes: 0 }, 0, 0), "a live root is never indexed")
  assert(!due({ enabled: false }, 0, 0), "a disabled root is not indexed")

  const st = Roots.parseStatus("r0000000a\tonline\tnfs\t1000000\tnas:/export\t1790000000\t1234\n"
    + "r0000000b\toffline\t-\t-\t-\t-\t-\nbogus line\n")
  eq(st.r0000000a, { online: true, fsType: "nfs", freeBytes: 1000000, source: "nas:/export", indexedAt: 1790000000000, indexCount: 1234 }, "status line parsed")
  eq(st.r0000000b.online, false, "offline status parsed")
  eq(Object.keys(st).length, 2, "malformed status lines are ignored")
  eq(Roots.describe({ path: "/mnt/n", cacheMinutes: 60 }, st.r0000000a, 1790000000000 + 5 * 60000),
     "/mnt/n\nnfs · nas:/export · 1.0 MB free\n1 234 paths, indexed 5 min ago", "a root is described, one fact per line")
  eq(Roots.describe({ path: "/mnt/n", cacheMinutes: 0 }, st.r0000000b), "/mnt/n\noffline", "an offline root says so")
  eq(Roots.parsePicked("/mnt/a\tcifs\0/mnt/b c\t-\0"), [{ path: "/mnt/a", fsType: "cifs" }, { path: "/mnt/b c", fsType: "" }], "picker output parsed")
}

// ------------------------------------------------------ global shortcuts --
// Keys bound to hl.dsp.global("omarchy-menu-omni:<name>") reach the shell
// without starting a process; the names are part of the user's bindings.
{
  const fs = require("fs")
  const menuSource = fs.readFileSync(path.join(root, "Menu.qml"), "utf8")
  const names = Array.from(menuSource.matchAll(/GlobalShortcut \{\s*appid: "omarchy-menu-omni"\s*name: "([\w-]+)"/g), m => m[1])
  eq(names, ["toggle", "cycle-root", "toggle-apps", "toggle-windows", "toggle-clipboard", "toggle-system", "toggle-capture",
    "toggle-toggles", "toggle-hardware", "toggle-share"], "the menu's global shortcut names")
  eq(/if \(root\.shell\) \{[\s\S]*?root\.shell\.toggle\("omarchy\.menu"[\s\S]*?Quickshell\.execDetached\(\["omarchy-menu", "toggle", route\]\)/.test(menuSource), true,
     "a shortcut falls back to omarchy-menu until the shell API is there")
}

// ---------------------------------------- index, index search, status ----
{
  const fs = require("fs"), os = require("os"), { spawnSync } = require("child_process")
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omni-roots-"))
  const share = path.join(dir, "share"), cache = path.join(dir, "cache")
  for (const d of ["Docs/.hidden", "Fotky/leto", "node_modules/pkg"]) fs.mkdirSync(path.join(share, d), { recursive: true })
  for (const f of ["Docs/Správa 2024.pdf", "Docs/notes.md", "Docs/.hidden/secret.txt", "Fotky/leto/IMG_1.JPG", "node_modules/pkg/index.js", "Docs/new\nline.txt"])
    fs.writeFileSync(path.join(share, f), "x")
  const root = { id: Roots.rootId(share), path: share }
  const run = (argv) => spawnSync(argv[0], argv.slice(1), { encoding: "utf8" })

  eq(run(Roots.indexCommand(cache, root, FileSearch.EXCLUDES)).status, 0, "an index is built")
  const idx = Roots.indexPath(cache, root.id)
  eq(fs.statSync(idx).mode & 0o777, 0o600, "the index is private")
  const search = (kinds, hidden, exts, q) => run(Roots.indexSearchCommand(kinds, hidden, exts, FileSearch.extractTerms(q), [{ root: share, index: idx }]))
    .stdout.split("\0").filter(Boolean).map(p => p.slice(share.length + 1)).sort()
  eq(search("f", true, [], "sprava"), ["Docs/Správa 2024.pdf"], "the index search is accent-insensitive")
  eq(search("f", false, [], ""), ["Docs/Správa 2024.pdf", "Docs/new\nline.txt", "Docs/notes.md", "Fotky/leto/IMG_1.JPG"],
     "hidden paths and excluded folders are left out; a newline in a name survives")
  assert(search("f", true, [], "secret").length === 1, "hidden paths are found when the filter includes them")
  eq(search("f", true, ["jpg"], ""), ["Fotky/leto/IMG_1.JPG"], "extensions filter case-insensitively")
  eq(search("d", true, [], "leto"), ["Fotky/leto/"], "folders keep their trailing slash")
  eq(search("df", true, [], "docs notes"), ["Docs/notes.md"], "every term has to match")
  eq(search("f", true, [], "a.b(").length, 0, "regex metacharacters in a query are literal")
  eq(run(Roots.indexSearchCommand("f", true, [], [], [{ root: share, index: idx + ".missing" }])).status, 0, "a missing index finds nothing")
  fs.symlinkSync(idx, path.join(cache, "link.idx"))
  eq(run(Roots.indexSearchCommand("f", true, [], [], [{ root: share, index: path.join(cache, "link.idx") }])).stdout, "", "a symlinked index is not read")

  // A cut-off record (no final NUL) is skipped rather than read as a path.
  fs.writeFileSync(idx, share + "/Docs/notes.md\0" + share + "/Docs/cut")
  eq(search("f", true, [], ""), ["Docs/notes.md"], "a truncated last record is skipped")

  eq(run(Roots.indexCommand(cache, { id: "r00000001", path: path.join(dir, "gone") }, [])).status, 4, "an unreachable root keeps its old index")
  const status = Roots.parseStatus(run(Roots.statusCommand(cache, [root, { id: "r00000001", path: path.join(dir, "gone") }])).stdout)
  assert(status[root.id].online && status[root.id].indexedAt > 0 && status[root.id].indexCount === 1, "status of a reachable, indexed root")
  eq(status.r00000001.online, false, "status of an unreachable root")
  fs.rmSync(dir, { recursive: true, force: true })
}

// ---------------------------------------------------------- tab highlight --
// repeater.itemAt() is not a binding dependency; the pill has to re-read it
// whenever chips are created or destroyed, or it stays on a dead chip (the
// highlight was missing on 7 of 8 first opens after a restart).
{
  const fs = require("fs")
  const bar = fs.readFileSync(path.join(root, "TabBar.qml"), "utf8")
  eq(/readonly property Item activeChip: bar\.chipsVersion >= 0 &&/.test(bar), true, "the active chip is re-read when chips change")
  eq(/onItemAdded: bar\.chipsVersion\+\+/.test(bar) && /onItemRemoved: bar\.chipsVersion\+\+/.test(bar), true, "adding or removing a chip bumps chipsVersion")
}

// ----------------------------------------------------- roots in results ---
{
  const home = "/home/u"
  const roots = [{ id: "r1", path: "/mnt/nas", label: "NAS" }]
  const items = FileSearch.parseLines(["/mnt/nas/Photos/2024/a.jpg", "/mnt/nas/Photos/", "/mnt/nas/.cfg/x", "/home/u/b.txt"].join("\0"), null, home, roots)
  eq(items.map(i => [i.name, i.dir, i.isDir, i.rootId]), [
    ["a.jpg", "NAS › Photos/2024", false, "r1"], ["Photos", "NAS", true, "r1"], ["x", "NAS › .cfg", false, "r1"], ["b.txt", "~", false, ""]
  ], "root items carry their label, kind from the trailing slash")
  eq(items.map(i => i.isSystem), [false, false, true, false], "dotted paths inside a root rank as system, the rest as the user's")
  eq(FileSearch.filtersFor("files").map(f => f.id).indexOf("remotes"), -1, "roots are a scope, not a type filter")
  const live = FileSearch.buildRootArgv("foto", FileSearch.ALL_FILTER, true, true, ["/mnt/a", "/mnt/b"])
  assert(live.indexOf("--follow") < 0, "live roots are walked without following links")
  eq(live.slice(-4), ["--", "f[oóòõôö]t[oóòõôö]", "/mnt/a", "/mnt/b"], "live roots are the search paths")
  eq(live.filter((a, i) => live[i - 1] === "--type"), ["d", "f"], "both kinds in one live search")
  const homeArgv = FileSearch.buildArgv("x", FileSearch.ALL_FILTER, false, home, ["/NAS"])
  assert(homeArgv.join(" ").indexOf("-E /NAS") >= 0, "the $HOME search excludes roots inside it")
}

// ----------------------------------------------------------- zoxide ------
{
  const home = "/home/u"
  const z = FileSearch.parseZoxide("  35.5 /home/u/work/menuland\n  2.0 /home/u/.config/hypr\ngarbage\n 1 relative\n")
  eq(z, { "/home/u/work/menuland": 35.5, "/home/u/.config/hypr": 2 }, "zoxide scores parsed")
  const items = FileSearch.parseLines(["/home/u/aa/menuland/", "/home/u/work/menuland/", "/home/u/work/menuland/plan.md"].join("\0"), null, home)
  eq(FileSearch.rankResults(items.slice(0, 2), "menuland", 5, home, "relevance", null).map(i => i.path)[0], "/home/u/aa/menuland",
     "without zoxide equal matches keep path order")
  eq(FileSearch.rankResults(items.slice(0, 2), "menuland", 5, home, "relevance", z).map(i => i.path)[0], "/home/u/work/menuland",
     "a frecent folder wins between equal matches")
  assert(FileSearch.frecencyBonus(items[2], z) > 0 && FileSearch.frecencyBonus(items[2], z) <= 0.5, "a file in a frecent folder gets a smaller lift")
  assert(FileSearch.frecencyBonus(items[1], { "/home/u/work/menuland": 1e9 }) <= 1.5, "the lift is capped")
  const hypr = FileSearch.parseLines("/home/u/.config/hypr/\0/home/u/hyprland-notes/", true, home)
  eq(FileSearch.rankResults(hypr, "", 5, home, "relevance", z)[0].path, "/home/u/.config/hypr", "a frecent dotted folder is not demoted")
  eq(FileSearch.zoxideItems(z, "hypr", home, [], 10).map(i => i.path), ["/home/u/.config/hypr"], "zoxide folders matching the query")
  eq(FileSearch.zoxideItems(z, "", home, [], 10), [], "no zoxide folders without a query")
  const dup = FileSearch.parseLines("/home/u/.config/hypr/", true, home).concat(FileSearch.zoxideItems(z, "hypr", home, [], 10))
  eq(FileSearch.rankResults(dup, "hypr", 5, home, "relevance", z).length, 1, "a folder found twice is listed once")
}

// ---------------------------------------------------------------- windows --

// The fixture: two workspaces, the scratchpad, and the clients Hyprland
// reports that nobody can switch to.
const clientsJson = JSON.stringify([
  { address: "0xa1", class: "foot", title: "~/src", workspace: { id: 2, name: "2" }, focusHistoryID: 3, mapped: true, hidden: false },
  { address: "0xa2", class: "zen", title: "TIDAL | Login", workspace: { id: 1, name: "1" }, focusHistoryID: 1, floating: true },
  { address: "0xa3", class: "foot", title: "Claude Code", workspace: { id: 1, name: "1" }, focusHistoryID: 0 },
  { address: "0xa4", class: "spotify", title: "Spotify", workspace: { id: -98, name: "special:scratchpad" }, focusHistoryID: 5 },
  { address: "0xa5", class: "ghost", title: "tab in a group", workspace: { id: 1, name: "1" }, hidden: true },
  { address: "0xa6", class: "gone", title: "tearing down", workspace: { id: 1, name: "1" }, mapped: false },
  { address: "not-an-address", class: "evil", title: "x", workspace: { id: 1, name: "1" } },
  "junk", null
])
const openWindows = Windows.parseClients(clientsJson)
const [srcTerminal, tidalLogin, claudeTerminal, spotifyOnScratchpad] = openWindows

// A window as parseClients would produce it, for cases the fixture lacks.
function openWindow(fields) {
  return Object.assign({
    address: "0xf0", windowClass: "x", title: "t", workspaceId: 1, workspaceName: "1",
    isSpecialWorkspace: false, isFloating: false, focusRecency: 0
  }, fields)
}
const onSpecialWorkspace = (name, fields) =>
  openWindow(Object.assign({ workspaceId: -97, workspaceName: "special:" + name, isSpecialWorkspace: true }, fields))

// Parsing.
eq(openWindows.map(w => w.address), ["0xa1", "0xa2", "0xa3", "0xa4"], "hidden, unmapped and bad-address clients are dropped")
eq(tidalLogin, {
  address: "0xa2", windowClass: "zen", title: "TIDAL | Login", workspaceId: 1, workspaceName: "1",
  isSpecialWorkspace: false, isFloating: true, focusRecency: 1
}, "a client becomes an open window")
eq(spotifyOnScratchpad.isSpecialWorkspace, true, "negative ids and special: names are special workspaces")
eq(Windows.parseClients(JSON.stringify([{ address: "0xa7", class: "x", title: "t", workspace: { id: 1, name: "1" } }]))[0].focusRecency,
   Windows.MAX_WINDOWS, "a window without focus history sorts last")
eq(Windows.parseClients("{not json"), [], "malformed client JSON is an empty list")
eq(Windows.parseClients('{"a":1}'), [], "a non-array client list is an empty list")
eq(Windows.parseClients(JSON.stringify([{ address: "0xa8", class: "x".repeat(5000), title: "t", workspace: {} }]))[0].windowClass.length,
   256, "long strings are cut to their bound")

// Workspaces.
eq(Windows.workspaceLabel(spotifyOnScratchpad), "Scratchpad", "the scratchpad has a name")
eq(Windows.workspaceLabel(onSpecialWorkspace("music")), "music (special)", "other special workspaces are marked")
eq(Windows.workspaceLabel(openWindow({ workspaceName: "not-special:x" })), "not-special:x", "special: only counts as a prefix")
eq(Windows.workspaceTrail(srcTerminal), "ws 2", "regular workspaces trail as ws N")
eq(Windows.workspaceTrail(spotifyOnScratchpad), "scratch", "the scratchpad trails as scratch")
eq(Windows.workspaceTrail(onSpecialWorkspace("music")), "music", "other special workspaces trail by name")

// Rows and their order.
const appForClass = windowClass => windowClass === "zen" ? { id: "zen-browser", name: "Zen Browser", icon: "zen" } : null
const rowTargets = (query, windows) => Windows.windowRows(windows || openWindows, query, appForClass).map(row => row.target)
const allRows = Windows.windowRows(openWindows, "", appForClass)
const tidalRow = allRows[1]

eq(rowTargets(""), ["0xa3", "0xa2", "0xa1", "0xa4"], "grouped by workspace, most recent first, scratchpad last")
eq(rowTargets("", [onSpecialWorkspace("zzz", { address: "0xz" }), onSpecialWorkspace("aaa", { address: "0xa" }), openWindow({ address: "0x1" })]),
   ["0x1", "0xa", "0xz"], "special workspaces follow the regular ones, by name")
eq(allRows.every(row => row.kind === "window"), true, "window rows have their own kind")
eq(tidalRow.detail, "Zen Browser · floating", "detail names the app and floating; the workspace is the trail")
eq(tidalRow.trailText, "ws 1", "the trail names the workspace")
eq([tidalRow.appIcon, tidalRow.icon], ["zen", ""], "a matched desktop entry supplies the icon")
eq([allRows[0].appIcon, allRows[0].icon], ["", "󰖯"], "an unmatched class falls back to a glyph")
eq([allRows[3].detail, allRows[3].trailText], ["spotify", "scratch"], "scratchpad windows say so in the trail")
eq(Windows.windowRows([onSpecialWorkspace("music")], "", null)[0].detail, "x · music (special)", "other special workspaces are named in the detail")
eq(Windows.windowRows(Windows.parseClients(JSON.stringify([{ address: "0xc1", class: "chrome-musicforprogramming.net__-Default", title: "mfp", workspace: { id: 3, name: "3" } }])), "", null)[0].detail,
   "musicforprogramming.net", "an unmatched web app is named by its host")

// Searching.
eq(rowTargets("tidal"), ["0xa2"], "the query matches the title")
eq(rowTargets("zen"), ["0xa2"], "the query matches the app name")
eq(rowTargets("scratch"), ["0xa4"], "the query matches the workspace")
eq(rowTargets("foot claude"), ["0xa3"], "every word has to match")
eq(rowTargets("nothing-here"), [], "no match, no rows")
const { MatchRank } = Windows
eq([
  Windows.matchRank(claudeTerminal, "Foot", "cla"),
  Windows.matchRank(claudeTerminal, "Foot", "code"),
  Windows.matchRank(claudeTerminal, "Foot", "ws 1"),
  Windows.matchRank(claudeTerminal, "Foot", "vim")
], [MatchRank.PREFIX, MatchRank.SUBSTRING, MatchRank.OTHER_FIELD, MatchRank.NO_MATCH], "match ranks: prefix, substring, other field, none")
eq(rowTargets("code", [
  openWindow({ address: "0x1", title: "Claude Code", workspaceId: 1 }),
  openWindow({ address: "0x2", title: "Code editor", workspaceId: 2 })
]), ["0x2", "0x1"], "with a query, a better match beats a lower workspace")

// Web apps.
eq(Windows.webappHost("chrome-musicforprogramming.net__-Default"), "musicforprogramming.net", "a web app class gives its host")
eq(Windows.webappHost("chrome-app.hey.com__calendar-Default"), "app.hey.com", "the path after the host is ignored")
eq(Windows.webappHost("foot"), "", "an ordinary class is not a web app")
eq(Windows.webappNameKeys("chrome-musicforprogramming.net__-Default"), ["musicforprogramming"], "host keys drop the TLD")
eq(Windows.webappNameKeys("chrome-app.hey.com__-Default"), ["apphey", "hey"], "uninformative labels are skipped")
eq(Windows.webappNameKeys("chrome-web.whatsapp.com__-Default"), ["webwhatsapp", "whatsapp"], "whatsapp matches by its label")
eq(Windows.webappNameKeys("foot"), [], "an ordinary class has no web app keys")
eq(Windows.normalizeName("Music For Programming"), "musicforprogramming", "names normalize for matching")

// Running applications.
const appIdByClass = { foot: "foot", zen: "zen-browser" }
const windowsByAppId = Windows.windowsByAppId(openWindows, windowClass => appIdByClass[windowClass] || "")
eq(Array.from(windowsByAppId.keys()).sort(), ["foot", "zen-browser"], "only windows with a desktop entry mark an app")
eq(windowsByAppId.get("foot"), ["0xa3", "0xa1"], "an app's windows are most recently focused first")
eq(windowsByAppId.get("zen-browser"), ["0xa2"], "each app keeps its own windows")
eq(Windows.windowsByAppId(null, null).size, 0, "no windows, nothing running")
eq(Windows.windowsByAppId([openWindow({ windowClass: "__proto__" })], () => "__proto__").get("__proto__"), ["0xf0"],
   "any string is a safe app id")
eq([Windows.runningLabel(0), Windows.runningLabel(1), Windows.runningLabel(3)], ["", "running", "3 windows"], "running labels")

// Focusing.
const focusArgv = Windows.focusCommand("0xa2")
eq([focusArgv[0], focusArgv[1], focusArgv[3], focusArgv[4]], ["bash", "-c", "omarchy-menu-focus", "0xa2"], "the address travels as an argument")
eq(focusArgv[2].includes("0xa2"), false, "the address is never part of the script")
eq(Windows.focusCommand("0xa2; rm -rf ~"), null, "anything but an address is refused")
eq(Windows.focusCommand(""), null, "an empty address is refused")

// A controller method named like a built-in Item property (focus, visible,
// enabled, ...) is shadowed by the property, and calling it throws.
{
  const fs = require("fs")
  const controllerSource = fs.readFileSync(path.join(root, "WindowsController.qml"), "utf8")
  const itemProperties = ["focus", "visible", "enabled", "opacity", "state", "clip", "children", "data", "parent", "x", "y", "width", "height", "z"]
  const methodNames = Array.from(controllerSource.matchAll(/^\s*function (\w+)\(/gm), match => match[1])
  eq(methodNames.filter(name => itemProperties.includes(name)), [], "WindowsController methods do not shadow Item properties")
}

// Node parses object rest/spread ({ ...rest }, ES2018) but Quickshell's
// engine does not, and one syntax error unloads the whole module -- so a
// test run here would pass while the plugin failed to load.
{
  const fs = require("fs")
  // `{ ...a }` or `{ x, ...rest }`; array spread (`[a, ...b]`) is fine.
  const objectSpread = /\{\s*\.\.\.\w|,\s*\.\.\.\w+\s*\}/
  for (const file of ["Windows.js", "WindowsController.qml"]) {
    const source = fs.readFileSync(path.join(root, file), "utf8").replace(/^\s*\/\/.*$/gm, "")
    eq(objectSpread.test(source), false, file + " has no object rest/spread")
  }
}

// The window list is read the first time something in an open shows it,
// not on every open.
{
  const fs = require("fs")
  const tracker = fs.readFileSync(path.join(root, "WindowsController.qml"), "utf8")
  const onOpened = (tracker.match(/function onOpenedChanged\(\) \{[\s\S]*?\n    \}/) || [""])[0]
  eq(/refresh\(\)/.test(onOpened), false, "opening the menu does not read the window list")
  eq(/onWindowsNeededChanged[\s\S]*?tracker\.refresh\(\)/.test(tracker), true, "the window list is read once something shows it")
  eq(/tracker\.openWindows = \[\]/.test(onOpened) && /tracker\.windowsByAppId = new Map\(\)/.test(onOpened), true,
     "closing the menu drops the window list instead of keeping it stale")
}

// ------------------------------------------------- model draft editing --
{
  const ed = Settings.editModelDraft
  eq(ed("hai", "", "k", false), "haik", "a typed character is appended")
  eq(ed("x", "", "a b;$(rm)", false), "xabrm", "characters a model name cannot hold are dropped")
  eq(ed("gpt-6/luna", "", ":@._-", false), "gpt-6/luna:@._-", "the model punctuation is kept")
  eq(ed("haiku", "backspace", "", false), "haik", "Backspace removes one character")
  eq(ed("haiku", "backspace", "", true), "", "Ctrl+Backspace clears")
  eq(ed("haiku", "clear", "", true), "", "Ctrl+U clears")
  eq(ed("haiku", "", "v", true), "haiku", "a Ctrl chord (Ctrl+V) types nothing and pastes nothing")
  eq(ed("a".repeat(127), "", "bcd", false).length, Settings.MODEL_MAX, "the draft stops at the model name limit")
  assert(Settings.MODEL_PATTERN.test(ed("", "", "openai-codex/gpt-6-luna", false)), "a typed model name passes the save check")
}

// --------------------------------------------------------- clipboard tab --
{
  // Plumbing: a tab with its own route, never a section of All.
  assert(Tabs.isTab("clipboard"), "clipboard is a tab")
  eq(Tabs.tabForRoute("clipboard"), { tab: "clipboard", menu: "root" }, "the clipboard route opens Clipboard")
  assert(Tabs.DEFAULT_ALL_SECTIONS.indexOf("clipboard") < 0, "All has no Clipboard section")
  eq(Tabs.orderSections(["clipboard", "apps"]).map(s => s.id), Tabs.DEFAULT_ALL_SECTIONS,
     "allSections cannot bring Clipboard into All")
  eq(Tabs.normalizeSectionsOff(["clipboard"]), [], "allSectionsOff ignores clipboard")
  eq(Tabs.sectionHeader("clipboard"), "", "clipboard rows get no All header")
  assert(Settings.OPEN_TABS.indexOf("clipboard") >= 0, "openTab may name clipboard")
  const fs = require("fs")
  const menuSource = fs.readFileSync(path.join(root, "Menu.qml"), "utf8")
  assert(/function inAll\(id\) \{\s*return Tabs\.DEFAULT_ALL_SECTIONS\.indexOf\(id\) >= 0 &&/.test(menuSource),
         "inAll only answers for All's own sections")
  assert(/tabRoute\.tab === "clipboard"\) entry = null/.test(menuSource),
         "the clipboard route wins over a menu entry of that name")
  const controller = fs.readFileSync(path.join(root, "ClipboardController.qml"), "utf8")
  assert(controller.indexOf("Settings.readFileCommand(clip.historyPath, Clipboard.MAX_HISTORY_BYTES, 5)") >= 0,
         "the history is read through the guarded reader")
  assert(!/wl-paste|Quickshell\.clipboard|setText|FileView/.test(controller), "the controller never reads the clipboard nor writes")

  const dir = "/home/u/.local/state/omarchy/clipboard-images/"
  const png = dir + "a.png"
  const history = JSON.stringify([
    { type: "text", text: "  \n\n  hello   world \t again\nsecond line" },
    "bare string",
    { type: "image", path: png, mime: "image/png", capturedAt: "Monday 10:00" },
    { type: "text", text: "   " },
    { type: "image", path: dir + "../../../.ssh/id_ed25519", mime: "image/png" },
    { type: "image", path: dir + "x/./y.png", mime: "image/png" },
    { type: "image", path: "relative.png", mime: "image/png" },
    { type: "image", path: "/tmp/clipboard-images/a.png", mime: "image/png" },
    { type: "image", path: dir, mime: "image/png" },
    { type: "image", path: dir + "b.png", mime: "text/html" },
    { type: "image", path: dir + "b.png", mime: "image/png; rm -rf" },
    { type: "image", path: dir + "b.png", mime: "IMAGE/PNG" },
    { type: "image", path: dir + "b.png" },
    { type: "text", text: 42 },
    { type: "file", text: "x" },
    null, 7, ["nested"],
    { type: "text", text: "Café crème\nline" },
    { type: "image", path: dir + "sub/c.webp", mime: "image/svg+xml", capturedAt: 5 }
  ])
  const entries = Clipboard.parseHistory(history, dir)
  eq(entries.map(e => e.index), [0, 1, 2, 18, 19], "valid entries keep their history index, the rest are dropped")
  eq(entries.map(e => e.type), ["text", "text", "image", "text", "image"], "entry types")
  eq(Clipboard.parseHistory("not json", dir), [], "malformed history is empty")
  eq(Clipboard.parseHistory('{"type":"text"}', dir), [], "a non-array history is empty")
  eq(Clipboard.parseHistory("", dir), [], "an empty history file is empty")
  eq(Clipboard.parseHistory(JSON.stringify([{ type: "image", path: png, mime: "image/png" }]), ""), [],
     "no image is trusted without the image folder")
  eq(Clipboard.parseHistory(JSON.stringify(Array(2000).fill("x")), dir).length, Clipboard.MAX_ENTRIES, "entries are capped")
  assert(!Clipboard.isSafeImagePath(dir + "a\u0000.png", dir), "a NUL in an image path is refused")
  assert(!Clipboard.isSafeImagePath(dir + "a//b.png", dir), "an empty path segment is refused")
  assert(Clipboard.isImageMime("image/vnd.microsoft.icon") && !Clipboard.isImageMime("image/"), "image mime shape")

  const rows = Clipboard.clipboardRows(entries, "")
  eq(rows[0].label, "hello world again", "label is the first non-empty line, whitespace collapsed")
  eq(rows[0].detail, "4 lines · 39 chars", "text detail counts lines and characters")
  eq(rows[0].target, "0", "the row carries only the history index")
  eq(rows[0].kind, "clipboard", "clipboard row kind")
  eq(rows[1].disabled, false, "a bare string can be acted on")
  eq(rows[2].label, "Image from Monday 10:00", "image label")
  eq(rows[2].detail, "Image · image/png · Monday 10:00", "image detail")
  eq(rows[4].detail, "Image · image/svg+xml", "a non-string capture time is dropped")
  assert(rows.every(r => r.path === ""), "no row shows an image path")
  const roleSet = JSON.stringify(Object.keys(rows[0]).sort())
  assert(rows.every(r => JSON.stringify(Object.keys(r).sort()) === roleSet), "every row has the same roles")
  assert(Object.keys(Windows.windowRows([{ address: "0x1", windowClass: "a", title: "t", workspaceId: 1,
    workspaceName: "1", isSpecialWorkspace: false, isFloating: false, focusRecency: 0 }], "", () => null)[0]).sort()
    .every(role => role in rows[0]), "clipboard rows carry every role a window row does")

  const hostile = Clipboard.parseHistory(JSON.stringify([
    { type: "text", text: "\u202eevil\u0007\u0000 <img src=http://x>" },
    { type: "text", text: "x".repeat(100000) },
    { type: "text", text: "a\u2028b" }
  ]), dir)
  const hostileRows = Clipboard.clipboardRows(hostile, "").map(r => MenuModel.sanitizeRow(r))
  assert(!/[\u0000-\u001f\u202e]/.test(hostileRows[0].label), "control and bidi characters never reach a label")
  eq(hostileRows[1].label.length, Clipboard.LABEL_LENGTH, "a huge entry's label is cut")
  assert(hostileRows[1].label.endsWith("…"), "a cut label says so")
  eq(hostileRows[1].detail, "1 line · 100000 chars", "a huge entry's detail")
  eq(hostileRows[2].label, "a", "a Unicode line separator ends the first line")
  eq(Clipboard.textLabel("\n\n\t\n"), "", "a label of only whitespace is empty")

  eq(Clipboard.clipboardRows(entries, "CAFE").map(r => r.target), ["18"], "search ignores case and accents")
  eq(Clipboard.clipboardRows(entries, "second hello").map(r => r.target), ["0"], "every word, anywhere in the full text")
  eq(Clipboard.clipboardRows(entries, "png").map(r => r.target), ["2"], "images match on their mime")
  eq(Clipboard.clipboardRows(entries, "nothing like it"), [], "no match")
  const long = Clipboard.parseHistory(JSON.stringify([{ type: "text", text: "a".repeat(20000) + " needle" }]), dir)
  eq(Clipboard.clipboardRows(long, "needle").length, 1, "search reaches past the label")

  assert(Clipboard.isHistoryIndex(0) && Clipboard.isHistoryIndex("12"), "history index")
  for (const bad of [-1, 1.5, "1.5", "-1", "--copy-only", "", " 1", "1e3", NaN, Infinity, null, undefined, {}, [], "99999999999999999999"])
    assert(!Clipboard.isHistoryIndex(bad), "not a history index: " + JSON.stringify(bad))
  eq(Clipboard.entryAt(entries, "2").path, png, "entryAt finds by history index")
  eq(Clipboard.entryAt(entries, "3"), null, "entryAt misses a dropped index")
  eq(Clipboard.entryAt(entries, "--help"), null, "entryAt refuses a non-index")

  const bin = "/usr/share/omarchy/bin"
  const verified = { [png]: true }
  const action = (entry, operation) => Clipboard.actionFor(entry, bin, operation, verified)
  const paste = action(entries[0], "paste")
  eq(paste.command.slice(0, 6), ["timeout", "-k", "1", "10", "bash", "-c"], "bounded text paste")
  eq(paste.input, entries[0].text, "paste sends the original whitespace and text on stdin")
  assert(paste.command.every(arg => !arg.includes(entries[0].text)), "text stays off the command line")
  eq(action(entries[1], "copy"),
     { command: ["timeout", "-k", "1", "10", "wl-copy"], input: entries[1].text }, "copy legacy text")
  const imagePaste = action(entries[2], "paste").command
  eq(imagePaste.slice(0, 6), ["timeout", "-k", "1", "10", "bash", "-c"], "bounded image paste")
  eq(imagePaste.slice(7), ["omni-paste", "app", "image/png", png], "image paste passes mode, mime and path as arguments")
  eq(action(entries[2], "paste").input, undefined, "image paste has no stdin")
  eq(action(entries[2], "copy").command,
     ["timeout", "-k", "1", "10", bin + "/omarchy-clipboard-paste-file", "--copy-only", "image/png", png], "copy checked image")
  eq(action(entries[2], "open").command, ["omasnap", "--notify", png], "open checked image directly")
  eq(Clipboard.actionFor(entries[2], bin, "open", {}), null, "unverified images cannot be opened")
  eq(action(entries[1], "open").input, entries[1].text, "open legacy text from the snapshot")
  eq(action({ type: "text", text: "Link: https://example.com/a" }, "open"),
     { command: [bin + "/omarchy-launch-browser", "https://example.com/a"] }, "open an HTTP(S) link")
  eq(action({ type: "text", text: "example.com/a" }, "open").command[1],
     "https://example.com/a", "open bare domain with HTTPS")
  assert(action({ type: "text", text: "file:///tmp/example" }, "open").edit, "other schemes open as plain text")
  const updated = Clipboard.parseHistory(JSON.stringify(["newer entry", entries[0].text]), dir)
  assert(updated[0].text !== paste.input, "new clipboard history can reuse the visible entry's index")
  eq(action(Clipboard.entryAt(entries, rows[0].target), "copy").input,
     entries[0].text, "a reused disk index cannot replace the visible snapshot entry")
  eq(action(null, "paste"), null, "no entry, no command")
  eq(action(entries[0], "other"), null, "unknown action, no command")
  eq(action({ type: "image", path: png, mime: "--help" }, "paste"), null,
     "a forged mime is refused")
  // Paste target: only a fixed token reaches the command.
  const modeAction = (entry, mode) => Clipboard.actionFor(entry, bin, "paste", verified, mode)
  eq(modeAction(entries[0], "terminal").command.slice(-2), ["omni-paste", "terminal"], "terminal text paste")
  eq(modeAction(entries[2], "terminal").command.slice(-4), ["omni-paste", "terminal", "image/png", png], "terminal image paste")
  eq(modeAction(entries[0], "kitty; rm -rf ~").command.slice(-1), ["app"], "an unknown mode is app")
  eq(modeAction(entries[0], undefined).command.slice(-1), ["app"], "no mode is app")
  assert(!Clipboard.actionFor(entries[0], bin, "copy", verified, "terminal").command.includes("terminal"), "copy ignores the mode")
  eq(Clipboard.activeWindowCommand(), ["bash", "-c", "timeout -k 1 2 hyprctl -j activewindow | head -c 65536"],
     "active window read is bounded")
  const win = (props) => JSON.stringify(Object.assign({ address: "0x1", class: "firefox", tags: [] }, props))
  eq(Clipboard.pasteModeFor(win({})), "app", "a browser is an app")
  eq(Clipboard.pasteModeFor(win({ tags: ["terminal*"] })), "terminal", "Hyprland's dynamic terminal tag")
  eq(Clipboard.pasteModeFor(win({ class: "org.omarchy.btop", tags: ["terminal"] })), "terminal", "a static terminal tag")
  eq(Clipboard.pasteModeFor(win({ tags: ["terminally-ill*", "xterminal"] })), "app", "only the exact tag counts")
  for (const cls of ["Alacritty", "kitty", "foot", "footclient", "com.mitchellh.ghostty", "org.wezfurlong.wezterm",
                     "org.kde.konsole", "org.gnome.Terminal", "org.gnome.Ptyxis", "herdr"]) {
    eq(Clipboard.pasteModeFor(win({ class: cls })), "terminal", "terminal class " + cls)
  }
  eq(Clipboard.pasteModeFor(win({ class: "kitty-ish" })), "app", "a class is matched whole")
  eq(Clipboard.pasteModeFor(win({ class: "constructor" })), "app", "prototype names are not terminals")
  eq(Clipboard.pasteModeFor(win({ class: ["kitty"] })), "app", "a non-string class is ignored")
  eq(Clipboard.pasteModeFor(win({ tags: "terminal" })), "app", "a non-array tags field is ignored")
  eq(Clipboard.pasteModeFor("{}"), "app", "no active window is an app")
  eq(Clipboard.pasteModeFor("[]"), "app", "a non-object is an app")
  eq(Clipboard.pasteModeFor("{\"class\": \"kit"), "app", "cut-off output is an app")
  eq(Clipboard.pasteModeFor(win({ class: "kitty", title: "x".repeat(70000) })), "app", "output at the cap is an app")
  eq(Clipboard.pasteModeFor(null), "app", "no output is an app")
  assert(Clipboard.TERMINAL_CLASSES.every(c => c === c.toLowerCase()), "the allow-list is lower case")

  eq(Clipboard.helpersCheckCommand(bin), ["timeout", "-k", "1", "2", "test",
     "-x", bin + "/omarchy-clipboard-paste-file"], "helper check")

  // Run the real action commands without touching the desktop or clipboard.
  const { spawnSync } = require("child_process")
  const temp = fs.mkdtempSync(path.join(require("os").tmpdir(), "omni-clipboard-test-"))
  try {
    fs.writeFileSync(path.join(temp, "wl-copy"), '#!/bin/sh\ncat > "$TMPDIR/copied"\n', { mode: 0o700 })
    fs.writeFileSync(path.join(temp, "wtype"), '#!/bin/sh\nprintf "%s\\n" "$@" > "$TMPDIR/keys"\n', { mode: 0o700 })
    const run = ({ command, input }) => spawnSync(command[0], command.slice(1), {
      input, encoding: "utf8", env: { ...process.env, PATH: temp + ":" + process.env.PATH, TMPDIR: temp }
    })
    const text = "--copy-only\nCafé\n" + "x".repeat(140000) + "\n\n"
    const entry = { type: "text", text }
    eq(run(action(entry, "copy")).status, 0, "text copy succeeds")
    eq(fs.readFileSync(path.join(temp, "copied"), "utf8") === text, true, "copy preserves large text verbatim")
    assert(!fs.existsSync(path.join(temp, "keys")), "copy does not inject keys")
    eq(run(paste).status, 0, "snapshot paste succeeds")
    eq(fs.readFileSync(path.join(temp, "copied"), "utf8"), paste.input, "paste copies the selected text")
    eq(fs.readFileSync(path.join(temp, "keys"), "utf8"), "-M\nshift\n-k\nInsert\n-m\nshift\n", "paste sends Shift+Insert")
    fs.unlinkSync(path.join(temp, "keys"))
    const termPaste = Clipboard.actionFor(entry, bin, "paste", verified, "terminal")
    eq(run(termPaste).status, 0, "terminal paste succeeds")
    eq(fs.readFileSync(path.join(temp, "keys"), "utf8"), "-M\nctrl\n-M\nshift\n-k\nv\n-m\nshift\n-m\nctrl\n",
       "terminal paste sends Ctrl+Shift+V")
    fs.unlinkSync(path.join(temp, "keys"))
    // An image goes to wl-copy straight from its file, with its mime type.
    const picture = path.join(temp, "a b$(x).png")
    fs.writeFileSync(picture, "\x89PNG fake")
    fs.writeFileSync(path.join(temp, "wl-copy"), '#!/bin/sh\nprintf "%s\\n" "$@" > "$TMPDIR/args"\ncat > "$TMPDIR/copied"\n',
                     { mode: 0o700 })
    const imageEntry = { type: "image", path: picture, mime: "image/png" }
    for (const [mode, keys] of [["app", "-M\nshift\n-k\nInsert\n-m\nshift\n"],
                                ["terminal", "-M\nctrl\n-M\nshift\n-k\nv\n-m\nshift\n-m\nctrl\n"]]) {
      eq(run(Clipboard.actionFor(imageEntry, bin, "paste", { [picture]: true }, mode)).status, 0, mode + " image paste succeeds")
      eq(fs.readFileSync(path.join(temp, "args"), "utf8"), "--type\nimage/png\n", mode + " image paste copies with its mime")
      eq(fs.readFileSync(path.join(temp, "copied"), "utf8"), "\x89PNG fake", mode + " image paste copies the file")
      eq(fs.readFileSync(path.join(temp, "keys"), "utf8"), keys, mode + " image paste key")
      fs.unlinkSync(path.join(temp, "keys"))
    }
    fs.unlinkSync(picture)
    eq(run(Clipboard.actionFor(imageEntry, bin, "paste", { [picture]: true }, "app")).status, 1, "a vanished image fails")
    assert(!fs.existsSync(path.join(temp, "keys")), "a vanished image sends no keys")
    fs.writeFileSync(path.join(temp, "wl-copy"), "#!/bin/sh\nexit 1\n")
    eq(run(paste).status, 1, "copy failure stops paste")
    assert(!fs.existsSync(path.join(temp, "keys")), "copy failure sends no keys")
    const edit = run(action(entry, "open"))
    eq(edit.status, 0, "opening plain text prepares an editor file")
    eq(path.dirname(edit.stdout), temp, "editor file stays in the temp directory")
    eq(fs.statSync(edit.stdout).mode & 0o777, 0o600, "editor file is private")
    eq(fs.readFileSync(edit.stdout, "utf8") === text, true, "editor file preserves the selected text")
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }

  // Image previews: one stat per read decides which files may be drawn.
  const webp = dir + "sub/c.webp"
  eq(Clipboard.imageStatCommand(entries), ["timeout", "-k", "1", "3", "stat", "--printf", "%f\t%s\t%n\\0", "--", png, webp],
     "one bounded stat of the image files, symlinks not followed")
  eq(Clipboard.imageStatCommand(entries.filter(e => e.type === "text")), null, "no image, no stat")
  eq(Clipboard.imageStatCommand([entries[2], entries[2]]).slice(-1), [png], "a file is asked about once")
  const big = Clipboard.MAX_IMAGE_BYTES
  const statText = ["81a4\t1234\t" + png, "a1ff\t20\t" + webp].join("\u0000") + "\u0000"
  eq(Clipboard.previewablePaths(statText, entries), { [png]: true }, "a regular file passes, a symlink does not")
  eq(Clipboard.previewablePaths("81a4\t" + (big + 1) + "\t" + png + "\u0000", entries), {}, "a file over the cap is not drawn")
  eq(Clipboard.previewablePaths("81a4\t" + big + "\t" + png + "\u0000", entries), { [png]: true }, "a file at the cap is")
  eq(Clipboard.previewablePaths("81a4\t0\t" + png + "\u0000", entries), {}, "an empty file is not drawn")
  eq(Clipboard.previewablePaths("11a4\t10\t" + png + "\u0000" + "21a4\t10\t" + webp + "\u0000", entries), {},
     "a FIFO or a device is never handed to the decoder")
  eq(Clipboard.previewablePaths("81a4\t10\t/etc/passwd\u0000", entries), {}, "a path nobody asked about is ignored")
  eq(Clipboard.previewablePaths("81a4\t10\t" + png, entries), {}, "an unfinished record is ignored")
  eq(Clipboard.previewablePaths("zz\t10\t" + png + "\u0000" + "81a4\t-1\t" + png + "\u0000", entries), {},
     "malformed records are ignored")
  eq(Clipboard.previewablePaths("81a4\t10\t" + png + "\u0000", entries, 5), {}, "the cap can be given")
  eq(Clipboard.previewablePaths(null, entries), {}, "no output, no previews")
  eq(Clipboard.imageSource("/a b/x#1?.png"), "file:///a%20b/x%231%3F.png", "an image URL encodes every segment")
  eq(Clipboard.imageSource("relative.png"), "", "a relative path has no URL")

  eq(rows.map(r => r.imagePath), ["", "", "", "", ""], "no thumbnail before the files are checked")
  const shown = Clipboard.clipboardRows(entries, "", { [png]: true, [dir + "x.png"]: true })
  eq(shown.map(r => r.imagePath), ["", "", png, "", ""], "a checked image row carries its file, every other row \"\"")
  eq(shown.map(r => r.disabled), [false, false, false, false, true], "unverified images stay listed but cannot be acted on")
  assert(shown.every(r => JSON.stringify(Object.keys(r).sort()) === roleSet), "image rows keep the same roles")
  eq(MenuModel.displayRow({}, [], {}, { id: "x", kind: "action", label: "X" }, "", 0, "").imagePath, "",
     "menu rows declare the imagePath role")
  assert("imagePath" in Windows.windowRows([{ address: "0x1", windowClass: "a", title: "t", workspaceId: 1,
    workspaceName: "1", isSpecialWorkspace: false, isFloating: false, focusRecency: 0 }], "", () => null)[0],
    "window rows declare the imagePath role")
  eq((menuSource.match(/imagePath: ""/g) || []).length, 3, "query and dmenu rows declare the imagePath role")
  assert(/rowHeightForDetail\(row\.detail, row\.kind, row\.imagePath\)/.test(menuSource),
         "the fitted list height counts image rows as tall")
  const resultRow = fs.readFileSync(path.join(root, "ResultRow.qml"), "utf8")
  assert(/rowHeightForDetail\(row\.detail, row\.kind, row\.imagePath\)/.test(resultRow), "a row is as tall as the list counts it")
  assert(/asynchronous: true/.test(resultRow) && /cache: false/.test(resultRow) && /Math\.min\(256,/.test(resultRow),
         "thumbnails decode off the UI thread, uncached, capped in size")
  assert(controller.indexOf("Clipboard.imageStatCommand(clip.entries)") >= 0
         && controller.indexOf("Clipboard.previewablePaths(") >= 0, "thumbnails wait for the stat")
}

// ---------------------------------------------------- clipboard filters --
{
  const fs = require("fs")
  const dir = "/home/u/.local/state/omarchy/clipboard-images/"
  const png = dir + "a.png"
  const kindOf = text => Clipboard.parseHistory(JSON.stringify([text]), dir)[0].kind

  eq(Clipboard.FILTERS.map(f => f.label), ["All Types", "Text", "Images", "Files", "Links", "Colors"],
     "filters match omacast's set")
  eq(Clipboard.filterAt(99).id, "all", "an out-of-range filter index is All")
  eq(Clipboard.filterIndex("colors"), 5, "filter ids map to their index")
  eq(Clipboard.filterIndex("constructor"), -1, "unknown filter ids are refused")

  // Files
  eq(kindOf("/etc/hosts"), "file", "an absolute path is a file")
  eq(kindOf("/home/u/a b.txt\n/tmp/x\n"), "file", "several paths, one per line, with a trailing newline")
  eq(kindOf("# comment\r\nfile:///home/u/x.png\r\nfile://localhost/tmp/y"), "file", "a text/uri-list")
  eq(Clipboard.fileCount("/a\n\n/b\nfile:///c"), 3, "paths are counted")
  eq(kindOf("/etc/hosts\nhello"), "text", "mixed lines are text")
  eq(kindOf("// a comment"), "text", "a // comment is not a path")
  eq(kindOf("/* block */"), "text", "a /* comment is not a path")
  eq(kindOf("relative/path"), "text", "a relative path is text")
  eq(kindOf("file://host/share"), "text", "a remote file URI is text")
  eq(kindOf("/a\tb"), "text", "a tab in a path line is text")
  eq(kindOf("/a\u0000b"), "text", "a NUL in a path line is text")
  eq(kindOf("# just a comment"), "text", "comments alone are not a file list")
  eq(Clipboard.fileCount(Array(1001).fill("/a").join("\n")), 0, "too many lines are not scanned as files")
  eq(Clipboard.fileCount("/" + "a".repeat(70000)), 0, "a huge text is not scanned as files")

  // Links
  eq(kindOf("https://example.com/a?b=c#d"), "link", "a whole URL is a link")
  eq(kindOf("  http://example.com  \n"), "link", "surrounding whitespace is trimmed")
  eq(kindOf("example.com/path"), "link", "a bare domain is a link")
  eq(kindOf("see https://example.com"), "text", "a sentence with a URL is text")
  eq(kindOf("https://a.com https://b.com"), "text", "two URLs are text")
  eq(kindOf("javascript:alert(1)"), "text", "other schemes are not links")
  eq(kindOf("ftp://example.com"), "text", "ftp is not a link")
  eq(kindOf("<a href=\"https://x.com\">x</a>"), "text", "markup is text")
  eq(kindOf("https://" + "a".repeat(9000) + ".com"), "text", "an overlong URL is text")
  eq(Clipboard.linkHost("https://user:pw@Example.COM:8080/x"), "example.com:8080", "the host drops credentials")
  eq(Clipboard.linkHost("https://[::1]:80/"), "[::1]:80", "an IPv6 host")
  eq(Clipboard.linkHost("https://exa<b>mple.com/"), "", "a host with markup is dropped")
  eq(Clipboard.wholeLink("example.com"), "https://example.com", "a bare domain gets https")

  // Colors: Qt "#AARRGGBB"
  eq(Clipboard.colorSwatch("#fff"), "#ffffffff", "#rgb")
  eq(Clipboard.colorSwatch("#f008"), "#88ff0000", "#rgba")
  eq(Clipboard.colorSwatch("#1E90FF"), "#ff1e90ff", "#rrggbb")
  eq(Clipboard.colorSwatch("#ff000080"), "#80ff0000", "#rrggbbaa puts alpha first for Qt")
  eq(Clipboard.colorSwatch("rgb(255, 0, 0)"), "#ffff0000", "rgb() with commas")
  eq(Clipboard.colorSwatch("rgba(0, 0, 255, 0.5)"), "#800000ff", "rgba() with alpha")
  eq(Clipboard.colorSwatch("rgb(0 128 255 / 50%)"), "#800080ff", "rgb() space syntax")
  eq(Clipboard.colorSwatch("rgb(100%, 0%, 0%)"), "#ffff0000", "rgb() percentages")
  eq(Clipboard.colorSwatch("rgb(300, -5, 0)"), "#ffff0000", "channels are clamped")
  eq(Clipboard.colorSwatch("hsl(120, 100%, 50%)"), "#ff00ff00", "hsl()")
  eq(Clipboard.colorSwatch("hsla(240deg 100% 50% / 0.25)"), "#400000ff", "hsla() space syntax with deg")
  eq(Clipboard.colorSwatch("hsl(0, 0%, 50%)"), "#ff808080", "grey hsl()")
  for (const bad of ["#ggg", "#12345", "fff", "rgb(1,2)", "rgb(1,2,3,4,5)", "rgb(a,b,c)", "rgb(1,2,3", "red",
                     "rgb(1%,2,3) x", "url(#fff)", "rgb(1 2 3 / 4 / 5)", "hsl(10%, 20%, 30%)", "rgb(,,)",
                     "#fff\n#000", "rgb(" + "1,".repeat(40) + "1)", "rgb(1e3, 0, 0)"]) {
    eq(Clipboard.colorSwatch(bad), "", "not a colour: " + JSON.stringify(bad))
  }
  eq(kindOf(" #ABCDEF "), "color", "a hex colour entry")
  eq(kindOf("color: #fff;"), "text", "CSS around a colour is text")
  assert(Clipboard.isSwatch("#ff00ff00") && !Clipboard.isSwatch("#fff") && !Clipboard.isSwatch("red")
         && !Clipboard.isSwatch("#ff00ff00; x") && !Clipboard.isSwatch(null), "only the swatch shape passes")

  // Text and hostile inputs
  eq(kindOf("hello world"), "text", "plain text")
  eq(kindOf("<b>#fff</b>"), "text", "markup around a colour is text")
  eq(kindOf("x".repeat(200000)), "text", "huge text is text")
  eq(kindOf("‮/etc/passwd"), "text", "a bidi override before a path is text")

  const history = ["hello", "/etc/hosts\n/tmp/x", "https://example.com/a", "#336699",
                   { type: "image", path: png, mime: "image/png", capturedAt: "now" }, "rgb(1,2,3)", "example.com"]
  const entries = Clipboard.parseHistory(JSON.stringify(history), dir)
  const ids = filter => Clipboard.clipboardRows(entries, "", {}, filter).map(r => r.target)
  eq(ids("all"), ["0", "1", "2", "3", "4", "5", "6"], "All Types shows everything")
  eq(ids(undefined), ids("all"), "no filter is All Types")
  eq(ids("bogus"), ids("all"), "an unknown filter is All Types")
  eq(ids("text"), ["0"], "Text leaves out files, links and colours")
  eq(ids("images"), ["4"], "Images")
  eq(ids("files"), ["1"], "Files")
  eq(ids("links"), ["2", "6"], "Links")
  eq(ids("colors"), ["3", "5"], "Colors")
  eq(Clipboard.clipboardRows(entries, "example", {}, "links").map(r => r.target), ["2", "6"], "the query and filter combine")
  eq(Clipboard.clipboardRows(entries, "hosts", {}, "links"), [], "a filtered-out match is hidden")

  const rows = Clipboard.clipboardRows(entries, "", {}, "all")
  eq(rows.map(r => r.detail.split(" · ")[0]), ["1 line", "2 files", "Link", "Color", "Image", "Color", "Link"], "details per kind")
  eq(rows[2].detail, "Link · example.com", "link rows show the host")
  eq(rows.map(r => r.swatch), ["", "", "", "#ff336699", "", "#ff010203", ""], "only colour rows carry a swatch")
  eq(new Set(rows.map(r => r.icon)).size, 5, "each kind has its own icon")
  const roleSet = JSON.stringify(Object.keys(rows[0]).sort())
  assert(rows.every(r => JSON.stringify(Object.keys(r).sort()) === roleSet), "filtered rows keep the same roles")
  eq(Clipboard.emptyFilterText(entries, "all"), "", "All has no filter empty state")
  eq(Clipboard.emptyFilterText(entries, "images"), "", "no empty state when the type is present")
  eq(Clipboard.emptyFilterText(entries.filter(e => e.type !== "image"), "images"), "No images in clipboard history",
     "empty state names the type")
  eq(Clipboard.emptyFilterText([], "text"), "No text in clipboard history", "empty text state")

  // The swatch role reaches every row builder, and the delegate checks it again.
  eq(MenuModel.displayRow({}, [], {}, { id: "x", kind: "action", label: "X" }, "", 0, "").swatch, "",
     "menu rows declare the swatch role")
  assert("swatch" in Windows.windowRows([{ address: "0x1", windowClass: "a", title: "t", workspaceId: 1,
    workspaceName: "1", isSpecialWorkspace: false, isFloating: false, focusRecency: 0 }], "", () => null)[0],
    "window rows declare the swatch role")
  const menuSource = fs.readFileSync(path.join(root, "Menu.qml"), "utf8")
  const resultRow = fs.readFileSync(path.join(root, "ResultRow.qml"), "utf8")
  const controller = fs.readFileSync(path.join(root, "ClipboardController.qml"), "utf8")
  eq((menuSource.match(/swatch: ""/g) || []).length, 3, "query and dmenu rows declare the swatch role")
  assert(/showsSwatch: .*Clipboard\.isSwatch\(row\.swatch\)/.test(resultRow), "the delegate validates the swatch")
  assert(!/Qt\.color\(/.test(resultRow), "no Qt.color on clipboard text")
  assert(/activeTab === "clipboard" && root\.tabsActive && event\.modifiers === Qt\.ControlModifier\s*&& event\.key === Qt\.Key_F/
         .test(menuSource), "Ctrl+F cycles the clipboard filter")
  assert(/clipboardCtl\.filterIndex = 0/.test(menuSource), "the filter resets on open")
  assert(/clipboardCtl\.setFilter\(id\)/.test(menuSource), "a chip picks the filter")
  assert(/Ctrl\+F type/.test(menuSource.match(/activeTab === "clipboard"\)\s*return "[^"]*"/)[0]), "footer mentions Ctrl+F")
  assert(/clipboardRows\(clip\.entries, query, clip\.previewable, clip\.filter\.id\)/.test(controller), "rows use the filter")
  assert(controller.indexOf("Clipboard.activeWindowCommand()") >= 0
         && /clip\.previewable, clip\.pasteMode\)/.test(controller)
         && /Clipboard\.pasteModeFor\(activeWindowOut\.text/.test(controller), "paste follows the window under the launcher")
}

// ------------------------------------------------------- System shortcuts --

{
  const lua = (modmask, key, description) => ({ modmask, key, description, dispatcher: "__lua", submap: "" })
  const lock = lua(68, "L", "Lock system")
  const print = lua(0, "PRINT", "Screenshot")
  const alternatePrint = lua(76, "SUPER + CTRL + ALT + C", "Screenshot")
  const capture = lua(68, "C", "Capture menu")
  const exec = { modmask: 72, key: "F8", dispatcher: "exec", arg: "omarchy-system-lock" }
  const hints = list => SystemShortcuts.parseBindings(JSON.stringify(list))
  const lockHint = bindings => SystemShortcuts.hintFor(bindings, "system.lock", "action", "omarchy-system-lock")
  const screenshotHint = bindings => SystemShortcuts.hintFor(bindings, "trigger.capture.screenshot", "action", "omarchy-capture-screenshot")

  eq(lockHint(hints([lock])), "Super+Ctrl+L", "known active Lua chord")
  eq(lockHint(hints([lock, exec])), "Super+Alt+F8", "an exact exec match beats the stock inference")
  eq(lockHint(hints([lock, { ...lock, dispatcher: "exec", arg: "other" }])), "", "conflicting global chord is not shown")
  eq(lockHint(hints([{ ...lock, submap: "resize" }])), "", "submap-only binding is not a global hint")
  eq(lockHint(hints([{ ...lock, description: "Different action" }])), "", "a reused stock chord needs the matching description")
  eq(lockHint(hints([{ ...lock, key: "F7" }])), "", "an opaque Lua command on a different chord is not guessed")
  eq(lockHint(SystemShortcuts.parseBindings("[invalid")), "", "invalid JSON silently omits hints")
  eq(lockHint(SystemShortcuts.parseBindings(JSON.stringify(Array(2001).fill(lock)))), "", "excessive binding lists are ignored")
  eq(screenshotHint(hints([alternatePrint, print])), "Print", "use the preferred stock chord when both are active")
  eq(screenshotHint(hints([alternatePrint])), "Super+Ctrl+Alt+C", "fall back to the alternate active stock chord")
  eq(SystemShortcuts.hintFor(hints([capture]), "trigger.capture", "menu", ""), "Super+Ctrl+C", "known submenu route")
  eq(SystemShortcuts.hintFor(hints([lock]), "system.lock", "action", "custom-lock"), "", "replaced actions do not inherit hints")
  eq(SystemShortcuts.hintFor(hints([lock]), "constructor", "action", "omarchy-system-lock"), "", "lookups use own stock entries only")
  eq(SystemShortcuts.bindingChord({ modmask: 0, key: "<img>" }), "", "untrusted markup is not a key")
}

// ---------------------------------------------------- percent and work time --

{
  const P = q => { const r = MenuModel.evaluatePercent(q); return r && [r.label, r.copy] }
  eq(P("$30 + 20%"), ["$36", "36"], "add a percent, money symbol kept on the label only")
  eq(P("30 + 20%"), ["36", "36"], "add a percent")
  eq(P("30+20%"), ["36", "36"], "no spaces")
  eq(P("50 - 10%"), ["45", "45"], "subtract a percent")
  eq(P("20% off 50"), ["40", "40"], "percent off")
  eq(P("20 % OFF $50"), ["$40", "40"], "case and spacing, symbol on the base")
  eq(P("20% of 50"), ["10", "10"], "percent of")
  eq(P("15% on 80"), ["92", "92"], "percent on")
  eq(P("50 as a % of 200"), ["25%", "25%"], "as a % of")
  eq(P("50 as % of 200"), ["25%", "25%"], "as % of")
  eq(P("50 is what % of 200"), ["25%", "25%"], "is what % of")
  eq(P("50 is what percent of 200"), ["25%", "25%"], "is what percent of")
  eq(P("/ 20% off 50 ="), ["40", "40"], "command slash and trailing =")
  eq(P("2,5% of 200"), ["5", "5"], "decimal comma")
  eq(P("1,000 + 5%"), null, "ambiguous thousands comma is refused")
  eq(P("5 as a % of 0"), null, "no share of zero")
  eq(P("20% off"), null, "missing base")
  eq(P("20%"), null, "bare percent")
  eq(MenuModel.evaluateMath("50 % 3"), "2", "% between numbers is still modulo")
  eq(MenuModel.evaluateMath("30 + 20%"), "", "the calculator leaves percentages alone")
  eq(MenuModel.evaluatePercent("30 + 20%").detail, "20% of 30 is 6", "percent detail")

  const W = q => { const r = MenuModel.evaluateWorkTime(q); return r && r.label }
  eq(W("40 hours in work days"), "5 work days", "hours to work days")
  eq(W("3 work weeks in hours"), "120 hours", "work weeks to hours")
  eq(W("2.5 work days in hours"), "20 hours", "decimal work days")
  eq(W("2,5 workdays to h"), "20 hours", "comma decimal and short spellings")
  eq(W("120 hours in work weeks"), "3 work weeks", "hours to work weeks")
  eq(W("10 wd in ww"), "2 work weeks", "work days to work weeks")
  eq(W("8 h in work days"), "1 work day", "singular")
  eq(W("40 hours in days"), null, "calendar days are a unit conversion")
  eq(W("40 hours in hours"), null, "no work unit")
  eq(W("2 work days in work days"), null, "same unit")
  eq(MenuModel.evaluateWorkTime("3 work weeks in hours").copy, "120", "copies the number")
  eq(MenuModel.parseUnitQuery("40 hours in work days"), null, "units do not claim work days")
  eq(MenuModel.parseCurrencyQuery("40 hours in work days"), null, "currency does not claim work days")
}

// ------------------------------------------------------------ answer forms --

{
  const F = q => { const f = MenuModel.answerFormFields(q); return f && [f.kind, f.fields.map(x => q.slice(x.start, x.end) + ":" + x.kind)] }
  eq(F("100 eur to usd"), ["currency", ["100:number", "eur:currency", "usd:currency"]], "currency form")
  eq(F("  /  100   EUR   to  usd  = "), ["currency", ["100:number", "EUR:currency", "usd:currency"]], "extra spaces, slash and =")
  eq(F("$120 to eur"), ["currency", ["$:currency", "120:number", "eur:currency"]], "symbol before the amount")
  eq(F("usd 100 to eur"), ["currency", ["usd:currency", "100:number", "eur:currency"]], "code before the amount")
  eq(F("eur to usd"), ["currency", ["eur:currency", "usd:currency"]], "rate only")
  eq(F("100eur→usd"), ["currency", ["100:number", "eur:currency", "usd:currency"]], "glued with an arrow")
  eq(F("5 ft to cm"), ["unit", ["5:number", "ft:unit", "cm:unit"]], "unit form")
  eq(F("2 cup to ml"), ["unit", ["2:number", "cup:unit", "ml:unit"]], "cup is a volume next to ml")
  eq(F("100 cup to eur"), ["currency", ["100:number", "cup:currency", "eur:currency"]], "cup is money next to eur")
  eq(F("20% off 50"), ["percent", ["20:number", "50:number"]], "percent form")
  eq(F("$30 + 20%"), ["percent", ["30:number", "20:number"]], "percent add form")
  eq(F("50 is what % of 200"), ["percent", ["50:number", "200:number"]], "ratio form")
  eq(F("40 hours in work days"), ["worktime", ["40:number", "hours:workunit", "work days:workunit"]], "work time form")
  eq(F("1,5 eur to usd"), null, "comma amount is not a conversion")
  eq(F("100 xyz to usd"), null, "unknown code")
  eq(F("5 kg to km"), null, "mismatched units")
  eq(F("time in tokyo"), null, "time query")
  eq(F("(20+5) eur to usd"), null, "expression amounts answer but are not forms")
  eq(F("2+3"), null, "calculator")
  eq(F(""), null, "empty")

  const text = "/100 eur to usd"
  const form = MenuModel.answerFormFields(text)
  eq(MenuModel.formSegments(text, form.fields),
     [{ text: "/", field: -1 }, { text: "100", field: 0 }, { text: " ", field: -1 }, { text: "eur", field: 1 },
      { text: " to ", field: -1 }, { text: "usd", field: 2 }], "segments cover the line")
  eq(MenuModel.formSegments("ab", [{ start: 1, end: 5 }]), [{ text: "ab", field: -1 }], "out of range spans fall back to plain")
  eq(MenuModel.formSegments("abc", [{ start: 2, end: 3 }, { start: 0, end: 1 }]), [{ text: "abc", field: -1 }], "unordered spans fall back")
  eq(MenuModel.formSegments("", null), [], "empty line")
  eq(MenuModel.formSegments("a  b", [{ start: 0, end: 1 }, { start: 3, end: 3 }, { start: 3, end: 4 }]),
     [{ text: "a", field: 0 }, { text: "  ", field: -1 }, { text: "", field: 1 }, { text: "b", field: 2 }], "empty field keeps its piece")

  // Editing: splice the focused field, shift the rest.
  let e = MenuModel.editFormField(text, form.fields, 0, "250")
  eq([e.text, e.kind, e.parsed], ["/250 eur to usd", "currency", true], "replace the amount")
  e = MenuModel.editFormField(text, form.fields, 0, "")
  eq([e.text, e.parsed, e.fields.map(f => [f.start, f.end])], ["/ eur to usd", false, [[1, 1], [2, 5], [9, 12]]],
     "an emptied amount keeps shifted spans")
  e = MenuModel.editFormField(e.text, e.fields, 0, "7")
  eq([e.text, e.parsed, e.fields.length], ["/7 eur to usd", true, 3], "typing into the empty field re-derives the form")
  e = MenuModel.editFormField(text, form.fields, 2, "gbp")
  eq([e.text, e.parsed], ["/100 eur to gbp", true], "edit the last field (cursor at the end)")
  e = MenuModel.editFormField(text, form.fields, 2, "")
  eq([e.text, e.fields[2]], ["/100 eur to ", { start: 12, end: 12, kind: "currency" }], "empty last field at the line end")
  e = MenuModel.editFormField(text, form.fields, 1, "xyz")
  eq([e.text, e.parsed, e.fields[2].start], ["/100 xyz to usd", false, 12], "unknown code keeps the form editable")
  e = MenuModel.editFormField(text, form.fields, 0, "1.5")
  eq([e.text, e.parsed], ["/1.5 eur to usd", true], "decimal point")
  e = MenuModel.editFormField(text, form.fields, 0, "1,5")
  eq([e.text, e.parsed], ["/1,5 eur to usd", false], "decimal comma edits but is not a conversion")
  e = MenuModel.editFormField("100 cup to eur", MenuModel.answerFormFields("100 cup to eur").fields, 2, "ml")
  eq([e.text, e.kind, e.fields[1].kind], ["100 cup to ml", "unit", "unit"], "a field that turns into a unit takes the unit kind")
  const pf = MenuModel.answerFormFields("20% off 50")
  e = MenuModel.editFormField("20% off 50", pf.fields, 1, "80")
  eq([e.text, MenuModel.evaluatePercent(e.text).label], ["20% off 80", "64"], "percent base edit")
  e = MenuModel.editFormField("20% off 50", pf.fields, 0, "")
  eq([e.text, e.fields[1]], ["% off 50", { start: 6, end: 8, kind: "number" }], "emptied percent shifts the base")
  eq(MenuModel.editFormField("abc", [{ start: 0, end: 9 }], 0, "x"), null, "bad spans are refused")
  eq(MenuModel.editFormField(text, form.fields, 5, "x"), null, "bad index is refused")

  // Up/Down stepping.
  const C = MenuModel.cycleFormValue
  eq(C("number", "100", 1), "101", "number up")
  eq(C("number", "1,5", -1), "0,5", "number down keeps the comma")
  eq(C("number", "", 1), "", "empty number does not step")
  eq(C("currency", "eur", 1), "USD", "currency up")
  eq(C("currency", "EUR", -1), "AUD", "currency wraps")
  eq(C("currency", "xyz", 1), "EUR", "unknown code starts the list")
  eq(C("currency", "$", 1), "GBP", "symbol is read as its code")
  eq(C("unit", "ft", 1), "yd", "unit steps within length")
  eq(C("unit", "mm", -1), "nmi", "unit wraps within length")
  eq(C("unit", "f", 1), "k", "temperature by name")
  eq(C("unit", "bogus", 1), "", "unknown unit")
  eq(C("workunit", "hours", 1), "work days", "work unit up")
  eq(C("workunit", "ww", 1), "hours", "work unit wraps")
  eq(C("other", "x", 1), "", "unknown kind")
}

// ------------------------------------------------ percent with a code --
{
  const M = MenuModel
  eq(M.evaluatePercent("100 eur - 10%").label, "90 EUR", "a currency code after the amount")
  eq(M.evaluatePercent("100eur+5%").copy, "105", "a code with no spaces; copy is the number")
  eq(M.evaluatePercent("20% off 100 eur").label, "80 EUR", "off with a code")
  eq(M.evaluatePercent("15% on 80 czk").detail, "Adds 12 CZK", "on with a code")
  eq(M.evaluatePercent("100 apples - 10%"), null, "a word that is no currency is not a percentage")
  eq(M.evaluatePercent("€100 eur - 10%"), null, "a symbol and a code together are refused")
  const q = "100 eur - 10%"
  eq(M.answerFormFields(q).fields.map(f => f.kind + ":" + q.slice(f.start, f.end)),
     ["number:100", "currency:eur", "number:10"], "the code is a currency field of the form")
  const to = M.evaluatePercent("100 eur - 10% to usd")
  eq([to.value, to.from, to.to], [90, "EUR", "USD"], "a percentage sum with a target currency")
  eq(M.evaluatePercent("€100 - 10% in usd").from, "EUR", "a symbol is a source currency")
  eq(M.evaluatePercent("100 - 10% to usd"), null, "a target needs a source currency")
  eq(M.evaluatePercent("100 eur - 10% to xyz"), null, "an unknown target is refused")
  eq(M.evaluatePercent("100 eur - 10%").to, "", "no target, nothing to convert")
  const tq = "20% off 100 eur to usd"
  eq(M.answerFormFields(tq).fields.map(f => f.kind + ":" + tq.slice(f.start, f.end)),
     ["number:20", "number:100", "currency:eur", "currency:usd"], "both currencies are form fields")
  const engine = require("fs").readFileSync(path.join(root, "AnswerEngine.qml"), "utf8")
  assert(/if \(result\.to\) return answers\.percentCurrencyRow\(result\)/.test(engine), "a target converts through the rates")
  const src = require("fs").readFileSync(path.join(root, "Menu.qml"), "utf8")
  assert(/if \(!root\.commandMode \|\| \(event\.modifiers & Qt\.ControlModifier\)\)\s*root\.setTab/.test(src),
         "plain Tab does not switch tabs under a / command")
}

console.log("")
console.log(pass + " passed, " + fail + " failed")
if (fail > 0) process.exit(1)
