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
const Settings = require(path.join(root, "Settings.js"))
const Roots = require(path.join(root, "Roots.js"))
const Windows = require(path.join(root, "Windows.js"))

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

eq(Tabs.TABS.map(t => t.id), ["all", "apps", "windows", "system", "files", "folders"], "default tab order")
eq(Tabs.DEFAULT_ALL_SECTIONS, ["apps", "windows", "system", "files", "folders"], "default All section order matches the tabs")
eq(Tabs.orderTabs(["files", "all"]).map(t => t.id), ["files", "all", "apps", "windows", "system", "folders"],
   "a partial tab order reorders and appends the rest")
eq(Tabs.orderTabs(["bogus", "apps", "apps", 7]).map(t => t.id), ["apps", "all", "windows", "system", "files", "folders"],
   "unknown and repeated ids are dropped")
eq(Tabs.orderTabs("not an array").map(t => t.id), Tabs.DEFAULT_TAB_ORDER, "a malformed order falls back to the default")
eq(Tabs.orderSections(["folders", "apps"]).map(s => s.id), ["folders", "apps", "windows", "system", "files"], "All sections reorder")
eq(Tabs.cycleTab("all", 1, Tabs.orderTabs(["all", "folders"])), "folders", "Tab follows the order on screen")
eq(Tabs.tabForRoute("root"), { tab: "all", menu: "root" }, "SUPER+SPACE opens All")
eq(Tabs.tabForRoute(""), { tab: "all", menu: "root" }, "an empty route opens All")
eq(Tabs.tabForRoute("apps"), { tab: "apps", menu: "root" }, "SUPER+ALT+SPACE opens Apps")
eq(Tabs.tabForRoute("windows"), { tab: "windows", menu: "root" }, "the windows route opens Windows")
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
eq(Tabs.visibleTabs(null, ["windows", "files", "folders"], "all").map(t => t.id), ["all", "apps", "system"], "disabled tabs leave the bar")
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
const write = Settings.writeCommand("/d", "/d/f.json", "$(boom)", false)
eq(write.slice(-3), ["/d", "/d/f.json", "$(boom)"], "written content reaches bash as an argument")
assert(write[2].indexOf("boom") === -1, "written content never enters the script text")
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
  eq(names, ["toggle", "toggle-apps"], "the menu's global shortcut names")
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
}

console.log("")
console.log(pass + " passed, " + fail + " failed")
if (fail > 0) process.exit(1)
