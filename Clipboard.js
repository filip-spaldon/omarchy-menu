// The Clipboard tab: Omarchy's clipboard history made safe to show, filtered
// by the query, and the commands that paste, copy or open an
// entry. Pure data in, data out -- nothing here touches QML -- so it runs
// under node. Reading the history file lives in ClipboardController.qml.
//
// The history is written by Omarchy's own clipboard service (Omarchy 4.5+,
// shell/plugins/clipboard): a JSON array, newest first, whose entries are a
// string, { type: "text", text } or { type: "image", path, mime, capturedAt }.
// This module never reads the clipboard and never writes the history; an
// actions use the snapshot shown in the menu, not a fresh lookup by index.
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
const FILE_ICON = "󰈔"
const LINK_ICON = "󰌹"
const COLOR_ICON = "󰏘"

const MIME_PATTERN = /^image\/[a-z0-9.+-]+$/
const INDEX_PATTERN = /^[0-9]+$/
const MAX_SAFE_INDEX = 9007199254740991

// ------------------------------------------------------------ parsing ----

// A snapshot index: a non-negative integer, as a number or a string of digits.
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

// Counted and classified once here rather than on every keystroke's rebuild.
function textEntry(index, text) {
  const entry = { index: index, type: "text", text: text, lineCount: text.split("\n").length,
                  kind: "text", fileCount: 0, host: "", swatch: "" }
  const files = fileCount(text)
  const color = files ? "" : colorSwatch(text)
  const link = files || color ? "" : wholeLink(text)
  if (files) {
    entry.kind = "file"
    entry.fileCount = files
  } else if (color) {
    entry.kind = "color"
    entry.swatch = color
  } else if (link) {
    entry.kind = "link"
    entry.host = linkHost(link)
  }
  return entry
}

// ------------------------------------------------------- classification ----
// What kind of text an entry is, for the type filter: one or more file paths,
// a link, a colour, or plain text. Each check looks at a bounded part of the
// text and tests whole-text shapes, so a paragraph that mentions a URL stays
// text. Nothing here is executed or handed to Qt as is.

// A file list longer than this is plain text, however it looks.
const FILE_SCAN = 65536
const MAX_FILE_LINES = 1000
const LINK_LENGTH = 8192
const COLOR_LENGTH = 64

// An absolute path ("/" then anything but a second "/" or "*", so "//" and
// "/*" comments are not paths) or a file:// URI with an absolute path; no
// control characters or tabs in either.
const PATH_LINE = /^(?:\/(?![\/*])|file:\/\/(?:localhost)?\/)[^\x00-\x1f\x7f]*$/i

// The number of paths when every line with something on it is one (blank
// lines and text/uri-list "#" comments aside); 0 for anything else.
function fileCount(text) {
  if (typeof text !== "string" || text.length > FILE_SCAN) return 0
  const lines = text.split(/\r?\n/)
  if (lines.length > MAX_FILE_LINES) return 0
  let count = 0
  for (const raw of lines) {
    const line = raw.trim()
    if (!line || line.charAt(0) === "#") continue
    if (!PATH_LINE.test(line)) return 0
    count++
  }
  return count
}

const URL_WHOLE = /^https?:\/\/[^\s"'<>\\\x00-\x1f\x7f]+$/i
const DOMAIN_WHOLE = /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(?:\/[^\s"'<>\\\x00-\x1f\x7f]*)?$/i

// The whole trimmed text as an http(s) link ("https://" added to a bare
// domain), or "" when it is anything more or less than one link.
function wholeLink(text) {
  const trimmed = String(text || "").trim()
  if (!trimmed || trimmed.length > LINK_LENGTH) return ""
  if (URL_WHOLE.test(trimmed)) return trimmed
  return DOMAIN_WHOLE.test(trimmed) ? "https://" + trimmed : ""
}

// A link's host for its detail line: no user name or password, only the
// characters a host (or an IPv6 literal and port) is made of, else "".
function linkHost(link) {
  const match = String(link || "").match(/^https?:\/\/([^\/?#]*)/i)
  if (!match) return ""
  const authority = match[1]
  const host = authority.slice(authority.lastIndexOf("@") + 1).toLowerCase()
  return /^[a-z0-9.\-:\[\]]{1,253}$/.test(host) ? host : ""
}

const HEX_COLOR = /^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i
const FUNC_COLOR = /^(rgba?|hsla?)\(\s*([^()]*?)\s*\)$/i
const NUMBER = /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/

function clamp(value, low, high) {
  return Math.min(high, Math.max(low, value))
}

// "12", "12.5" or "50%" to a number, a percentage scaled to `percentOf`;
// NaN for anything else, or for a percentage where none is allowed.
function colorNumber(token, percentOf, unit) {
  let text = String(token)
  let scale = 1
  if (text.slice(-1) === "%") {
    if (!percentOf) return NaN
    text = text.slice(0, -1)
    scale = percentOf / 100
  } else if (unit && text.slice(-unit.length).toLowerCase() === unit) {
    text = text.slice(0, -unit.length)
  }
  return NUMBER.test(text) ? Number(text) * scale : NaN
}

function hexByte(value) {
  const hex = Math.round(clamp(value, 0, 255)).toString(16)
  return hex.length === 1 ? "0" + hex : hex
}

// Channels to Qt's "#AARRGGBB" -- note the alpha first, unlike CSS.
function qtColor(r, g, b, a) {
  return "#" + hexByte(a * 255) + hexByte(r) + hexByte(g) + hexByte(b)
}

function hueToChannel(p, q, t) {
  if (t < 0) t += 1
  if (t > 1) t -= 1
  if (t < 1 / 6) return p + (q - p) * 6 * t
  if (t < 1 / 2) return q
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
  return p
}

// The arguments of rgb()/hsl(): "a, b, c[, d]" or "a b c[ / d]".
function colorArguments(inner) {
  let parts
  if (inner.indexOf(",") >= 0) {
    parts = inner.split(",").map(part => part.trim())
  } else {
    const halves = inner.split("/")
    if (halves.length > 2) return null
    parts = halves[0].trim().split(/\s+/)
    if (halves.length === 2) parts.push(halves[1].trim())
  }
  return (parts.length === 3 || parts.length === 4) && parts.every(part => part !== "") ? parts : null
}

// The whole trimmed text as a CSS colour -- #rgb, #rgba, #rrggbb, #rrggbbaa,
// rgb()/rgba() or hsl()/hsla() -- to a Qt "#AARRGGBB" string built here from
// parsed numbers, never the text itself; "" for anything else.
function colorSwatch(text) {
  const trimmed = String(text || "").trim()
  if (!trimmed || trimmed.length > COLOR_LENGTH) return ""
  const hex = trimmed.match(HEX_COLOR)
  if (hex) {
    let digits = hex[1]
    if (digits.length <= 4) digits = digits.split("").map(d => d + d).join("")
    const channel = i => parseInt(digits.slice(i * 2, i * 2 + 2), 16)
    return qtColor(channel(0), channel(1), channel(2), digits.length === 8 ? channel(3) / 255 : 1)
  }
  const call = trimmed.match(FUNC_COLOR)
  if (!call) return ""
  const parts = colorArguments(call[2])
  if (!parts) return ""
  const alpha = parts.length === 4 ? colorNumber(parts[3], 1) : 1
  if (isNaN(alpha)) return ""
  const a = clamp(alpha, 0, 1)
  if (call[1].toLowerCase().charAt(0) === "r") {
    const channels = parts.slice(0, 3).map(part => colorNumber(part, 255))
    if (channels.some(isNaN)) return ""
    return qtColor(channels[0], channels[1], channels[2], a)
  }
  const hue = colorNumber(parts[0], 0, "deg")
  const sat = colorNumber(parts[1], 1)
  const light = colorNumber(parts[2], 1)
  if (isNaN(hue) || isNaN(sat) || isNaN(light)) return ""
  // Saturation and lightness without "%" are read as percentages, as CSS
  // Color 4 allows; written with it they are already 0..1.
  const s = clamp(parts[1].slice(-1) === "%" ? sat : sat / 100, 0, 1)
  const l = clamp(parts[2].slice(-1) === "%" ? light : light / 100, 0, 1)
  const h = ((hue % 360) + 360) % 360 / 360
  if (s === 0) return qtColor(l * 255, l * 255, l * 255, a)
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  return qtColor(hueToChannel(p, q, h + 1 / 3) * 255, hueToChannel(p, q, h) * 255,
                 hueToChannel(p, q, h - 1 / 3) * 255, a)
}

// A swatch string as colorSwatch writes it; ResultRow checks again before use.
function isSwatch(value) {
  return typeof value === "string" && /^#[0-9a-f]{8}$/.test(value)
}

// ------------------------------------------------------------- filters ----

// The type filter, as in omacast: Text holds only what is none of the others.
const FILTERS = [
  { id: "all", label: "All Types", kind: "", noun: "" },
  { id: "text", label: "Text", kind: "text", noun: "text" },
  { id: "images", label: "Images", kind: "image", noun: "images" },
  { id: "files", label: "Files", kind: "file", noun: "files" },
  { id: "links", label: "Links", kind: "link", noun: "links" },
  { id: "colors", label: "Colors", kind: "color", noun: "colors" }
]

function filterAt(index) {
  return FILTERS[index] || FILTERS[0]
}

function filterIndex(id) {
  for (let i = 0; i < FILTERS.length; i++) if (FILTERS[i].id === id) return i
  return -1
}

function entryKind(entry) {
  if (!entry) return ""
  return entry.type === "image" ? "image" : entry.kind || "text"
}

function matchesFilter(entry, filterId) {
  const filter = FILTERS[filterIndex(filterId)]
  return !filter || !filter.kind || entryKind(entry) === filter.kind
}

// What the list says when the history has nothing of the filter's type; ""
// when it does, or for All.
function emptyFilterText(entries, filterId) {
  const filter = FILTERS[filterIndex(filterId)]
  if (!filter || !filter.kind) return ""
  if ((entries || []).some(entry => entryKind(entry) === filter.kind)) return ""
  return "No " + filter.noun + " in clipboard history"
}

// One raw history value to { index, type, ... }, or null for anything not a
// usable entry. `index` is the value's position in the snapshot, including
// any entries that were dropped.
function normalizeEntry(value, index, imageDir) {
  if (typeof value === "string") {
    return value.trim() ? textEntry(index, value) : null
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  if (value.type === "text") {
    if (typeof value.text !== "string" || !value.text.trim()) return null
    return textEntry(index, value.text)
  }
  if (value.type === "image") {
    if (!isSafeImagePath(value.path, imageDir) || !isImageMime(value.mime)) return null
    const capturedAt = typeof value.capturedAt === "string" ? value.capturedAt.slice(0, MAX_CAPTURED_AT_LENGTH) : ""
    return { index: index, type: "image", path: value.path, mime: value.mime, capturedAt: capturedAt }
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
  const counts = plural(entry.lineCount, "line", "lines") + " · " + plural(entry.text.length, "char", "chars")
  if (entry.kind === "file") return plural(entry.fileCount, "file", "files")
  if (entry.kind === "link") return entry.host ? "Link · " + entry.host : "Link"
  if (entry.kind === "color") return "Color"
  return counts
}

function textIcon(entry) {
  if (entry.kind === "file") return FILE_ICON
  if (entry.kind === "link") return LINK_ICON
  if (entry.kind === "color") return COLOR_ICON
  return TEXT_ICON
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
  const imageReady = isImage && previewable && previewable[entry.path] === true
  return {
    itemId: "clipboard:" + entry.index,
    disabled: isImage && !imageReady,
    kind: "clipboard",
    icon: isImage ? IMAGE_ICON : textIcon(entry),
    iconFont: "",
    appIcon: "",
    appId: "",
    label: isImage ? (entry.capturedAt ? "Image from " + entry.capturedAt : "Image") : textLabel(entry.text),
    target: String(entry.index),
    detail: isImage ? imageDetail(entry) : textDetail(entry),
    path: "",
    imagePath: imageReady ? entry.path : "",
    // A colour entry's swatch, Qt "#AARRGGBB" from colorSwatch; "" otherwise.
    swatch: !isImage && isSwatch(entry.swatch) ? entry.swatch : "",
    childCount: 0,
    action: "",
    provider: "",
    score: 0,
    section: "",
    trailText: ""
  }
}

// `filterId` is a FILTERS id; anything else (or none) shows every type.
function clipboardRows(entries, query, previewable, filterId) {
  return (entries || []).filter(entry => matchesFilter(entry, filterId) && matches(entry, query))
    .map(entry => toClipboardRow(entry, previewable))
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

// An HTTP(S) link in the selected text, or the whole text if it is a bare
// domain. Never treat other schemes or leading options as launch targets.
function textLink(text) {
  const url = text.match(/https?:\/\/[^\s"'<>\\\x00-\x1f\x7f]+/i)
  if (url) return url[0]
  const domain = text.trim().match(/^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}(?:\/[^\s"'<>\\\x00-\x1f\x7f]*)?$/i)
  return domain ? "https://" + domain[0] : ""
}

// ------------------------------------------------------- paste target ----
// Terminals paste with Ctrl+Shift+V, every other window with Shift+Insert,
// as Omarchy's universal paste does (default/hypr/bindings/clipboard.lua).
// The window is the one that had focus under the launcher: Hyprland's
// active window stays the last focused client while a layer surface holds
// the keyboard. It is a terminal when Hyprland tagged it "terminal" (Omarchy's
// default/hypr/apps/terminals.lua) or its class is on this fixed list. Only
// the resulting token, "terminal" or "app", ever reaches a command.
const TERMINAL_CLASSES = [
  "alacritty", "kitty", "foot", "footclient", "com.mitchellh.ghostty", "ghostty",
  "org.wezfurlong.wezterm", "wezterm", "org.kde.konsole", "konsole",
  "org.gnome.terminal", "gnome-terminal", "gnome-terminal-server",
  "org.gnome.ptyxis", "ptyxis", "herdr"
]
const ACTIVE_WINDOW_BYTES = 65536
const MAX_TAGS = 64

// A fixed script, bounded in time and output; nothing is interpolated.
function activeWindowCommand() {
  return ["bash", "-c", "timeout -k 1 2 hyprctl -j activewindow | head -c " + ACTIVE_WINDOW_BYTES]
}

// `hyprctl -j activewindow` output to "terminal" or "app"; anything
// unreadable is "app", the Shift+Insert every Omarchy terminal also takes.
function pasteModeFor(json) {
  const text = String(json || "")
  if (!text || text.length >= ACTIVE_WINDOW_BYTES) return "app"
  let window
  try {
    window = JSON.parse(text)
  } catch (error) {
    return "app"
  }
  if (!window || typeof window !== "object" || Array.isArray(window)) return "app"
  const tags = Array.isArray(window.tags) ? window.tags.slice(0, MAX_TAGS) : []
  // Dynamic tags carry a trailing "*".
  if (tags.some(tag => typeof tag === "string" && tag.replace(/\*$/, "") === "terminal")) return "terminal"
  const windowClass = typeof window.class === "string" && window.class.length <= 256 ? window.class.toLowerCase() : ""
  return windowClass && TERMINAL_CLASSES.indexOf(windowClass) >= 0 ? "terminal" : "app"
}

function pasteMode(mode) {
  return mode === "terminal" ? "terminal" : "app"
}

// Fixed scripts; clipboard text is private and can exceed the argument
// size limit, so send it verbatim on stdin. An image goes to wl-copy from its
// verified file with its validated mime type, as omarchy-clipboard-paste-file
// does -- that helper always sends Shift+Insert, so pasting does not use it.
// $1 is the paste mode token. Delay the paste as Omarchy does, and never send
// a paste key if the copy failed.
const PASTE_KEYS = 'sleep 0.15 && if [ "$1" = terminal ]; then wtype -M ctrl -M shift -k v -m shift -m ctrl;'
  + " else wtype -M shift -k Insert -m shift; fi"
const PASTE_SCRIPT = "wl-copy && " + PASTE_KEYS
const IMAGE_PASTE_SCRIPT = 'wl-copy --type "$2" <"$3" && ' + PASTE_KEYS
const OPEN_TEXT_SCRIPT = [
  "file=$(mktemp -t omni-clipboard.XXXXXXXXXX.txt) || exit 1",
  'if cat >"$file"; then printf "%s" "$file"; else rm -f -- "$file"; exit 1; fi'
].join("\n")

// `mode` is the paste target ("terminal" or "app", see pasteModeFor); only
// pasting uses it.
function actionFor(entry, binDir, operation, verifiedImages, mode) {
  if (!entry || !binDir) return null
  if (operation !== "paste" && operation !== "copy" && operation !== "open") return null
  if (entry.type === "image") {
    if (!isImageMime(entry.mime) || typeof entry.path !== "string" || entry.path.charAt(0) !== "/"
        || !verifiedImages || verifiedImages[entry.path] !== true) return null
    if (operation === "open") return { command: ["omasnap", "--notify", entry.path] }
    if (operation === "copy")
      return { command: bounded([binDir + "/omarchy-clipboard-paste-file", "--copy-only", entry.mime, entry.path]) }
    return { command: bounded(["bash", "-c", IMAGE_PASTE_SCRIPT, "omni-paste", pasteMode(mode), entry.mime, entry.path]) }
  }
  if (entry.type !== "text" || typeof entry.text !== "string" || !entry.text) return null
  if (operation === "open") {
    const link = textLink(entry.text)
    if (link && link.length <= 8192) return { command: [binDir + "/omarchy-launch-browser", link] }
    return { command: bounded(["bash", "-c", OPEN_TEXT_SCRIPT]), input: entry.text, edit: true }
  }
  const argv = operation === "copy" ? ["wl-copy"] : ["bash", "-c", PASTE_SCRIPT, "omni-paste", pasteMode(mode)]
  return { command: bounded(argv), input: entry.text }
}

function helpersCheckCommand(binDir) {
  return ["timeout", "-k", "1", "2", "test", "-x", binDir + "/omarchy-clipboard-paste-file"]
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_HISTORY_BYTES,
    MAX_ENTRIES,
    MAX_IMAGE_BYTES,
    LABEL_LENGTH,
    FILTERS,
    filterAt,
    filterIndex,
    matchesFilter,
    emptyFilterText,
    fileCount,
    wholeLink,
    linkHost,
    colorSwatch,
    isSwatch,
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
    actionFor,
    TERMINAL_CLASSES,
    activeWindowCommand,
    pasteModeFor,
    helpersCheckCommand
  }
}
