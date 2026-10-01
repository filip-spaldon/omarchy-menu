// The options the launcher reads from the state directory, shared by the menu
// (SettingsStore.qml, which applies them) and the bar widget's settings popup
// (BarWidget.qml, which edits them), so the two agree on defaults, ranges and
// how a file is written. Pure data in, data out, so it runs under node.

// style.json: the card's geometry. See SettingsStore.qml for what each does.
var STYLE_DEFAULTS = {
  fontScale: 1.0, cardWidth: 560, bodyHeight: 0.6, fixedHeight: false, top: 0.2, pickerHeight: 0.7,
  tabSlide: true
}

// Numeric style.json keys: accepted range and the step the popup moves by.
var STYLE_RANGES = {
  fontScale: { min: 0.5, max: 2, step: 0.05 },
  cardWidth: { min: 200, max: 2000, step: 10 },
  bodyHeight: { min: 0.1, max: 0.95, step: 0.05 },
  pickerHeight: { min: 0.1, max: 0.95, step: 0.05 },
  top: { min: 0, max: 0.9, step: 0.02 }
}

// The tab highlight's slide (TabBar.qml). tabSlide is a style default (the
// Tab animation switch under Look in the settings popup); false turns every tab animation
// off, whatever the keys below say. The rest are opt-in style.json keys, not
// written to a new file, so they are there to experiment with but stay out of
// the way:
//   tabSlideMs    slide length in ms; 0 jumps
//   tabEasing     one of TAB_EASINGS (Qt easing curve names)
//   tabOvershoot  how far the Back curves overshoot (Qt's default 1.70158)
//   tabPop        brightness/scale pulse as the pill lands; 0 turns it off
//   tabBezier     [x1, y1, x2, y2], a CSS-style cubic-bezier that replaces
//                 tabEasing; a y above 1 overshoots. x in 0..1, y in -1..3
//   tabSweep      true: the accent text colour travels with the pill, lighting
//                 whatever it covers; false: each label fades on its own
var TAB_ANIM_DEFAULTS = { tabSlide: STYLE_DEFAULTS.tabSlide, tabSlideMs: 120, tabEasing: "OutCubic", tabOvershoot: 1.70158, tabPop: 0, tabBezier: null, tabSweep: true }
var TAB_ANIM_RANGES = {
  tabSlideMs: { min: 0, max: 1000 },
  tabOvershoot: { min: 0, max: 5 },
  tabPop: { min: 0, max: 1 }
}
var TAB_EASINGS = [
  "Linear", "OutQuad", "OutCubic", "OutQuart", "OutQuint", "OutExpo", "OutCirc", "OutSine",
  "InOutQuad", "InOutCubic", "InOutQuart", "InOutExpo", "InOutSine", "OutBack", "InOutBack", "OutElastic", "OutBounce"
]

function validBezier(v) {
  if (!Array.isArray(v) || v.length !== 4) return false
  for (var i = 0; i < 4; i++) {
    var n = Number(v[i])
    if (typeof v[i] !== "number" || !isFinite(n)) return false
    if (i % 2 === 0 ? (n < 0 || n > 1) : (n < -1 || n > 3)) return false
  }
  return true
}

// The tab animation settings from a parsed style.json, each key falling back
// to its default when missing or invalid.
function tabAnim(style) {
  var out = {}
  for (var key in TAB_ANIM_DEFAULTS) {
    var range = TAB_ANIM_RANGES[key]
    var v = style ? style[key] : undefined
    if (key === "tabSweep" || key === "tabSlide") out[key] = typeof v === "boolean" ? v : TAB_ANIM_DEFAULTS[key]
    else if (key === "tabBezier") out[key] = validBezier(v) ? v.map(Number) : null
    else if (!range) out[key] = TAB_EASINGS.indexOf(v) >= 0 ? v : TAB_ANIM_DEFAULTS[key]
    else out[key] = v !== undefined && v !== null && isFinite(Number(v)) && Number(v) >= range.min && Number(v) <= range.max
      ? Number(v) : TAB_ANIM_DEFAULTS[key]
  }
  if (!out.tabSlide) {
    out.tabSlideMs = 0
    out.tabPop = 0
  }
  return out
}

var APPS_VIEWS = ["list", "grid"]
// state.json "barLeftClick": what the bar button's left click opens; the
// right click opens the other.
var BAR_CLICKS = ["settings", "menu"]
var CURSOR_STYLES = ["block", "beam", "underline", "outline", "none"]
// state.json "zoxide": how zoxide's folder scores enter the file search.
var ZOXIDE_MODES = ["off", "rank", "results"]
// state.json's read ceiling: the search roots make it more than a few keys.
var STATE_MAX_BYTES = 65536

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
  'use Fcntl; use Errno qw(ENOENT);',
  'my ($path, $max) = @ARGV;',
  'sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or exit($! == ENOENT ? 2 : 1);',
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
  return ["timeout", "-k", "1", String(seconds || 5), "perl", "-e", FILE_READER_PROGRAM, "--", path, String(maxBytes)]
}

// Adds `id` to a list or takes it out.
function toggleListed(list, id) {
  var out = (list || []).slice()
  var index = out.indexOf(id)
  if (index >= 0) out.splice(index, 1)
  else out.push(id)
  return out
}

// The reader distinguishes ENOENT from refusal, timeout and I/O failure.
// Present-but-empty files are invalid JSON, never permission to reset them.
function readObject(text, exitCode, exitStatus) {
  if (exitStatus) return { ok: false, error: "Settings read was interrupted" }
  if (exitCode === 2) return { ok: true, missing: true, data: {} }
  if (exitCode !== 0) return { ok: false, error: "Could not read settings safely" }
  var data = String(text || "").trim() ? parseObject(text) : null
  return data !== null ? { ok: true, missing: false, data: data }
    : { ok: false, error: "Settings must contain a JSON object" }
}

function patch(key, value, missingOnly) {
  var op = { path: Array.isArray(key) ? key : [key] }
  if (value === undefined) op.remove = true
  else op.value = value
  if (missingOnly) op.missingOnly = true
  return [op]
}

// Serialize read/modify/rename across the menu and popup. Only requested
// keys change; unknown keys and concurrent edits to other keys survive.
// Perl and JSON::PP are supplied by the system, no new runtime dependency.
var FILE_WRITER_PROGRAM = [
  "use strict; use warnings;",
  "use Fcntl qw(:DEFAULT :flock :mode); use Errno qw(ENOENT);",
  "use JSON::PP; use File::Temp qw(tempfile); use File::Path qw(make_path);",
  "my ($dir, $path, $max, $patch) = @ARGV;",
  "my $json = JSON::PP->new->utf8->canonical->indent->indent_length(2)->space_after;",
  "my $ops = $json->decode($patch); die \"invalid patch\\n\" unless ref($ops) eq \"ARRAY\";",
  "umask 0077;",
  "make_path($dir, {mode => 0700}) unless -e $dir;",
  "my @ds = stat($dir);",
  "die \"unsafe directory\\n\" unless @ds && S_ISDIR($ds[2]) && $ds[4] == $<;",
  "chmod(($ds[2] & 07777) & ~0022, $dir) or die \"chmod directory: $!\\n\" if $ds[2] & 0022;",
  "sysopen(my $lock, \"$path.lock\", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0600) or die \"open lock: $!\\n\";",
  "my @ls = stat($lock);",
  "die \"unsafe lock\\n\" unless @ls && S_ISREG($ls[2]) && $ls[4] == $< && $ls[3] == 1;",
  "flock($lock, LOCK_EX) or die \"lock: $!\\n\";",
  "if (opendir(my $dh, $dir)) {",
  "  for my $name (readdir $dh) {",
  "    next unless $name =~ /^\\.settings\\.[A-Za-z0-9]{8}$/;",
  "    my @fs = lstat(\"$dir/$name\");",
  "    unlink(\"$dir/$name\") if @fs && S_ISREG($fs[2]) && $fs[4] == $< && time - $fs[9] > 60;",
  "  }",
  "  closedir($dh);",
  "}",
  "my $data = {};",
  "if (sysopen(my $in, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)) {",
  "  my @st = stat($in);",
  "  die \"unsafe settings file\\n\" unless @st && S_ISREG($st[2]) && ($st[4] == $< || $st[4] == 0) && $st[7] <= $max;",
  "  my $raw = \"\";",
  "  while (length($raw) <= $max) {",
  "    my $n = sysread($in, my $chunk, $max + 1 - length($raw));",
  "    die \"read: $!\\n\" unless defined $n;",
  "    last unless $n; $raw .= $chunk;",
  "  }",
  "  die \"settings too large\\n\" if length($raw) > $max;",
  "  $data = $json->decode($raw);",
  "  die \"settings must be an object\\n\" unless ref($data) eq \"HASH\";",
  "} else { die \"open settings: $!\\n\" unless $! == ENOENT }",
  "OP: for my $op (@$ops) {",
  "  die \"invalid operation\\n\" unless ref($op) eq \"HASH\" && ref($op->{path}) eq \"ARRAY\" && @{$op->{path}};",
  "  my @keys = @{$op->{path}}; my $key = pop @keys; my $obj = $data;",
  "  for my $part (@keys) {",
  "    next OP if $op->{remove} && !exists $obj->{$part};",
  "    $obj->{$part} = {} unless exists $obj->{$part};",
  "    die \"expected object\\n\" unless ref($obj->{$part}) eq \"HASH\";",
  "    $obj = $obj->{$part};",
  "  }",
  "  next if $op->{missingOnly} && exists $obj->{$key};",
  "  if ($op->{remove}) { delete $obj->{$key} } else { $obj->{$key} = $op->{value} }",
  "}",
  "my $content = $json->encode($data);",
  "die \"settings too large\\n\" if length($content) > $max;",
  "my ($out, $temp) = tempfile(\".settings.XXXXXXXX\", DIR => $dir, UNLINK => 1);",
  "chmod 0600, $temp or die \"chmod: $!\\n\";",
  "print {$out} $content or die \"write: $!\\n\";",
  "close($out) or die \"close: $!\\n\";",
  "rename($temp, $path) or die \"rename: $!\\n\";",
  "print $content;"
].join("\n")

function writeCommand(dir, path, operations, maxBytes) {
  return ["timeout", "-k", "1", "5", "perl", "-e", FILE_WRITER_PROGRAM, "--",
          dir, path, String(maxBytes || STATE_MAX_BYTES), JSON.stringify(operations)]
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLE_DEFAULTS: STYLE_DEFAULTS,
    STYLE_RANGES: STYLE_RANGES,
    TAB_ANIM_DEFAULTS: TAB_ANIM_DEFAULTS,
    TAB_EASINGS: TAB_EASINGS,
    tabAnim: tabAnim,
    APPS_VIEWS: APPS_VIEWS,
    BAR_CLICKS: BAR_CLICKS,
    CURSOR_STYLES: CURSOR_STYLES,
    ZOXIDE_MODES: ZOXIDE_MODES,
    STATE_MAX_BYTES: STATE_MAX_BYTES,
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
    readObject: readObject,
    patch: patch,
    FILE_WRITER_PROGRAM: FILE_WRITER_PROGRAM,
    writeCommand: writeCommand
  }
}
