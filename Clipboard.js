// The Clipboard tab: Omarchy's clipboard history made safe to show, filtered
// by the query, and the argv of Omarchy's helpers that paste, copy or open an
// entry. Pure data in, data out -- nothing here touches QML -- so it runs
// under node. Reading the history file lives in ClipboardController.qml.
//
// The history is written by Omarchy's own clipboard service (Omarchy 4.5+,
// shell/plugins/clipboard): a JSON array, newest first, whose entries are a
// string, { type: "text", text } or { type: "image", path, mime, capturedAt }.
// This module never reads the clipboard and never writes the history; an
// entry is acted on by its index, which Omarchy's helpers look up themselves.
//
// Written in ES2015 (const/let, arrows); object rest/spread does not parse
// in Quickshell's engine (see Windows.js).

// The guarded reader refuses anything larger. Omarchy keeps up to 500
// entries; a history that has grown past this is not read at all.
const MAX_HISTORY_BYTES = 4194304  // 4 MiB
const MAX_ENTRIES = 500
// Entries past this raw position are not looked at, whatever the file holds.
const MAX_SCAN = 1000
const LABEL_LENGTH = 200
// Only the start of an entry is scanned for its label.
const LABEL_SCAN = 8192
const MAX_CAPTURED_AT_LENGTH = 64
const MAX_PATH_LENGTH = 4096
// A picture file larger than this is not shown, only listed. Screenshots of
// a 4K screen are well under it; a decoder that is handed one has to read
// all of it, whatever size it is asked to draw.
const MAX_IMAGE_BYTES = 16777216  // 16 MiB

const TEXT_ICON = "󰅍"
const IMAGE_ICON = "󰋩"

const MIME_PATTERN = /^image\/[a-z0-9.+-]+$/
const INDEX_PATTERN = /^[0-9]+$/
const MAX_SAFE_INDEX = 9007199254740991

// ------------------------------------------------------------ parsing ----

// A history index Omarchy's helpers accept: a non-negative integer, as a
// number or a string of digits. Anything else could pass as an option.
function isHistoryIndex(value) {
  const number = typeof value === "number" ? value
    : typeof value === "string" && INDEX_PATTERN.test(value) ? Number(value) : -1
  return number >= 0 && number <= MAX_SAFE_INDEX && Math.floor(number) === number
}

function isImageMime(mime) {
  return typeof mime === "string" && mime.length <= 128 && MIME_PATTERN.test(mime)
}

// An image is shown only from Omarchy's own image folder: an absolute path
// directly or deeper inside `imageDir` (which ends in "/"), with no "." or
// ".." segment and nothing that could pass as an option.
function isSafeImagePath(path, imageDir) {
  const dir = String(imageDir || "")
  if (typeof path !== "string" || !dir || dir.charAt(0) !== "/" || dir.slice(-1) !== "/") return false
  if (path.length > MAX_PATH_LENGTH || path.indexOf("\u0000") >= 0) return false
  if (path.indexOf(dir) !== 0 || path.length === dir.length) return false
  const segments = path.slice(dir.length).split("/")
  return segments.every(segment => segment !== "" && segment !== "." && segment !== "..")
}

// Counted once here rather than on every keystroke's rebuild.
function textEntry(index, text, actionable) {
  return { index: index, type: "text", text: text, lineCount: text.split("\n").length, actionable: actionable }
}

// One raw history value to { index, type, ... }, or null for anything not a
// usable entry. `index` is the value's position in the file, which is what
// the helpers look up. A bare string is shown, but cannot be acted on: the
// helpers only accept { type: "text" } objects, as Omarchy writes them.
function normalizeEntry(value, index, imageDir) {
  if (typeof value === "string") {
    return value.trim() ? textEntry(index, value, false) : null
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  if (value.type === "text") {
    if (typeof value.text !== "string" || !value.text.trim()) return null
    return textEntry(index, value.text, true)
  }
  if (value.type === "image") {
    if (!isSafeImagePath(value.path, imageDir) || !isImageMime(value.mime)) return null
    const capturedAt = typeof value.capturedAt === "string" ? value.capturedAt.slice(0, MAX_CAPTURED_AT_LENGTH) : ""
    return { index: index, type: "image", path: value.path, mime: value.mime, capturedAt: capturedAt, actionable: true }
  }
  return null
}

// The history file's text to its usable entries, newest first, at most
// MAX_ENTRIES. Malformed input is an empty list, never an exception.
function parseHistory(json, imageDir) {
  let values
  try {
    values = JSON.parse(String(json || ""))
  } catch (error) {
    return []
  }
  if (!Array.isArray(values)) return []
  const entries = []
  for (let i = 0; i < values.length && i < MAX_SCAN && entries.length < MAX_ENTRIES; i++) {
    const entry = normalizeEntry(values[i], i, imageDir)
    if (entry) {
      entry.search = foldText(searchableText(entry))
      entries.push(entry)
    }
  }
  return entries
}

// ----------------------------------------------------------- matching ----

// Lower case without accents, so "cafe" finds "Café". normalize() is
// guarded: an engine without it still matches case-insensitively.
function foldText(text) {
  const lower = String(text || "").toLowerCase()
  return typeof lower.normalize === "function" ? lower.normalize("NFD").replace(/[\u0300-\u036f]/g, "") : lower
}

function searchableText(entry) {
  if (entry.type === "image") return "image " + entry.mime + " " + entry.capturedAt
  return entry.text
}

// Every word of the query appears somewhere in the entry's full text.
function matches(entry, query) {
  const words = foldText(query).trim().split(/\s+/).filter(word => word !== "")
  if (words.length === 0) return true
  const haystack = entry.search !== undefined ? entry.search : foldText(searchableText(entry))
  return words.every(word => haystack.indexOf(word) >= 0)
}

// --------------------------------------------------------------- rows ----

// The first line with something on it, whitespace collapsed and cut to
// LABEL_LENGTH. Control characters are left for MenuModel.sanitizeRow, the
// gate every row passes on its way to the list.
function textLabel(text) {
  const head = String(text || "").slice(0, LABEL_SCAN)
  const lines = head.split(/[\r\n\u2028\u2029]/)
  let line = ""
  for (let i = 0; i < lines.length && !line; i++) line = lines[i].replace(/\s+/g, " ").trim()
  if (!line) line = head.replace(/\s+/g, " ").trim()
  return line.length > LABEL_LENGTH ? line.slice(0, LABEL_LENGTH - 1) + "…" : line
}

function plural(count, one, other) {
  return count + " " + (count === 1 ? one : other)
}

function textDetail(entry) {
  return plural(entry.lineCount, "line", "lines") + " · " + plural(entry.text.length, "char", "chars")
}

function imageDetail(entry) {
  const parts = ["Image", entry.mime]
  if (entry.capturedAt) parts.push(entry.capturedAt)
  return parts.join(" · ")
}

// ------------------------------------------------------------ previews ----

// One bounded stat of every image entry's file, after the history is read:
// file type (raw mode, which no locale translates), size and path, each
// record NUL-terminated. No -L: a symlink is reported as one and refused,
// never followed. null when there is no image to look at.
function imageStatCommand(entries) {
  const paths = []
  for (const entry of entries || []) {
    if (entry.type === "image" && typeof entry.path === "string" && entry.path.charAt(0) === "/"
        && paths.indexOf(entry.path) < 0) paths.push(entry.path)
  }
  if (paths.length === 0) return null
  return ["timeout", "-k", "1", "3", "stat", "--printf", "%f\t%s\t%n\\0", "--"].concat(paths)
}

const S_IFMT = 0xF000
const S_IFREG = 0x8000
const SIZE_PATTERN = /^[0-9]+$/
const MODE_PATTERN = /^[0-9a-f]{1,8}$/

// imageStatCommand's output to { path: true } for the files a thumbnail may
// be drawn from: regular files (not a symlink, FIFO or device, which could
// stall a decoder), not empty, at most `maxBytes`, and only paths that were
// asked about -- a record for anything else is ignored.
function previewablePaths(statText, entries, maxBytes) {
  const limit = typeof maxBytes === "number" ? maxBytes : MAX_IMAGE_BYTES
  const asked = {}
  for (const entry of entries || []) if (entry.type === "image" && typeof entry.path === "string") asked[entry.path] = true
  const previewable = {}
  // The piece after the last NUL is an unfinished record (a stat cut off by
  // its deadline), never a whole one.
  const records = String(statText || "").split("\u0000").slice(0, -1)
  for (const record of records) {
    const first = record.indexOf("\t")
    const second = first < 0 ? -1 : record.indexOf("\t", first + 1)
    if (second < 0) continue
    const mode = record.slice(0, first)
    const size = record.slice(first + 1, second)
    const path = record.slice(second + 1)
    if (!MODE_PATTERN.test(mode) || !SIZE_PATTERN.test(size) || asked[path] !== true) continue
    const bytes = Number(size)
    if ((parseInt(mode, 16) & S_IFMT) === S_IFREG && bytes > 0 && bytes <= limit) previewable[path] = true
  }
  return previewable
}

// A file URL for an image path, every segment percent-encoded so a "#" or
// "?" in a name cannot end the path early. "" for anything not absolute.
function imageSource(path) {
  if (typeof path !== "string" || path.charAt(0) !== "/" || path.indexOf("\u0000") >= 0) return ""
  return "file://" + path.split("/").map(encodeURIComponent).join("/")
}

// The menu's row shape (queryRow in Menu.qml), every field on every row; see
// Windows.toWindowRow. Only the history index travels in the row: the
// controller looks the entry up again when it is acted on.
// `previewable` (previewablePaths) decides which images get a thumbnail:
// `imagePath` is their file, "" on every other row.
function toClipboardRow(entry, previewable) {
  const isImage = entry.type === "image"
  return {
    itemId: "clipboard:" + entry.index,
    // A bare string has no history index the helpers accept.
    disabled: !entry.actionable,
    kind: "clipboard",
    icon: isImage ? IMAGE_ICON : TEXT_ICON,
    iconFont: "",
    appIcon: "",
    appId: "",
    label: isImage ? (entry.capturedAt ? "Image from " + entry.capturedAt : "Image") : textLabel(entry.text),
    target: String(entry.index),
    detail: isImage ? imageDetail(entry) : textDetail(entry),
    path: "",
    imagePath: isImage && previewable && previewable[entry.path] === true ? entry.path : "",
    childCount: 0,
    action: "",
    provider: "",
    score: 0,
    section: "",
    trailText: ""
  }
}

function clipboardRows(entries, query, previewable) {
  return (entries || []).filter(entry => matches(entry, query)).map(entry => toClipboardRow(entry, previewable))
}

function entryAt(entries, index) {
  if (!isHistoryIndex(index)) return null
  const wanted = Number(index)
  for (const entry of entries || []) if (entry.index === wanted) return entry
  return null
}

// ----------------------------------------------------------- commands ----

// Pasting and copying finish in well under a second; the deadline only
// stops a helper that hangs (wl-copy waiting on a compositor that is gone).
const HELPER_DEADLINE = 10

function bounded(argv) {
  return ["timeout", "-k", "1", String(HELPER_DEADLINE)].concat(argv)
}

// The argv that pastes an entry into the focused window (Shift+Insert, as
// Omarchy's own picker does) or, with copyOnly, puts it on the clipboard.
// null for anything that cannot be acted on.
function pasteCommand(entry, binDir, copyOnly) {
  if (!entry || !entry.actionable || !binDir || !isHistoryIndex(entry.index)) return null
  if (entry.type === "image") {
    if (!isImageMime(entry.mime) || typeof entry.path !== "string" || entry.path.charAt(0) !== "/") return null
    const fileArgs = copyOnly ? ["--copy-only", entry.mime, entry.path] : [entry.mime, entry.path]
    return bounded([binDir + "/omarchy-clipboard-paste-file"].concat(fileArgs))
  }
  const mode = copyOnly ? "--copy-only" : "--shift-insert"
  return bounded([binDir + "/omarchy-clipboard-paste-text", mode, "--history-index", String(entry.index)])
}

// Opens a link in the browser, text in the editor, an image in the viewer.
// Not under a deadline: the helper execs into the application it opens.
function openCommand(entry, binDir) {
  if (!entry || !entry.actionable || !binDir || !isHistoryIndex(entry.index)) return null
  return [binDir + "/omarchy-clipboard-open", "--history-index", String(entry.index)]
}

const HELPERS = ["omarchy-clipboard-paste-text", "omarchy-clipboard-paste-file", "omarchy-clipboard-open"]

// Exits 0 only when every helper is there to run.
function helpersCheckCommand(binDir) {
  const argv = ["timeout", "-k", "1", "2", "test"]
  HELPERS.forEach((name, i) => {
    if (i > 0) argv.push("-a")
    argv.push("-x", binDir + "/" + name)
  })
  return argv
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_HISTORY_BYTES,
    MAX_ENTRIES,
    MAX_IMAGE_BYTES,
    LABEL_LENGTH,
    HELPERS,
    isHistoryIndex,
    isImageMime,
    isSafeImagePath,
    normalizeEntry,
    parseHistory,
    foldText,
    matches,
    textLabel,
    toClipboardRow,
    clipboardRows,
    entryAt,
    imageStatCommand,
    previewablePaths,
    imageSource,
    pasteCommand,
    openCommand,
    helpersCheckCommand
  }
}
