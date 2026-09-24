// The options the launcher reads from the state directory, shared by the menu
// (SettingsStore.qml, which applies them) and the bar widget's settings popup
// (BarWidget.qml, which edits them), so the two agree on defaults, ranges and
// how a file is written. Pure data in, data out, so it runs under node.

// style.json: the card's geometry. See SettingsStore.qml for what each does.
var STYLE_DEFAULTS = {
  fontScale: 1.0, cardWidth: 560, bodyHeight: 0.6, fixedHeight: false, top: 0.2, pickerHeight: 0.7
}

// Numeric style.json keys: accepted range and the step the popup moves by.
var STYLE_RANGES = {
  fontScale: { min: 0.5, max: 2, step: 0.05 },
  cardWidth: { min: 200, max: 2000, step: 10 },
  bodyHeight: { min: 0.1, max: 0.95, step: 0.05 },
  pickerHeight: { min: 0.1, max: 0.95, step: 0.05 },
  top: { min: 0, max: 0.9, step: 0.02 }
}

var APPS_VIEWS = ["list", "grid"]
// state.json "barLeftClick": what the bar button's left click opens; the
// right click opens the other.
var BAR_CLICKS = ["settings", "menu"]
var CURSOR_STYLES = ["block", "beam", "underline", "outline", "none"]

// Reasoning effort each agent's CLI accepts ("" leaves the CLI's own).
var AGENT_EFFORTS = {
  claude: ["", "low", "medium", "high", "xhigh", "max"],
  codex: ["", "minimal", "low", "medium", "high", "xhigh"],
  agy: ["", "low", "medium", "high"],
  opencode: [""],
  pi: ["", "off", "minimal", "low", "medium", "high", "xhigh", "max"]
}

// Same pattern ai/AiConfig.js accepts for a model name.
var MODEL_PATTERN = /^[A-Za-z0-9._:\/@-]{1,128}$/

// A JSON object from a file's text: {} for an empty or missing file, null
// for one that does not parse or is not an object (left alone, not rewritten).
function parseObject(text) {
  var raw = String(text || "").trim()
  if (!raw) return {}
  try {
    var value = JSON.parse(raw)
    return value && typeof value === "object" && !Array.isArray(value) ? value : null
  } catch (e) {
    return null
  }
}

// A shallow copy with `key` set in place (appended when new), or removed
// when value is undefined; the other keys, unknown ones included, are kept
// in their order.
function withKey(object, key, value) {
  var next = {}
  for (var k in object) {
    if (k !== key) next[k] = object[k]
    else if (value !== undefined) next[k] = value
  }
  if (value !== undefined && !(key in next)) next[key] = value
  return next
}

function cycle(choices, current, direction) {
  var index = choices.indexOf(current)
  if (index < 0) return direction > 0 ? choices[0] : choices[choices.length - 1]
  return choices[(index + direction + choices.length) % choices.length]
}

// One step of a numeric option, clamped and rounded to the step so repeated
// steps do not drift (0.1 + 0.05 + 0.05 ...).
function stepNumber(value, range, direction) {
  var v = Number(value)
  if (!isFinite(v)) v = range.min
  var next = Math.round((v + direction * range.step) / range.step) * range.step
  next = Math.max(range.min, Math.min(range.max, next))
  return Math.round(next * 1000) / 1000
}

// style.json's "top": a share of the screen, or -1 (centred) for anything
// else, "center" included (the menu reads it the same way). Stepping below 0
// centres the card; stepping up from centred starts at 0.
function styleTop(style) {
  var top = style ? style.top : undefined
  return typeof top === "number" && isFinite(top) && top >= STYLE_RANGES.top.min && top <= STYLE_RANGES.top.max
    ? top : -1
}

function stepTop(top, direction) {
  if (top < 0) return direction > 0 ? STYLE_RANGES.top.min : -1
  if (direction < 0 && top <= STYLE_RANGES.top.min) return -1
  return stepNumber(top, STYLE_RANGES.top, direction)
}

// A numeric style.json value as the menu reads it: the file's value when it
// is in range, the default otherwise.
function styleNumber(style, key) {
  var range = STYLE_RANGES[key]
  var v = Number(style ? style[key] : undefined)
  return style && style[key] !== undefined && isFinite(v) && v >= range.min && v <= range.max
    ? v : STYLE_DEFAULTS[key]
}

// Moves `id` one place left (-1) or right (+1) in `order`.
function moveInOrder(order, id, delta) {
  var out = (order || []).slice()
  var from = out.indexOf(id)
  var to = from + delta
  if (from < 0 || to < 0 || to >= out.length) return out
  out.splice(from, 1)
  out.splice(to, 0, id)
  return out
}

// Switches a tab on or off; the last tab that is on stays on.
function toggleDisabled(disabled, id, allIds) {
  var out = (disabled || []).slice()
  var index = out.indexOf(id)
  if (index >= 0) out.splice(index, 1)
  else if (out.length + 1 < allIds.length) out.push(id)
  return out
}

// Reads a file for the menu and the settings popup without trusting the path
// (the reasoning is in Menu.qml, above fileReadDeadline): opened once with
// O_NOFOLLOW | O_NONBLOCK, then checked through that descriptor -- a regular
// file, owned by the user or root, within the byte ceiling. Path and ceiling
// arrive as argv; there is no shell and nothing to quote.
var FILE_READER_PROGRAM = [
  'use Fcntl;',
  'my ($path, $max) = @ARGV;',
  'sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit 1;',
  'my @st = stat($fh) or exit 1;',
  'exit 1 unless -f _;',
  'exit 1 unless $st[4] == $< || $st[4] == 0;',
  'exit 1 if $st[7] > $max;',
  'my $out = "";',
  'while (length($out) < $max) {',
  '  my $n = sysread($fh, my $chunk, $max - length($out));',
  '  exit 1 unless defined $n;',
  '  last if $n == 0;',
  '  $out .= $chunk;',
  '}',
  'print $out;'
].join("\n")

function readFileCommand(path, maxBytes, seconds) {
  return ["timeout", String(seconds || 5), "perl", "-e", FILE_READER_PROGRAM, "--", path, String(maxBytes)]
}

// Adds `id` to a list or takes it out.
function toggleListed(list, id) {
  var out = (list || []).slice()
  var index = out.indexOf(id)
  if (index >= 0) out.splice(index, 1)
  else out.push(id)
  return out
}

// Writes a file under `dir` (0600, directory created as needed) through a
// temporary file and a rename, so a crash mid-write cannot leave half a
// file; the path and the content reach bash as positional arguments, never
// as script text. keepExisting: only create, never replace.
function writeCommand(dir, path, content, keepExisting) {
  var move = keepExisting ? 'mv -n -- "$t" "$2"' : 'mv -f -- "$t" "$2"'
  return ["bash", "-c",
    'umask 077; mkdir -p -- "$1" || exit 1; ' + (keepExisting ? '[ -e "$2" ] && exit 0; ' : '')
      + 't=$(mktemp -- "$2.XXXXXX") || exit 1; printf %s "$3" > "$t" && ' + move + '; rm -f -- "$t"',
    "bash", dir, path, content]
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLE_DEFAULTS: STYLE_DEFAULTS,
    STYLE_RANGES: STYLE_RANGES,
    APPS_VIEWS: APPS_VIEWS,
    BAR_CLICKS: BAR_CLICKS,
    CURSOR_STYLES: CURSOR_STYLES,
    AGENT_EFFORTS: AGENT_EFFORTS,
    MODEL_PATTERN: MODEL_PATTERN,
    parseObject: parseObject,
    withKey: withKey,
    cycle: cycle,
    stepNumber: stepNumber,
    styleTop: styleTop,
    stepTop: stepTop,
    styleNumber: styleNumber,
    moveInOrder: moveInOrder,
    toggleDisabled: toggleDisabled,
    toggleListed: toggleListed,
    FILE_READER_PROGRAM: FILE_READER_PROGRAM,
    readFileCommand: readFileCommand,
    writeCommand: writeCommand
  }
}
