// Search roots: folders outside $HOME (a NAS share, a cloud drive, a second
// disk) that the Files and Folders tabs and All search as well, each shown
// under its own label. The launcher never connects anything itself: a root is
// a path the user already mounted, by whatever means (fstab, rclone, sshfs,
// GVFS). A root can be searched live with fd, or through an index that is
// rebuilt in the background, which suits slow network mounts.
//
// state.json:
//   "searchRoots": [
//     { "path": "/mnt/nas", "label": "NAS", "enabled": true, "cacheMinutes": 60 }
//   ]
// cacheMinutes 0 searches live; otherwise the index is rebuilt when older.
//
// Shared by the menu (search, the background indexer) and the bar widget's
// settings popup. Pure data in, data out, so it runs under node.

var MAX_ROOTS = 32
var LABEL_MAX = 40
var PATH_MAX = 1024

// The cache choices the settings popup cycles through, in minutes.
var CACHE_CHOICES = [0, 15, 60, 360, 1440]

// An index larger than this is cut off; the paths past it are not found.
var INDEX_MAX_BYTES = 67108864      // 64 MiB
// Longest a rebuild may run, and how deep it walks.
var INDEX_SECONDS = 900
var INDEX_MAX_DEPTH = 16
// A root that failed to index (offline, unreadable) is tried again after this.
var INDEX_RETRY_MINUTES = 10

// Results one root may contribute to a search.
var ROOT_MAX_RESULTS = 500

// File systems behind which a walk is slow enough that an index is the
// better default for a new root. `fuse` covers rclone and sshfs; `fuseblk`
// is a local disk (NTFS, exFAT) and not in the list.
var NETWORK_FS = ["nfs", "nfs4", "cifs", "smb", "smb2", "smb3", "smbfs", "fuse", "sshfs", "9p", "ceph", "afs", "davfs", "glusterfs", "lustre"]

function isNetworkFs(type) {
  var t = String(type || "").toLowerCase()
  if (t.indexOf("fuse.") === 0 && t !== "fuse.fuseblk") return true
  return NETWORK_FS.indexOf(t) >= 0
}

// FNV-1a over the path: a stable id the menu and the popup agree on without
// storing one, and a safe file name for the index.
function rootId(path) {
  var h = 0x811c9dc5
  var s = String(path)
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return "r" + ("0000000" + h.toString(16)).slice(-8)
}

// An absolute, normalized directory path, or "" when it is not one this
// accepts: "~/" is expanded, repeated and trailing slashes go, and control
// characters, "." or ".." segments, "/" itself and $HOME itself (searched
// already) are refused.
function cleanPath(path, home) {
  var p = String(path === undefined || path === null ? "" : path).trim()
  if (!p || p.length > PATH_MAX) return ""
  if (/[\x00-\x1f\x7f]/.test(p)) return ""
  if (p === "~") p = home
  else if (p.indexOf("~/") === 0) p = home + p.slice(1)
  if (p.charAt(0) !== "/") return ""
  p = p.replace(/\/{2,}/g, "/").replace(/\/+$/, "")
  if (!p) return ""
  var parts = p.split("/")
  for (var i = 1; i < parts.length; i++) if (parts[i] === "." || parts[i] === "..") return ""
  if (home && p === String(home).replace(/\/+$/, "")) return ""
  return p
}

function cleanLabel(label, path) {
  var l = String(label === undefined || label === null ? "" : label).replace(/[\x00-\x1f\x7f]/g, "").trim()
  if (!l) {
    var slash = path.lastIndexOf("/")
    l = path.slice(slash + 1) || path
  }
  return l.length > LABEL_MAX ? l.slice(0, LABEL_MAX) : l
}

function cleanCache(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return 0
  return Math.max(5, Math.min(10080, Math.round(n)))
}

// state.json's searchRoots, validated: entries that are not objects or whose
// path is refused are dropped, duplicates keep the first, and at most
// MAX_ROOTS remain. Each gains its id.
function normalizeRoots(list, home) {
  var out = []
  if (!Array.isArray(list)) return out
  var seen = {}
  for (var i = 0; i < list.length && out.length < MAX_ROOTS; i++) {
    var entry = list[i]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    var path = cleanPath(entry.path, home)
    if (!path || seen[path]) continue
    seen[path] = true
    out.push({
      id: rootId(path),
      path: path,
      label: cleanLabel(entry.label, path),
      enabled: entry.enabled !== false,
      cacheMinutes: cleanCache(entry.cacheMinutes)
    })
  }
  return out
}

// What goes back into state.json: the stored fields only, no id.
function serializeRoots(roots) {
  var out = []
  for (var i = 0; i < roots.length; i++)
    out.push({ path: roots[i].path, label: roots[i].label, enabled: roots[i].enabled, cacheMinutes: roots[i].cacheMinutes })
  return out
}

// The raw list with a new root appended (or the existing one left alone).
function addRoot(list, path, home, fsType) {
  var roots = normalizeRoots(list, home)
  var clean = cleanPath(path, home)
  if (!clean || roots.length >= MAX_ROOTS) return serializeRoots(roots)
  for (var i = 0; i < roots.length; i++) if (roots[i].path === clean) return serializeRoots(roots)
  roots.push({ id: rootId(clean), path: clean, label: cleanLabel("", clean), enabled: true,
               cacheMinutes: isNetworkFs(fsType) ? 60 : 0 })
  return serializeRoots(roots)
}

// The raw list with root `id` changed by `change(root)` or, when change
// returns null, removed.
function updateRoot(list, home, id, change) {
  var roots = normalizeRoots(list, home)
  var out = []
  for (var i = 0; i < roots.length; i++) {
    if (roots[i].id !== id) { out.push(roots[i]); continue }
    var next = change(roots[i])
    if (next) out.push(next)
  }
  return serializeRoots(out)
}

function nextCache(minutes, direction) {
  var i = CACHE_CHOICES.indexOf(minutes)
  if (i < 0) i = 0
  var n = CACHE_CHOICES.length
  return CACHE_CHOICES[((i + (direction < 0 ? -1 : 1)) % n + n) % n]
}

function cacheLabel(minutes) {
  if (!minutes) return "Live"
  if (minutes < 60) return "Index " + minutes + " min"
  if (minutes < 1440) return "Index " + Math.round(minutes / 60) + " h"
  return "Index " + Math.round(minutes / 1440) + " d"
}

function enabledRoots(roots) {
  var out = []
  for (var i = 0; i < roots.length; i++) if (roots[i].enabled) out.push(roots[i])
  return out
}

// The root a path lies in (the deepest one, if roots nest), or null.
function rootFor(path, roots) {
  var best = null
  for (var i = 0; i < roots.length; i++) {
    var r = roots[i].path
    if ((path === r || path.indexOf(r + "/") === 0) && (!best || r.length > best.path.length)) best = roots[i]
  }
  return best
}

// Roots inside $HOME are walked by the $HOME search too; these anchored
// excludes keep it out of them, so each path is found once, under its root.
function homeExcludes(roots, home) {
  var out = []
  var h = String(home || "").replace(/\/+$/, "")
  if (!h) return out
  for (var i = 0; i < roots.length; i++) {
    var p = roots[i].path
    if (p.indexOf(h + "/") !== 0) continue
    // fd reads the pattern as a glob: escape what it would expand.
    out.push("/" + p.slice(h.length + 1).replace(/([\\*?\[\]{}!])/g, "\\$1"))
  }
  return out
}

function indexDir(cacheHome) {
  return cacheHome + "/omarchy-menu-omni/roots"
}

function indexPath(cacheHome, id) {
  return indexDir(cacheHome) + "/" + id + ".idx"
}

// Rebuilds one root's index: bash -c INDEX_SCRIPT bash DIR OUT ROOT DEPTH
// MAXBYTES SECONDS [fd exclude args...]. One rebuild per root at a time
// (flock); a root that does not answer within two seconds is left with its
// old index (exit 4). fd walks without --follow, so a symlink loop on a
// share cannot run away; its NUL-separated output, directories marked by a
// trailing slash, goes to a temporary file renamed over the index only when
// fd finished or was cut off by the size cap.
var INDEX_SCRIPT = [
  'set -u -o pipefail',
  'dir=$1 out=$2 root=$3 depth=$4 max=$5 secs=$6; shift 6',
  'umask 077',
  'mkdir -p -- "$dir" || exit 3',
  'exec 9>"$out.lock" || exit 3',
  'flock -n 9 || exit 0',
  '[ "$(timeout -k 1 2 stat -L -c %F -- "$root" 2>/dev/null)" = directory ] || exit 4',
  'tmp=$(mktemp -- "$dir/.idx.XXXXXX") || exit 3',
  'trap \'rm -f -- "$tmp"\' EXIT',
  'timeout -k 5 "$secs" fd --color=never --print0 --hidden --no-ignore --max-depth "$depth" --type d --type f "$@" -- . "$root" | head -c "$max" > "$tmp"',
  'codes=("${PIPESTATUS[@]}")',
  // fd ends 0; 141 when head stopped reading at the cap, 124 when it ran out
  // of time: either way the paths it got to are worth keeping.
  'case "${codes[0]}" in 0|124|141) ;; *) exit 5 ;; esac',
  'mv -f -- "$tmp" "$out" || exit 3',
  'trap - EXIT'
].join("\n")

function indexCommand(cacheHome, root, excludes) {
  var argv = ["bash", "-c", INDEX_SCRIPT, "bash", indexDir(cacheHome), indexPath(cacheHome, root.id), root.path,
    String(INDEX_MAX_DEPTH), String(INDEX_MAX_BYTES), String(INDEX_SECONDS)]
  for (var i = 0; i < excludes.length; i++) argv.push("-E", excludes[i])
  return argv
}

// Searches indexes: perl -e INDEX_SEARCH_PROGRAM -- KINDS MAX HIDDEN EXTS
// NTERMS TERMS... ROOT INDEX [ROOT INDEX...]. KINDS is "d", "f" or "df";
// EXTS a comma list or "-"; the terms are the fd regexes FileSearch builds
// (accent classes, metacharacters escaped), matched case-insensitively
// against the whole path as fd --full-path does. Each index is opened
// without following links and must be a regular file of ours. Prints the
// matches NUL-terminated, directories with their trailing slash, at most MAX
// per root; a record the size cap cut in half (no final NUL) is skipped.
var INDEX_SEARCH_PROGRAM = [
  'use strict; use warnings; use Fcntl; use Encode ();',
  'my ($kinds, $max, $hidden, $exts, $nterms) = splice(@ARGV, 0, 5);',
  'my @terms = map { my $t = Encode::decode("UTF-8", $_); qr/$t/i } splice(@ARGV, 0, $nterms);',
  'my %ext = map { $_ => 1 } grep { length } split /,/, ($exts eq "-" ? "" : $exts);',
  'my $wantD = index($kinds, "d") >= 0; my $wantF = index($kinds, "f") >= 0;',
  '$/ = "\\0";',
  'while (@ARGV >= 2) {',
  '  my ($root, $idx) = splice(@ARGV, 0, 2);',
  '  sysopen(my $fh, $idx, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;',
  '  my @st = stat($fh) or next;',
  '  next unless -f _ && $st[4] == $<;',
  '  my $n = 0;',
  '  while (my $rec = <$fh>) {',
  '    chomp($rec) or last;',
  '    my $isDir = substr($rec, -1) eq "/";',
  '    next if $isDir ? !$wantD : !$wantF;',
  '    next unless index($rec, $root . "/") == 0;',
  '    my $rel = substr($rec, length($root) + 1);',
  '    next if !$hidden && $rel =~ m{(?:^|/)\\.};',
  '    if (!$isDir && %ext) { next unless $rec =~ /\\.([^.\\/]+)$/ && $ext{lc $1} }',
  '    my $text = $rec =~ /[\\x80-\\xff]/ ? Encode::decode("UTF-8", $rec) : $rec;',
  '    my $ok = 1;',
  '    for my $re (@terms) { if ($text !~ $re) { $ok = 0; last } }',
  '    next unless $ok;',
  '    print $rec, "\\0";',
  '    last if ++$n >= $max;',
  '  }',
  '  close $fh;',
  '}'
].join("\n")

function indexSearchCommand(kinds, hidden, exts, terms, pairs) {
  var argv = ["timeout", "-k", "1", "5", "perl", "-e", INDEX_SEARCH_PROGRAM, "--",
    kinds, String(ROOT_MAX_RESULTS), hidden ? "1" : "0", exts.length ? exts.join(",") : "-", String(terms.length)]
  argv = argv.concat(terms)
  for (var i = 0; i < pairs.length; i++) argv.push(pairs[i].root, pairs[i].index)
  return argv
}

// Status of each root: bash -c STATUS_SCRIPT bash CACHEDIR ID PATH [ID
// PATH...]. Every root is looked at in parallel, each step under a
// two-second timeout, so a hung mount reads as offline instead of stalling
// the rest. One line per root, written by a single printf:
//   id <TAB> online|offline <TAB> fstype <TAB> free bytes <TAB> source
//      <TAB> index mtime (s) <TAB> index paths
// with "-" for what is unknown. The source (the mount's device or remote)
// comes from findmnt and has tabs and newlines replaced.
var STATUS_SCRIPT = [
  'dir=$1; shift',
  'while [ $# -ge 2 ]; do',
  '  id=$1 p=$2; shift 2',
  '  (',
  '    state=offline fs=- free=- src=- at=- count=-',
  '    if [ "$(timeout -k 1 2 stat -L -c %F -- "$p" 2>/dev/null)" = directory ]; then',
  '      state=online',
  '      read -r fs a s < <(timeout -k 1 2 stat -f -L -c "%T %a %S" -- "$p" 2>/dev/null) && free=$((a * s))',
  '      src=$(timeout -k 1 2 findmnt -n -o SOURCE --target "$p" 2>/dev/null | head -n 1 | tr -d "\\r\\n" | tr "\\t" " " | head -c 200)',
  '      src=${src:--}',
  '    fi',
  '    idx="$dir/$id.idx"',
  '    if [ -f "$idx" ] && [ ! -L "$idx" ]; then',
  '      at=$(stat -c %Y -- "$idx" 2>/dev/null || echo -)',
  '      count=$(tr -cd "\\000" < "$idx" | wc -c)',
  '    fi',
  '    printf "%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "$id" "$state" "${fs:--}" "$free" "$src" "$at" "$count"',
  '  ) &',
  'done',
  'wait'
].join("\n")

function statusCommand(cacheHome, roots) {
  var argv = ["timeout", "-k", "1", "8", "bash", "-c", STATUS_SCRIPT, "bash", indexDir(cacheHome)]
  for (var i = 0; i < roots.length; i++) argv.push(roots[i].id, roots[i].path)
  return argv
}

// STATUS_SCRIPT output as { id: { online, fsType, freeBytes, source,
// indexedAt (ms), indexCount } }.
function parseStatus(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length !== 7 || !/^r[0-9a-f]{8}$/.test(f[0])) continue
    var free = Number(f[3])
    var at = Number(f[5])
    var count = Number(f[6])
    map[f[0]] = {
      online: f[1] === "online",
      fsType: f[2] === "-" ? "" : f[2],
      freeBytes: f[3] !== "-" && isFinite(free) ? free : -1,
      source: f[4] === "-" ? "" : f[4],
      indexedAt: f[5] !== "-" && isFinite(at) && at > 0 ? at * 1000 : 0,
      indexCount: f[6] !== "-" && isFinite(count) ? count : -1
    }
  }
  return map
}

function formatBytes(n) {
  if (!(n >= 0)) return ""
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

function formatAge(ms, nowMs) {
  var s = Math.max(0, Math.round(((nowMs === undefined ? Date.now() : nowMs) - ms) / 1000))
  if (s < 60) return "just now"
  if (s < 3600) return Math.round(s / 60) + " min ago"
  if (s < 86400) return Math.round(s / 3600) + " h ago"
  return Math.round(s / 86400) + " d ago"
}

function formatCount(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
}

// One line about a root for the settings popup: where it lives, whether it
// answers, free space, and the index.
function describe(root, status, nowMs) {
  var parts = [root.path]
  if (!status) return parts.concat(["checking…"]).join(" · ")
  if (!status.online) parts.push("offline")
  else {
    var where = status.source && status.source !== status.fsType ? status.fsType + " " + status.source : status.fsType
    if (where) parts.push(where)
    if (status.freeBytes >= 0) parts.push(formatBytes(status.freeBytes) + " free")
  }
  if (root.cacheMinutes > 0) {
    if (status.indexedAt > 0) parts.push(formatCount(status.indexCount) + " paths, indexed " + formatAge(status.indexedAt, nowMs))
    else parts.push("not indexed yet")
  }
  return parts.join(" · ")
}

// Whether a root's index is due: missing, or older than its cache time.
// A failed rebuild waits INDEX_RETRY_MINUTES before the next attempt.
function indexDue(root, indexedAtMs, failedAtMs, nowMs) {
  if (!root.enabled || root.cacheMinutes <= 0) return false
  if (failedAtMs && nowMs - failedAtMs < INDEX_RETRY_MINUTES * 60000) return false
  return !indexedAtMs || nowMs - indexedAtMs >= root.cacheMinutes * 60000
}

// Picks folders to add: bash -c PICK_SCRIPT bash TITLE. Asks the desktop's
// file chooser portal (the default file manager's own dialog when it
// provides one, as Strata or Nautilus do) for directories, and falls back to
// zenity when there is no portal. Prints "path<TAB>fstype" per chosen folder,
// NUL-terminated. Exit 1: cancelled; 2: no way to ask.
var PICK_PORTAL_PROGRAM = [
  'import os, sys',
  'try:',
  '    import gi',
  '    gi.require_version("Gio", "2.0")',
  '    from gi.repository import Gio, GLib',
  'except Exception:',
  '    sys.exit(2)',
  'try:',
  '    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)',
  '    token = "omni%d" % os.getpid()',
  '    sender = bus.get_unique_name()[1:].replace(".", "_")',
  '    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)',
  '    loop = GLib.MainLoop()',
  '    result = {"code": 2, "uris": []}',
  '    def on_response(conn, name, path, iface, signal, params):',
  '        code, res = params.unpack()',
  '        result["code"] = code',
  '        result["uris"] = res.get("uris", []) if code == 0 else []',
  '        loop.quit()',
  '    bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",',
  '                         handle, None, Gio.DBusSignalFlags.NO_MATCH_RULE, on_response)',
  '    options = {"handle_token": GLib.Variant("s", token), "directory": GLib.Variant("b", True),',
  '               "multiple": GLib.Variant("b", True), "modal": GLib.Variant("b", True)}',
  '    bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",',
  '                  "org.freedesktop.portal.FileChooser", "OpenFile",',
  '                  GLib.Variant("(ssa{sv})", ("", sys.argv[1], options)), None, 0, -1, None)',
  '    loop.run()',
  'except Exception:',
  '    sys.exit(2)',
  'if result["code"] != 0:',
  '    sys.exit(1 if result["code"] == 1 else 2)',
  'for uri in result["uris"]:',
  '    path = Gio.File.new_for_uri(uri).get_path()',
  '    if path:',
  '        sys.stdout.buffer.write(os.fsencode(path) + b"\\0")'
].join("\n")

var PICK_SCRIPT = [
  'emit() { while IFS= read -r -d "" p; do',
  '  [ -n "$p" ] || continue',
  '  fs=$(timeout -k 1 2 stat -f -L -c %T -- "$p" 2>/dev/null)',
  '  printf "%s\\t%s\\0" "$p" "${fs:--}"',
  'done; }',
  'python3 -c "$2" "$1" | emit',
  'code=${PIPESTATUS[0]}',
  'if [ "$code" -eq 2 ] && command -v zenity >/dev/null 2>&1; then',
  '  zenity --file-selection --directory --multiple --separator=$\'\\n\' --title="$1" 2>/dev/null | tr "\\n" "\\0" | emit',
  '  [ "${PIPESTATUS[0]}" -eq 0 ] && code=0 || code=1',
  'fi',
  'exit "$code"'
].join("\n")

function pickCommand(title) {
  return ["timeout", "-k", "2", "900", "bash", "-c", PICK_SCRIPT, "bash", title, PICK_PORTAL_PROGRAM]
}

// PICK_SCRIPT output as [{ path, fsType }].
function parsePicked(text) {
  var out = []
  var records = String(text || "").split("\0")
  for (var i = 0; i < records.length; i++) {
    var tab = records[i].lastIndexOf("\t")
    if (tab <= 0) continue
    var fs = records[i].slice(tab + 1)
    out.push({ path: records[i].slice(0, tab), fsType: fs === "-" ? "" : fs })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_ROOTS: MAX_ROOTS,
    CACHE_CHOICES: CACHE_CHOICES,
    INDEX_MAX_BYTES: INDEX_MAX_BYTES,
    INDEX_RETRY_MINUTES: INDEX_RETRY_MINUTES,
    ROOT_MAX_RESULTS: ROOT_MAX_RESULTS,
    isNetworkFs: isNetworkFs,
    rootId: rootId,
    cleanPath: cleanPath,
    normalizeRoots: normalizeRoots,
    serializeRoots: serializeRoots,
    addRoot: addRoot,
    updateRoot: updateRoot,
    nextCache: nextCache,
    cacheLabel: cacheLabel,
    enabledRoots: enabledRoots,
    rootFor: rootFor,
    homeExcludes: homeExcludes,
    indexDir: indexDir,
    indexPath: indexPath,
    INDEX_SCRIPT: INDEX_SCRIPT,
    indexCommand: indexCommand,
    INDEX_SEARCH_PROGRAM: INDEX_SEARCH_PROGRAM,
    indexSearchCommand: indexSearchCommand,
    STATUS_SCRIPT: STATUS_SCRIPT,
    statusCommand: statusCommand,
    parseStatus: parseStatus,
    formatBytes: formatBytes,
    formatAge: formatAge,
    describe: describe,
    indexDue: indexDue,
    PICK_SCRIPT: PICK_SCRIPT,
    PICK_PORTAL_PROGRAM: PICK_PORTAL_PROGRAM,
    pickCommand: pickCommand,
    parsePicked: parsePicked
  }
}
