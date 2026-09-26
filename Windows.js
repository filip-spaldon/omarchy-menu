// Open windows for the Windows tab, All's Windows section and the running
// marker in Apps: the client list Hyprland reports, made safe to show,
// grouped by workspace, filtered by the query and matched to applications.
// Pure data in, data out -- nothing here touches QML -- so it runs under
// node. Reading the list and focusing a window live in WindowsController.qml.
//
// Written in ES2015+ (const/let, arrows, Map). Quickshell's engine supports
// it, with one exception worth knowing: object rest/spread (`{ ...rest }`,
// ES2018) does not parse, and one syntax error unloads the whole module.

// Hyprland addresses are hex pointers ("0xaaab131000f0"). Anything else is
// not a window this module will hand to a dispatcher.
const ADDRESS_PATTERN = /^0x[0-9a-fA-F]{1,16}$/

// Past this many the list is noise rather than a switcher, and the client
// JSON is bounded anyway.
const MAX_WINDOWS = 200
const MAX_CLASS_LENGTH = 256
const MAX_TITLE_LENGTH = 512
const MAX_WORKSPACE_NAME_LENGTH = 128

const SPECIAL_WORKSPACE_PREFIX = "special:"
// The special workspace SUPER + S toggles.
const SCRATCHPAD_NAME = "scratchpad"
// Shown for a window whose application has no icon to borrow.
const FALLBACK_WINDOW_ICON = "󰖯"

// How well a window matches the query; lower sorts first.
const MatchRank = Object.freeze({
  NO_MATCH: -1,
  // The app name or title starts with the query. Without a query every
  // window ranks here, so the list keeps its workspace order.
  PREFIX: 0,
  // The app name or title contains the query.
  SUBSTRING: 1,
  // Every word is found, but across the class and workspace as well.
  OTHER_FIELD: 2
})

// ------------------------------------------------------------ parsing ----

function isAddress(value) {
  return ADDRESS_PATTERN.test(String(value || ""))
}

function boundedString(value, maxLength) {
  const text = value === null || value === undefined ? "" : String(value)
  return text.slice(0, maxLength)
}

// Unmapped and hidden clients (a window being torn down, a background tab of
// a group) are not windows anyone can switch to.
function isSwitchableClient(client) {
  return !!client && typeof client === "object"
    && isAddress(client.address)
    && client.mapped !== false
    && client.hidden !== true
}

function toOpenWindow(client) {
  const workspace = client.workspace && typeof client.workspace === "object" ? client.workspace : {}
  const workspaceName = boundedString(workspace.name, MAX_WORKSPACE_NAME_LENGTH)
  const workspaceId = Number.isFinite(Number(workspace.id)) ? Number(workspace.id) : 0
  const focusHistoryId = Number(client.focusHistoryID)
  return {
    address: String(client.address),
    windowClass: boundedString(client.class || client.initialClass, MAX_CLASS_LENGTH),
    title: boundedString(client.title || client.initialTitle, MAX_TITLE_LENGTH),
    workspaceId: workspaceId,
    workspaceName: workspaceName,
    // Special workspaces have negative ids and "special:<name>" names.
    isSpecialWorkspace: workspaceName.startsWith(SPECIAL_WORKSPACE_PREFIX) || workspaceId < 0,
    isFloating: client.floating === true,
    // Hyprland's focusHistoryID: 0 is the window focused last. A window
    // without one sorts after every window that has one.
    focusRecency: Number.isFinite(focusHistoryId) ? focusHistoryId : MAX_WINDOWS
  }
}

// `hyprctl -j clients` output to the windows worth listing, each shaped by
// toOpenWindow. Malformed input is an empty list, never an exception.
function parseClients(json) {
  let clients
  try {
    clients = JSON.parse(String(json || ""))
  } catch (error) {
    return []
  }
  if (!Array.isArray(clients)) return []
  return clients.filter(isSwitchableClient).slice(0, MAX_WINDOWS).map(toOpenWindow)
}

// --------------------------------------------------------- workspaces ----

// "special:music" -> "music"; "" for the unnamed special workspace.
function specialWorkspaceName(openWindow) {
  const name = openWindow.workspaceName
  return name.startsWith(SPECIAL_WORKSPACE_PREFIX) ? name.slice(SPECIAL_WORKSPACE_PREFIX.length) : name
}

function isOnScratchpad(openWindow) {
  if (!openWindow.isSpecialWorkspace) return false
  const name = specialWorkspaceName(openWindow)
  return name === "" || name === SCRATCHPAD_NAME
}

// What a workspace is called in full: "2", "Scratchpad", "music (special)".
function workspaceLabel(openWindow) {
  if (isOnScratchpad(openWindow)) return "Scratchpad"
  if (openWindow.isSpecialWorkspace) return `${specialWorkspaceName(openWindow)} (special)`
  return openWindow.workspaceName || String(openWindow.workspaceId)
}

// The short form for a row's right-hand column: "ws 2", "scratch", "music".
function workspaceTrail(openWindow) {
  if (isOnScratchpad(openWindow)) return "scratch"
  if (openWindow.isSpecialWorkspace) return specialWorkspaceName(openWindow)
  return `ws ${openWindow.workspaceName || openWindow.workspaceId}`
}

// ------------------------------------------------------------ sorting ----

function compareText(a, b) {
  if (a === b) return 0
  return a < b ? -1 : 1
}

// Most recently focused first.
function compareByRecency(a, b) {
  return a.focusRecency - b.focusRecency || compareText(a.address, b.address)
}

// Regular workspaces in number order, then special ones by name; inside a
// workspace, the most recently focused window first.
function compareByWorkspaceThenRecency(a, b) {
  if (a.isSpecialWorkspace !== b.isSpecialWorkspace) return a.isSpecialWorkspace ? 1 : -1
  const byWorkspace = a.isSpecialWorkspace
    ? compareText(a.workspaceName, b.workspaceName)
    : a.workspaceId - b.workspaceId
  return byWorkspace || compareByRecency(a, b)
}

// ----------------------------------------------------------- matching ----

// Every word of the query has to appear somewhere in the title, the app
// name, the class or the workspace. See MatchRank for the order.
function matchRank(openWindow, appName, query) {
  const needle = String(query || "").trim().toLowerCase()
  if (!needle) return MatchRank.PREFIX

  const title = openWindow.title.toLowerCase()
  const name = String(appName || "").toLowerCase()
  const searchable = [
    title,
    name,
    openWindow.windowClass.toLowerCase(),
    workspaceLabel(openWindow).toLowerCase(),
    workspaceTrail(openWindow).toLowerCase()
  ].join(" ")

  const everyWordFound = needle.split(/\s+/).every(word => searchable.includes(word))
  if (!everyWordFound) return MatchRank.NO_MATCH
  if (name.startsWith(needle) || title.startsWith(needle)) return MatchRank.PREFIX
  if (name.includes(needle) || title.includes(needle)) return MatchRank.SUBSTRING
  return MatchRank.OTHER_FIELD
}

// --------------------------------------------------------------- rows ----

// "Zen Browser · floating". The workspace has its own column; only a special
// workspace other than the scratchpad is also named here, because the
// column has room for its short name alone.
function windowDetail(openWindow, appName) {
  const parts = [appName]
  if (openWindow.isSpecialWorkspace && !isOnScratchpad(openWindow)) parts.push(workspaceLabel(openWindow))
  if (openWindow.isFloating) parts.push("floating")
  return parts.join(" · ")
}

// The menu's row shape (queryRow in Menu.qml). Every field is set on every
// row: a QML ListModel fixes its roles on the first row appended, and a row
// missing one silently loses it.
function toWindowRow(match) {
  const openWindow = match.openWindow
  const appIcon = match.app && match.app.icon ? String(match.app.icon) : ""
  return {
    itemId: `window:${openWindow.address}`,
    disabled: false,
    kind: "window",
    icon: appIcon ? "" : FALLBACK_WINDOW_ICON,
    iconFont: "",
    appIcon: appIcon,
    appId: openWindow.windowClass,
    label: openWindow.title || match.appName || "(untitled)",
    target: openWindow.address,
    detail: windowDetail(openWindow, match.appName),
    path: "",
    childCount: 0,
    action: "",
    provider: "",
    score: match.rank,
    section: "",
    trailText: workspaceTrail(openWindow)
  }
}

// appForClass(windowClass) -> { id, name, icon } of the matching desktop
// entry, or null. Without one, a web app is named by its host and anything
// else by its class.
function windowRows(openWindows, query, appForClass) {
  const hasQuery = String(query || "").trim() !== ""
  const matches = (openWindows || []).map(openWindow => {
    const app = (appForClass && appForClass(openWindow.windowClass)) || null
    const appName = app && app.name
      ? String(app.name)
      : webappHost(openWindow.windowClass) || openWindow.windowClass
    return { openWindow: openWindow, app: app, appName: appName, rank: matchRank(openWindow, appName, query) }
  })
  return matches
    .filter(match => match.rank !== MatchRank.NO_MATCH)
    .sort((a, b) => (hasQuery ? a.rank - b.rank : 0) || compareByWorkspaceThenRecency(a.openWindow, b.openWindow))
    .map(toWindowRow)
}

// ----------------------------------------------------------- web apps ----

// Chromium-family web apps (omarchy-launch-webapp) get a class built from
// the URL: "chrome-app.hey.com__-Default", "chrome-web.whatsapp.com__-Default".
// Their desktop entries often carry no StartupWMClass, so the class alone
// matches nothing; the host is what is left to go on.
const WEBAPP_CLASS_PATTERN = /^(?:chrome|chromium|brave|msedge|vivaldi)-([A-Za-z0-9.-]+)__?.*-[A-Za-z0-9 ]+$/
// Host labels that say nothing about which app it is.
const UNINFORMATIVE_HOST_LABELS = ["www", "app", "web", "m", "mobile"]

function webappHost(windowClass) {
  const match = WEBAPP_CLASS_PATTERN.exec(String(windowClass || ""))
  return match ? match[1].toLowerCase() : ""
}

// Names compared the way people write them: "Music For Programming" and
// "musicforprogramming" are the same app.
function normalizeName(name) {
  return String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
}

// What a web app's desktop entry may be called, normalized, most specific
// first: the host without its TLD run together, then each informative label.
//   "musicforprogramming.net" -> ["musicforprogramming"]
//   "app.hey.com"             -> ["apphey", "hey"]
function webappNameKeys(windowClass) {
  const host = webappHost(windowClass)
  if (!host) return []
  const labels = host.split(".")
  const labelsWithoutTld = labels.length > 1 ? labels.slice(0, -1) : labels
  const wholeHost = normalizeName(labelsWithoutTld.join(""))
  const informativeLabels = labelsWithoutTld
    .map(normalizeName)
    .filter(label => label.length > 1 && !UNINFORMATIVE_HOST_LABELS.includes(label))
  const keys = [wholeHost, ...informativeLabels].filter(key => key !== "")
  return keys.filter((key, index) => keys.indexOf(key) === index)
}

// ------------------------------------------------------- running apps ----

// Which applications have windows open: desktop entry id -> addresses, most
// recently focused first, so the first address is the window to switch to.
// appIdForClass(windowClass) is the matching entry's id, or "" when none
// matches (that window marks no application).
function windowsByAppId(openWindows, appIdForClass) {
  const byAppId = new Map()
  const byRecency = (openWindows || []).slice().sort(compareByRecency)
  for (const openWindow of byRecency) {
    const appId = appIdForClass ? String(appIdForClass(openWindow.windowClass) || "") : ""
    if (!appId) continue
    if (!byAppId.has(appId)) byAppId.set(appId, [])
    byAppId.get(appId).push(openWindow.address)
  }
  return byAppId
}

// The right-hand text of a running application's row.
function runningLabel(windowCount) {
  if (!(windowCount > 0)) return ""
  return windowCount === 1 ? "running" : `${windowCount} windows`
}

// ----------------------------------------------------------- focusing ----

// Focusing a window on a hidden workspace (or the scratchpad) brings that
// workspace up. Lua-config Hyprland takes hl.dsp.focus; older builds only
// know focuswindow, so fall back to it as omarchy-launch-or-focus does. The
// address arrives as $1, never spliced into the script.
const FOCUS_SCRIPT = 'hyprctl dispatch "hl.dsp.focus({ window = \\"address:$1\\" })" >/dev/null 2>&1'
  + ' || hyprctl dispatch focuswindow "address:$1" >/dev/null'

// The argv that focuses a window, or null for anything but an address.
function focusCommand(address) {
  if (!isAddress(address)) return null
  return ["bash", "-c", FOCUS_SCRIPT, "omarchy-menu-focus", String(address)]
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_WINDOWS,
    MatchRank,
    isAddress,
    parseClients,
    workspaceLabel,
    workspaceTrail,
    compareByWorkspaceThenRecency,
    matchRank,
    windowRows,
    webappHost,
    webappNameKeys,
    normalizeName,
    windowsByAppId,
    runningLabel,
    focusCommand
  }
}
