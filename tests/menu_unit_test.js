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
const FileSearch = require(path.join(root, "FileSearch.js"))
const MenuModel = require(path.join(root, "MenuModel.js"))

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

eq(Tabs.TABS.map(t => t.id), ["all", "apps", "system", "files", "folders"], "default tab order")
eq(Tabs.DEFAULT_ALL_SECTIONS, ["apps", "system", "files", "folders"], "default All section order matches the tabs")
eq(Tabs.orderTabs(["files", "all"]).map(t => t.id), ["files", "all", "apps", "system", "folders"],
   "a partial tab order reorders and appends the rest")
eq(Tabs.orderTabs(["bogus", "apps", "apps", 7]).map(t => t.id), ["apps", "all", "system", "files", "folders"],
   "unknown and repeated ids are dropped")
eq(Tabs.orderTabs("not an array").map(t => t.id), Tabs.DEFAULT_TAB_ORDER, "a malformed order falls back to the default")
eq(Tabs.orderSections(["folders", "apps"]).map(s => s.id), ["folders", "apps", "system", "files"], "All sections reorder")
eq(Tabs.cycleTab("all", 1, Tabs.orderTabs(["all", "folders"])), "folders", "Tab follows the order on screen")
eq(Tabs.tabForRoute("root"), { tab: "all", menu: "root" }, "SUPER+SPACE opens All")
eq(Tabs.tabForRoute(""), { tab: "all", menu: "root" }, "an empty route opens All")
eq(Tabs.tabForRoute("apps"), { tab: "apps", menu: "root" }, "SUPER+ALT+SPACE opens Apps")
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
eq(Tabs.visibleTabs(null, ["files", "folders"], "all").map(t => t.id), ["all", "apps", "system"], "disabled tabs leave the bar")
eq(Tabs.visibleTabs(null, ["system"], "system").map(t => t.id), Tabs.DEFAULT_TAB_ORDER,
   "a disabled tab opened by route stays visible while active")
eq(Tabs.firstEnabledTab(null, ["all"]), "apps", "with All off, the first tab that is on opens")
eq(Tabs.firstEnabledTab(["system", "all"], ["all"]), "system", "first enabled follows the user's order")

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

const parsed = FileSearch.parseLines(home + "/Docs/\n" + home + "/.config/hypr/\nrelative\n\n", true, home)
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

eq(FileSearch.parseStatLines("1700000000\t/x\ngarbage\n0\t/y\n5\trelative\n"), { "/x": 1700000000000 }, "parseStatLines keeps valid lines only")
eq(FileSearch.formatMtime(new Date(2026, 8, 23, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "Today 09:05", "today")
eq(FileSearch.formatMtime(new Date(2026, 8, 22, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "Yesterday 09:05", "yesterday")
eq(FileSearch.formatMtime(new Date(2025, 0, 2, 9, 5).getTime(), new Date(2026, 8, 23, 18, 0).getTime()), "02/01/25 09:05", "older years")
eq(FileSearch.nextSortMode("name_desc"), "relevance", "sort modes wrap")
eq(FileSearch.nextDisplayLimit(200), 15, "display limits wrap")

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

// --------------------------------------------------------- untrusted text --

const rlo = String.fromCharCode(0x202e)
const row = MenuModel.sanitizeRow({ label: "evil" + rlo + "txt.exe", detail: "a\nb", trailText: "x" })
assert(row.label.indexOf(rlo) === -1, "bidi overrides are stripped from labels")
assert(row.detail.indexOf("\n") === -1, "line breaks are stripped from details")
eq(MenuModel.displayRow({}, [], {}, { id: "x", kind: "action", label: "X" }, "", 0, "").trailText, "",
   "menu rows declare the trailText role")

console.log("")
console.log(pass + " passed, " + fail + " failed")
if (fail > 0) process.exit(1)
