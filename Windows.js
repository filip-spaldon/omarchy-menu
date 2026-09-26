// Open windows for the Windows tab and All's Windows section: the client list
// Hyprland reports, made safe to show, grouped by workspace and filtered by
// the query. Pure data in, data out -- nothing here touches QML -- so it runs
// under node. Reading the list and focusing a window live in
// WindowsController.qml.

// Hyprland addresses are hex pointers ("0xaaab131000f0"). Anything else is
// not a window this tab will hand to a dispatcher.
var ADDRESS_PATTERN = /^0x[0-9a-fA-F]{1,16}$/

// Past this many the list is noise rather than a switcher, and the client
// JSON is bounded anyway.
var MAX_WINDOWS = 200

function isAddress(value) {
  return ADDRESS_PATTERN.test(String(value || ""))
}

function text(value, max) {
  var s = String(value === null || value === undefined ? "" : value)
  return s.length > max ? s.slice(0, max) : s
}

// `hyprctl -j clients` to [{ address, cls, title, workspaceId, workspaceName,
// special, floating, focus, pid }]. Unmapped and hidden clients (a window
// being torn down, a tab of a group) are left out; so is anything without a
// usable address. Malformed input is an empty list, never an exception.
function parseClients(raw) {
  var list
  try {
    list = JSON.parse(String(raw || ""))
  } catch (e) {
    return []
  }
  if (!Array.isArray(list)) return []

  var out = []
  for (var i = 0; i < list.length && out.length < MAX_WINDOWS; i++) {
    var c = list[i]
    if (!c || typeof c !== "object") continue
    if (!isAddress(c.address)) continue
    if (c.mapped === false || c.hidden === true) continue
    var ws = c.workspace && typeof c.workspace === "object" ? c.workspace : {}
    var wsName = text(ws.name, 128)
    var wsId = Number(ws.id)
    if (!isFinite(wsId)) wsId = 0
    out.push({
      address: String(c.address),
      cls: text(c.class || c.initialClass, 256),
      title: text(c.title || c.initialTitle, 512),
      workspaceId: wsId,
      workspaceName: wsName,
      // Special workspaces have negative ids and "special:<name>" names.
      special: wsName.indexOf("special:") === 0 || wsId < 0,
      floating: c.floating === true,
      focus: isFinite(Number(c.focusHistoryID)) ? Number(c.focusHistoryID) : MAX_WINDOWS,
      pid: Number(c.pid) || 0
    })
  }
  return out
}

// What a workspace is called on screen: "2", "Scratchpad" for the one
// SUPER + S toggles, "<name> (special)" for any other special workspace.
function workspaceLabel(win) {
  if (!win) return ""
  if (win.special) {
    var name = win.workspaceName.replace(/^special:/, "")
    if (!name || name === "scratchpad") return "Scratchpad"
    return name + " (special)"
  }
  return win.workspaceName || String(win.workspaceId)
}

// Short form for the right-hand column of a row.
function workspaceTrail(win) {
  if (!win) return ""
  if (win.special) {
    var name = win.workspaceName.replace(/^special:/, "")
    return !name || name === "scratchpad" ? "scratch" : name
  }
  return "ws " + (win.workspaceName || String(win.workspaceId))
}

// Workspaces in number order with the special ones last; inside a workspace
// the most recently focused window first.
function compareWindows(a, b) {
  if (a.special !== b.special) return a.special ? 1 : -1
  if (a.workspaceId !== b.workspaceId) return a.special ? b.workspaceId - a.workspaceId : a.workspaceId - b.workspaceId
  if (a.focus !== b.focus) return a.focus - b.focus
  return a.address < b.address ? -1 : 1
}

// Lower is better, -1 for no match. Every word of the query has to appear
// somewhere in the title, the class, the app name or the workspace; a title
// or app name that starts with the query ranks first.
function matchScore(win, appName, query) {
  var q = String(query || "").toLowerCase().trim()
  if (!q) return 0
  var title = win.title.toLowerCase()
  var name = String(appName || "").toLowerCase()
  var cls = win.cls.toLowerCase()
  var haystack = [title, name, cls, workspaceLabel(win).toLowerCase(), workspaceTrail(win)].join(" ")
  var words = q.split(/\s+/)
  for (var i = 0; i < words.length; i++) if (haystack.indexOf(words[i]) < 0) return -1
  if (name.indexOf(q) === 0 || title.indexOf(q) === 0) return 0
  if (name.indexOf(q) >= 0 || title.indexOf(q) >= 0) return 1
  return 2
}

// windows: parsed clients. appInfo(cls) -> { name, icon } or null, from the
// desktop entries. Returns the menu's row shape (see queryRow in Menu.qml),
// kind "window", with the address as the target.
function windowRows(windows, query, appInfo) {
  var picked = []
  var list = windows || []
  for (var i = 0; i < list.length; i++) {
    var win = list[i]
    var info = (appInfo && appInfo(win.cls)) || null
    var appName = info && info.name ? String(info.name) : win.cls
    var score = matchScore(win, appName, query)
    if (score < 0) continue
    picked.push({ win: win, info: info, appName: appName, score: score })
  }

  var q = String(query || "").trim()
  picked.sort(function(a, b) {
    if (q && a.score !== b.score) return a.score - b.score
    return compareWindows(a.win, b.win)
  })

  var rows = []
  for (var j = 0; j < picked.length; j++) {
    var p = picked[j]
    var details = [p.appName, p.win.special ? workspaceLabel(p.win) : "Workspace " + workspaceLabel(p.win)]
    if (p.win.floating) details.push("floating")
    rows.push({
      itemId: "window:" + p.win.address,
      disabled: false,
      kind: "window",
      icon: p.info && p.info.icon ? "" : "󰖯",
      iconFont: "",
      appIcon: p.info && p.info.icon ? String(p.info.icon) : "",
      appId: p.win.cls,
      label: p.win.title || p.appName || "(untitled)",
      target: p.win.address,
      detail: details.join(" · "),
      path: "",
      childCount: 0,
      action: "",
      provider: "",
      score: p.score,
      section: "",
      trailText: workspaceTrail(p.win)
    })
  }
  return rows
}

// Focusing a window on a hidden workspace (or the scratchpad) brings that
// workspace up. Lua-config Hyprland takes hl.dsp.focus; older builds only
// know focuswindow, so fall back to it as omarchy-launch-or-focus does. The
// address arrives as $1, never spliced into the script.
var FOCUS_SCRIPT = 'hyprctl dispatch "hl.dsp.focus({ window = \\"address:$1\\" })" >/dev/null 2>&1'
  + ' || hyprctl dispatch focuswindow "address:$1" >/dev/null'

function focusCommand(address) {
  if (!isAddress(address)) return null
  return ["bash", "-c", FOCUS_SCRIPT, "omarchy-menu-focus", String(address)]
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_WINDOWS: MAX_WINDOWS,
    isAddress: isAddress,
    parseClients: parseClients,
    workspaceLabel: workspaceLabel,
    workspaceTrail: workspaceTrail,
    compareWindows: compareWindows,
    matchScore: matchScore,
    windowRows: windowRows,
    focusCommand: focusCommand
  }
}
