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

console.log("")
console.log(pass + " passed, " + fail + " failed")
if (fail > 0) process.exit(1)
