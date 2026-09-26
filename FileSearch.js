// File and folder search for the Files and Folders tabs (and their sections in
// All): builds the `fd` argument vectors, parses what comes back, and ranks it.
//
// Adapted from FindBackend.js in omarchy-find by Jessé Burlamaque
// (https://github.com/jesseburlamaque/omarchy-find), MIT licensed. Changes
// from the original: the filters are split between the two tabs they now
// belong to, the Portuguese strings and AI/Google modes are gone, and the
// module loads under node as well as QML so it can be tested.

var MAX_RESULTS = 500

// Directories that are never worth a result: VCS internals, package caches,
// virtualenvs, trash.
var EXCLUDES = [
  ".git",
  "node_modules",
  ".cache",
  "__pycache__",
  ".npm",
  ".nvm",
  ".cargo",
  ".rustup",
  ".gradle",
  ".local/share/Trash",
  ".local/share/flatpak",
  ".venv",
  "venv",
  // Wine and Proton prefixes map drive letters onto symlinks (`z:` is `/`),
  // and with --follow one Steam compatdata prefix is a walk of the whole disk:
  // a second per keystroke, and results full of other people's /etc.
  "dosdevices",
  // Game installs and the Steam runtime: gigabytes of files nobody searches
  // for by name, and the rest of the compatdata prefixes.
  ".local/share/Steam",
  ".steam"
]

// Extra noise under ~/.config and ~/.local/share that the System folders
// filter walks: caches and runtime state, excluded outright.
var SYSTEM_EXCLUDES = [
  "*Cache*",
  "Local Storage",
  "Session Storage",
  "Service Worker",
  "blob_storage",
  "Dawn*",
  "logs",
  "*Storage*",
  "History",
  "data",
  "Crashpad",
  "Dictionaries",
  "Partitions",
  "Shared Dictionary",
  "Backups",
  ".*.bak.*"
]

// Application folders whose *insides* are noise -- a browser profile is
// hundreds of directories -- but which are themselves exactly what a search
// for "chromium" or "mozilla" is after. Upstream excluded them whole, so
// ~/.config/chromium could be found from All but never from System folders.
// `**/name/*` keeps the folder and drops everything under it.
var SYSTEM_CONTENT_EXCLUDES = [
  "google-chrome*",
  "microsoft-edge*",
  "chromium",
  "BraveSoftware",
  "mozilla",
  "dconf",
  "ibus",
  "fcitx",
  "pulse",
  "procps"
]

var DOCS_EXTS = [
  "pdf", "epub", "mobi", "azw", "azw3", "djvu", "cbr", "cbz", "fb2",
  "doc", "docx", "docm", "dot", "dotx", "odt", "ott", "rtf", "txt", "text", "wps", "pages", "gdlink", "gdoc",
  "xls", "xlsx", "xlsm", "xltx", "ods", "ots", "csv", "tsv", "numbers", "gsheet", "parquet", "feather", "tab",
  "ppt", "pptx", "pptm", "potx", "odp", "otp", "key", "keynote", "gslides",
  "md", "markdown", "mdown", "org", "rst", "adoc", "asciidoc", "tex", "latex", "typst", "typ", "bib", "nfo", "log"
]

var IMAGES_EXTS = [
  "jpg", "jpeg", "png", "gif", "webp", "svg", "svgz", "bmp", "ico", "cur", "tif", "tiff", "heic", "heif", "avif", "jxl",
  "raw", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2", "dng", "orf", "rw2", "pef", "raf", "kdc",
  "psd", "psb", "ai", "eps", "kra", "xcf", "clip", "ase", "aseprite", "fig", "sketch", "tga", "dds", "hdr", "exr", "icns"
]

var VIDEOS_EXTS = [
  "mp4", "mkv", "webm", "avi", "mov", "m4v", "mpg", "mpeg", "wmv", "flv", "ts", "m2ts", "mts",
  "3gp", "3g2", "ogv", "vob", "divx", "rm", "rmvb", "f4v", "asf"
]

var AUDIO_EXTS = [
  "mp3", "flac", "ogg", "oga", "opus", "wav", "wave", "m4a", "aac", "wma", "aiff", "aif", "alac",
  "mid", "midi", "ape", "ac3", "dts", "mp2", "mka", "ra", "voc", "amr"
]

var CODE_EXTS = [
  "c", "h", "cpp", "cxx", "cc", "hpp", "hh", "hxx", "rs", "go", "zig", "d", "nim", "v", "odin", "f", "f90", "for", "asm", "s",
  "java", "kt", "kts", "scala", "groovy", "gradle", "swift", "m", "mm", "dart", "cs", "fs", "fsx",
  "py", "pyw", "pyx", "ipynb", "rb", "erb", "rake", "php", "phtml", "pl", "pm", "t", "lua", "r", "jl", "sh", "bash", "zsh", "fish", "ksh", "bat", "cmd", "ps1",
  "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx", "html", "htm", "xhtml", "css", "scss", "sass", "less", "styl", "vue", "svelte", "astro", "qml",
  "hs", "lhs", "ml", "mli", "ex", "exs", "erl", "hrl", "clj", "cljs", "cljc", "edn", "lisp", "lsp", "scm", "ss", "rkt", "elm", "purs",
  "json", "jsonc", "json5", "yaml", "yml", "toml", "xml", "ini", "cfg", "conf", "cnf", "env", "sql", "sqlite", "graphql", "gql", "proto", "prisma",
  "dockerfile", "containerfile", "justfile", "makefile", "mk", "cmake", "nix", "tf", "hcl",
  "gd", "tscn", "tres", "glsl", "vert", "frag", "geom", "comp", "hlsl", "shader", "wgsl"
]

var ARCHIVE_EXTS = [
  "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "zst", "7z", "rar", "iso", "deb", "rpm", "pkg", "appimage", "apk"
]

var MODEL3D_EXTS = [
  "blend", "obj", "fbx", "stl", "step", "stp", "iges", "igs", "gltf", "glb", "3ds", "dae", "dwg", "dxf", "kicad_pcb", "kicad_sch"
]

// The type filters each tab cycles through with Ctrl+F. The first of each is
// the default, and the one All uses for its Files and Folders sections.
var FILE_FILTERS = [
  { id: "files", label: "All files", exts: [], hidden: true },
  { id: "docs", label: "Documents", exts: DOCS_EXTS, hidden: false },
  { id: "images", label: "Images", exts: IMAGES_EXTS, hidden: false },
  { id: "videos", label: "Videos", exts: VIDEOS_EXTS, hidden: false },
  { id: "audio", label: "Audio", exts: AUDIO_EXTS, hidden: false },
  { id: "code", label: "Code", exts: CODE_EXTS, hidden: false },
  // Only the search roots (Roots.js): a share or drive the user added.
  { id: "remotes", label: "Remotes", exts: [], hidden: true, remotesOnly: true }
]

var FOLDER_FILTERS = [
  { id: "folders", label: "Folders", exts: [], hidden: false },
  { id: "systemFolders", label: "System folders", exts: [], hidden: true, systemFolders: true },
  { id: "remoteFolders", label: "Remotes", exts: [], hidden: true, remotesOnly: true }
]

// Each tab's filters; the Remotes one only while there is a root to search.
// It is last in both lists, so the other filters keep their positions.
function filtersFor(kind, hasRoots) {
  var list = kind === "folders" ? FOLDER_FILTERS : FILE_FILTERS
  if (hasRoots) return list
  var out = []
  for (var i = 0; i < list.length; i++) if (!list[i].remotesOnly) out.push(list[i])
  return out
}

// What All searches with: hidden paths included, because the folder most
// often wanted by name is a config one (`hypr`, `nvim`), and those all live
// under a dot-directory. Ranking still puts the user's own files first.
var ALL_FILTER = { id: "all", label: "All", exts: [], hidden: true }

function filterAt(kind, index, hasRoots) {
  var list = filtersFor(kind, hasRoots)
  return list[index] || list[0]
}

var SORT_MODES = [
  { id: "relevance", label: "Relevance", icon: "󰓥" },
  { id: "mtime_desc", label: "Most recent", icon: "󰔚" },
  { id: "mtime_asc", label: "Oldest", icon: "󰔛" },
  { id: "name_asc", label: "Name (A → Z)", icon: "󰚔" },
  { id: "name_desc", label: "Name (Z → A)", icon: "󰚕" }
]

var DISPLAY_LIMITS = [15, 30, 60, 100, 200]

function sortMode(id) {
  for (var i = 0; i < SORT_MODES.length; i++) if (SORT_MODES[i].id === id) return SORT_MODES[i]
  return SORT_MODES[0]
}

function nextSortMode(id) {
  for (var i = 0; i < SORT_MODES.length; i++)
    if (SORT_MODES[i].id === id) return SORT_MODES[(i + 1) % SORT_MODES.length].id
  return SORT_MODES[0].id
}

function nextDisplayLimit(limit) {
  var index = DISPLAY_LIMITS.indexOf(limit)
  return DISPLAY_LIMITS[(index + 1) % DISPLAY_LIMITS.length]
}

function stripAccents(str) {
  return String(str || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
}

var ACCENT_MAP = {
  "a": "[aáàãâä]",
  "e": "[eéèêë]",
  "i": "[iíìîï]",
  "o": "[oóòõôö]",
  "u": "[uúùûü]",
  "c": "[cç]"
}

// A search term as an fd regex: accent-insensitive for the common vowels, and
// every regex metacharacter escaped so a typed `.` or `(` is literal.
function accentRegex(term) {
  var s = ""
  for (var i = 0; i < term.length; i++) {
    var ch = term.charAt(i).toLowerCase()
    var base = stripAccents(ch)
    if (ACCENT_MAP[base]) {
      s += ACCENT_MAP[base]
    } else {
      var special = "\\^$.[]|()?*+{}"
      if (special.indexOf(ch) !== -1) s += "\\" + ch
      else s += ch
    }
  }
  return s
}

function extractTerms(query) {
  var rawTerms = String(query || "").trim().split(/\s+/)
  var terms = []
  var seen = {}
  for (var i = 0; i < rawTerms.length; i++) {
    var term = rawTerms[i]
    if (!term) continue
    var lower = term.toLowerCase()
    if (!seen[lower]) {
      seen[lower] = true
      terms.push(accentRegex(term))
    }
  }
  return terms
}

// The fd argument vector for one search of $HOME. Every term has to match
// somewhere in the full path (`--and` for the rest); an empty query matches
// everything and ranking decides what shows. Passed to Process as an array:
// no shell ever sees the query. `excludes` are extra fd -E patterns (the
// search roots inside $HOME, which are searched under their own label).
function buildArgv(query, filter, forDirs, home, excludes) {
  var paths = filter.systemFolders ? [home + "/.config", home + "/.local/share"] : [home]
  return fdArgv(query, filter, forDirs ? ["d"] : ["f"], true, excludes || [], paths)
}

// fd over search roots (Roots.js) that are searched live. No --follow: a
// share's symlinks may point anywhere, loops included. Directories come back
// with a trailing slash, which tells them apart when both kinds are asked for.
function buildRootArgv(query, filter, wantDirs, wantFiles, paths) {
  var types = []
  if (wantDirs) types.push("d")
  if (wantFiles) types.push("f")
  return fdArgv(query, filter, types, false, [], paths)
}

function fdArgv(query, filter, types, follow, extraExcludes, paths) {
  // --print0: a file name may contain a newline; NUL cannot occur in one, so
  // each path arrives whole and no name can pose as another path.
  var argv = ["fd", "--color=never", "--print0", "-i", "--no-ignore"]
  if (follow) argv.push("--follow")
  argv.push("--max-results", String(MAX_RESULTS))
  for (var y = 0; y < types.length; y++) argv.push("--type", types[y])

  if (filter.hidden === true) argv.push("--hidden")

  for (var i = 0; i < EXCLUDES.length; i++) argv.push("-E", EXCLUDES[i])
  for (var x = 0; x < extraExcludes.length; x++) argv.push("-E", extraExcludes[x])

  if (filter.systemFolders) {
    argv.push("--max-depth", "3")
    for (var s = 0; s < SYSTEM_EXCLUDES.length; s++) argv.push("-E", SYSTEM_EXCLUDES[s])
    for (var c = 0; c < SYSTEM_CONTENT_EXCLUDES.length; c++) argv.push("-E", "**/" + SYSTEM_CONTENT_EXCLUDES[c] + "/*")
  }

  if (types.indexOf("d") < 0) {
    for (var e = 0; e < filter.exts.length; e++) argv.push("-e", filter.exts[e])
  }

  var terms = extractTerms(query)
  for (var t = 1; t < terms.length; t++) argv.push("--and", terms[t])

  argv.push("--full-path")
  argv.push("--")
  argv.push(terms.length === 0 ? "." : terms[0])
  for (var p = 0; p < paths.length; p++) argv.push(paths[p])

  return argv
}

function basename(path) {
  var idx = path.lastIndexOf("/")
  return idx === -1 ? path : path.slice(idx + 1)
}

// Parses `stat -c '%Y\t%n'` output into { path: mtimeMs }.
// `stat --printf '%Y\t%n\0'` output: NUL-terminated, like fd's.
function parseStatLines(text) {
  var map = {}
  var lines = String(text || "").split("\0")
  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab <= 0) continue
    var sec = Number(lines[i].slice(0, tab))
    var path = lines[i].slice(tab + 1)
    if (!isFinite(sec) || sec <= 0 || path.charAt(0) !== "/") continue
    map[path] = sec * 1000
  }
  return map
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// "Today 14:05", "Yesterday 09:12", "03/08 11:00", or "03/08/25 11:00".
function formatMtime(msec, nowMs) {
  var d = new Date(msec)
  var now = new Date(nowMs === undefined ? Date.now() : nowMs)
  var hm = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate())
    return "Today " + hm
  var yest = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  if (d.getFullYear() === yest.getFullYear() && d.getMonth() === yest.getMonth() && d.getDate() === yest.getDate())
    return "Yesterday " + hm
  var dm = pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1)
  if (d.getFullYear() === now.getFullYear()) return dm + " " + hm
  return dm + "/" + String(d.getFullYear()).slice(2) + " " + hm
}

function parentDir(path, home) {
  var idx = path.lastIndexOf("/")
  var dir = idx <= 0 ? "/" : path.slice(0, idx)
  if (home && dir.indexOf(home) === 0) dir = "~" + dir.slice(home.length)
  return dir
}

function extension(name) {
  var idx = name.lastIndexOf(".")
  if (idx <= 0 || idx === name.length - 1) return ""
  return name.slice(idx + 1).toLowerCase()
}

function contains(list, value) {
  return list.indexOf(value) !== -1
}

function iconFor(name, isDir) {
  if (isDir) return "󰉋"
  var ext = extension(name)
  if (contains(IMAGES_EXTS, ext)) return "󰋩"
  if (contains(VIDEOS_EXTS, ext)) return "󰕧"
  if (contains(AUDIO_EXTS, ext)) return "󰎈"
  if (contains(CODE_EXTS, ext)) return "󰅩"
  if (contains(DOCS_EXTS, ext)) return "󰈙"
  if (contains(ARCHIVE_EXTS, ext)) return "󰛫"
  if (contains(MODEL3D_EXTS, ext)) return "󰆧"
  return "󰈔"
}

// Outside $HOME, or anywhere under a dot-directory: ranked after the user's
// own files.
function isSystemPath(path, home) {
  var p = String(path || "")
  if (!home || p.indexOf(home) !== 0) return true
  var rel = p.slice(home.length)
  if (rel.charAt(0) === "/") rel = rel.slice(1)
  var parts = rel.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].charAt(0) === ".") return true
  }
  return false
}

// fd's (or the index search's) NUL-separated output as items. isDir null
// reads the kind from the trailing slash fd gives directories. With `roots`,
// an item inside one carries its label and is shown relative to it; its
// place in the ranking is judged inside the root, as $HOME's files are.
function parseLines(text, isDir, home, roots) {
  var out = []
  var lines = String(text || "").split("\0")
  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i]
    var dirMark = /\/$/.test(raw)
    // fd marks directories with a trailing slash.
    var path = raw.replace(/\/+$/, "")
    if (!path || path.charAt(0) !== "/") continue
    var name = basename(path)
    if (!name) continue
    var kind = isDir === null || isDir === undefined ? dirMark : isDir
    var root = roots ? rootOf(path, roots) : null
    out.push({
      path: path,
      name: name,
      dir: root ? rootDir(path, root) : parentDir(path, home),
      isDir: kind,
      isSystem: root ? isSystemPath(path, root.path) : isSystemPath(path, home),
      icon: iconFor(name, kind),
      rootId: root ? root.id : "",
      rootLabel: root ? root.label : ""
    })
  }
  return out
}

function rootOf(path, roots) {
  var best = null
  for (var i = 0; i < roots.length; i++) {
    var r = roots[i].path
    if (path.indexOf(r + "/") === 0 && (!best || r.length > best.path.length)) best = roots[i]
  }
  return best
}

// "NAS › Photos/2024" for a path inside root NAS.
function rootDir(path, root) {
  var rel = path.slice(root.path.length + 1)
  var idx = rel.lastIndexOf("/")
  return idx <= 0 ? root.label : root.label + " › " + rel.slice(0, idx)
}

// `zoxide query --list --score` output as { path: score }.
function parseZoxide(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*([0-9]+(?:\.[0-9]+)?)\s+(\/.*)$/.exec(lines[i])
    if (!m) continue
    var path = m[2].replace(/\/+$/, "")
    if (path && !(path in map)) map[path] = Number(m[1])
  }
  return map
}

// Folders zoxide knows that match every term of the query, as items: the
// places the user actually goes, found even where fd did not look.
function zoxideItems(frecency, query, home, roots, limit) {
  var q = String(query || "").trim()
  if (!q || !frecency) return []
  var out = []
  for (var path in frecency) {
    var name = basename(path)
    if (!name) continue
    var root = roots ? rootOf(path, roots) : null
    var item = {
      path: path, name: name,
      dir: root ? rootDir(path, root) : parentDir(path, home),
      isDir: true, isSystem: false, icon: iconFor(name, true),
      rootId: root ? root.id : "", rootLabel: root ? root.label : ""
    }
    if (scoreItem(item, q) < 0) continue
    out.push(item)
    if (out.length >= (limit || 200)) break
  }
  return out
}

// How much a zoxide score lifts an item: a folder by its own frecency, a
// file by a third of its folder's. At most 1.5, against term scores of 0 to 5
// per term, so a frequent folder wins between near matches but never beats a
// name that matches while its own does not.
function frecencyBonus(item, frecency) {
  if (!frecency) return 0
  var own = frecency[item.path]
  if (item.isDir && own > 0) return Math.min(1.5, Math.log(1 + own) / Math.LN10 * 0.75)
  if (!item.isDir) {
    var slash = item.path.lastIndexOf("/")
    var parent = slash > 0 ? frecency[item.path.slice(0, slash)] : 0
    if (parent > 0) return Math.min(0.5, Math.log(1 + parent) / Math.LN10 * 0.25)
  }
  return 0
}

// Scores one term against a file name: lower is better, -1 is no match.
function scoreTerm(name, term) {
  if (name === term) return 0
  if (name.indexOf(term) === 0) return 1
  var idx = name.indexOf(term)
  if (idx > 0) {
    var prev = name.charAt(idx - 1)
    if (prev === " " || prev === "-" || prev === "_" || prev === "." || prev === "/") return 2
    return 3
  }
  return -1
}

// Every term has to match, in the name or failing that in the path.
function scoreItem(item, query) {
  var name = stripAccents(item.name.toLowerCase())
  var path = stripAccents(item.path.toLowerCase())
  var rawTerms = stripAccents(query.trim().toLowerCase()).split(/\s+/)
  var total = 0
  for (var i = 0; i < rawTerms.length; i++) {
    var term = rawTerms[i]
    if (!term) continue
    var s = scoreTerm(name, term)
    if (s < 0) {
      if (path.indexOf("/" + term) !== -1 || path.indexOf("/." + term) !== -1 || path.indexOf(" " + term) !== -1
          || path.indexOf("_" + term) !== -1 || path.indexOf("-" + term) !== -1) s = 4
      else if (path.indexOf(term) !== -1) s = 5
      else return -1
    }
    total += s
  }
  return total
}

function systemFlag(item, home) {
  return item.isSystem !== undefined ? item.isSystem : isSystemPath(item.path, home)
}

function byName(a, b) {
  return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
}

// Orders candidates and keeps the first `limit`. User files always come before
// system (dotted) ones; within that the sort mode decides. With no query,
// relevance means shallow and folders-first, the way a file manager opens.
// A folder zoxide knows is the user's own, dotted or not: ~/.config/hypr,
// visited daily, is not ranked as system noise. `frecency` (optional) is
// parseZoxide's map.
function rankResults(items, query, limit, home, mode, frecency) {
  var sort = mode || "relevance"
  var q = String(query || "").trim().toLowerCase()
  var entries = []
  var seen = {}

  for (var i = 0; i < items.length; i++) {
    // The same path from two sources (fd and zoxide, $HOME and a root).
    if (seen[items[i].path]) continue
    var score = q ? scoreItem(items[i], q) : 0
    if (score < 0) continue
    seen[items[i].path] = true
    var bonus = frecencyBonus(items[i], frecency)
    entries.push({ item: items[i], score: score - bonus, bonus: bonus,
                   isSystem: systemFlag(items[i], home) && !(items[i].isDir && bonus > 0) })
  }

  entries.sort(function(a, b) {
    if (sort === "relevance" && q && a.score !== b.score) return a.score - b.score
    if (a.isSystem !== b.isSystem) return a.isSystem ? 1 : -1
    // No query: the folders the user goes to most come first.
    if (sort === "relevance" && !q && a.bonus !== b.bonus) return b.bonus - a.bonus

    if (sort === "name_asc") return byName(a.item, b.item)
    if (sort === "name_desc") return byName(b.item, a.item)
    if (sort === "mtime_asc") return (a.item.mtimeMs || 0) - (b.item.mtimeMs || 0)
    if (sort === "mtime_desc") {
      if ((b.item.mtimeMs || 0) !== (a.item.mtimeMs || 0)) return (b.item.mtimeMs || 0) - (a.item.mtimeMs || 0)
      return a.score - b.score
    }

    if (a.item.isDir !== b.item.isDir) return a.item.isDir ? -1 : 1
    if (!q) {
      var aDepth = a.item.path.split("/").length
      var bDepth = b.item.path.split("/").length
      if (aDepth !== bDepth) return aDepth - bDepth
      return byName(a.item, b.item)
    }
    if (a.item.name.length !== b.item.name.length) return a.item.name.length - b.item.name.length
    return a.item.path < b.item.path ? -1 : (a.item.path > b.item.path ? 1 : 0)
  })

  var out = []
  for (var j = 0; j < entries.length && j < limit; j++) out.push(entries[j].item)
  return out
}

// Files that Enter would not so much open as run or install: the default
// handler for these executes them (a .desktop entry, an AppImage, a script)
// or installs them. Enter opens their folder instead; the menu also treats
// any file with the executable bit this way (checked when it is opened).
var LAUNCHABLE_EXTS = [
  "desktop", "appimage", "run", "bin", "sh", "bash", "zsh", "fish", "csh", "ksh",
  "py", "pl", "rb", "jar", "command", "exe", "msi", "bat", "cmd", "com",
  "ps1", "vbs", "lnk", "flatpak", "flatpakref", "flatpakrepo", "deb", "rpm", "apk", "snap"
]

// bash -c script for Enter on a file: $1 the file, $2 its folder. A file
// with the executable bit opens its folder, anything else opens itself.
var OPEN_FILE_SCRIPT = 'if [ -f "$1" ] && [ -x "$1" ]; then exec gio open "$2"; fi; exec gio open "$1"'

function isLaunchableName(name) {
  var n = String(name || "").toLowerCase()
  if (/\.pkg\.tar(\.[a-z0-9]+)?$/.test(n)) return true
  var dot = n.lastIndexOf(".")
  return dot > 0 && LAUNCHABLE_EXTS.indexOf(n.slice(dot + 1)) >= 0
}

if (typeof module !== "undefined") {
  module.exports = {
    EXCLUDES: EXCLUDES,
    FILE_FILTERS: FILE_FILTERS,
    FOLDER_FILTERS: FOLDER_FILTERS,
    ALL_FILTER: ALL_FILTER,
    SORT_MODES: SORT_MODES,
    DISPLAY_LIMITS: DISPLAY_LIMITS,
    filtersFor: filtersFor,
    filterAt: filterAt,
    sortMode: sortMode,
    nextSortMode: nextSortMode,
    nextDisplayLimit: nextDisplayLimit,
    accentRegex: accentRegex,
    extractTerms: extractTerms,
    buildArgv: buildArgv,
    buildRootArgv: buildRootArgv,
    parseZoxide: parseZoxide,
    zoxideItems: zoxideItems,
    frecencyBonus: frecencyBonus,
    rootDir: rootDir,
    parseStatLines: parseStatLines,
    formatMtime: formatMtime,
    parentDir: parentDir,
    LAUNCHABLE_EXTS: LAUNCHABLE_EXTS,
    isLaunchableName: isLaunchableName,
    OPEN_FILE_SCRIPT: OPEN_FILE_SCRIPT,
    iconFor: iconFor,
    isSystemPath: isSystemPath,
    parseLines: parseLines,
    scoreItem: scoreItem,
    rankResults: rankResults
  }
}
