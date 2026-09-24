// Tab model for the launcher card: which tabs exist, how a summon route picks
// one, and how per-source results are stitched into one sectioned list.
// Pure data in, data out -- nothing here touches QML -- so it runs under node.

// Every tab, in the default order. The order a user sees can be changed in
// state.json ("tabOrder"); see orderTabs.
var TABS = [
  { id: "all", label: "All", icon: "󰍉" },
  { id: "apps", label: "Apps", icon: "󰀻" },
  { id: "system", label: "System", icon: "󰒓" },
  { id: "files", label: "Files", icon: "󰈔" },
  { id: "folders", label: "Folders", icon: "󰉋" }
]

// The sections All shows its results in, in the default order; reorderable
// in state.json ("allSections").
var ALL_SECTIONS = [
  { id: "apps", title: "Apps" },
  { id: "system", title: "System" },
  { id: "files", title: "Files" },
  { id: "folders", title: "Folders" }
]

function ids(list) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(list[i].id)
  return out
}

var DEFAULT_TAB_ORDER = ids(TABS)
var DEFAULT_ALL_SECTIONS = ids(ALL_SECTIONS)

// A user-supplied order made safe to use: unknown or repeated ids dropped,
// and anything left out appended in its default place -- so a typo or an old
// state.json can reorder, but never hide a tab or lose a section.
function normalizeOrder(order, known) {
  var out = []
  var list = Array.isArray(order) ? order : []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i])
    if (known.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
  }
  for (var k = 0; k < known.length; k++) if (out.indexOf(known[k]) < 0) out.push(known[k])
  return out
}

function byOrder(catalog, order) {
  var ordered = normalizeOrder(order, ids(catalog))
  var out = []
  for (var i = 0; i < ordered.length; i++)
    for (var j = 0; j < catalog.length; j++) if (catalog[j].id === ordered[i]) out.push(catalog[j])
  return out
}

function orderTabs(order) {
  return byOrder(TABS, order)
}

function orderSections(order) {
  return byOrder(ALL_SECTIONS, order)
}

// Tabs switched off in state.json ("disabledTabs"): valid ids only. A list
// that would switch every tab off is ignored -- a launcher with no tabs is
// not a setting anyone meant to make.
function normalizeDisabled(list) {
  var known = DEFAULT_TAB_ORDER
  var out = []
  var input = Array.isArray(list) ? list : []
  for (var i = 0; i < input.length; i++) {
    var id = String(input[i])
    if (known.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
  }
  return out.length >= known.length ? [] : out
}

// Sections left out of All's search in state.json ("allSectionsOff"):
// valid section ids only. Unlike disabledTabs every one may be off; All then
// shows only the answers and the web search.
function normalizeSectionsOff(list) {
  var out = []
  var input = Array.isArray(list) ? list : []
  for (var i = 0; i < input.length; i++) {
    var id = String(input[i])
    if (DEFAULT_ALL_SECTIONS.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
  }
  return out
}

// The tabs shown, in the user's order. A disabled tab stays visible only
// while it is the active one: routes other programs open (`capture` lands on
// System, SUPER + ALT + SPACE on Apps) keep working with their tab off.
function visibleTabs(order, disabled, activeTab) {
  var tabs = orderTabs(order)
  var off = normalizeDisabled(disabled)
  var out = []
  for (var i = 0; i < tabs.length; i++)
    if (off.indexOf(tabs[i].id) < 0 || tabs[i].id === activeTab) out.push(tabs[i])
  return out
}

function firstEnabledTab(order, disabled) {
  var tabs = orderTabs(order)
  var off = normalizeDisabled(disabled)
  for (var i = 0; i < tabs.length; i++) if (off.indexOf(tabs[i].id) < 0) return tabs[i].id
  return "all"
}

function tabIndex(id, tabs) {
  var list = tabs || TABS
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return i
  return -1
}

function isTab(id) {
  return tabIndex(id) >= 0
}

// Wraps in both directions, so Shift+Tab from the first tab lands on the last.
// `tabs` is the order on screen; the default order when omitted.
function cycleTab(id, delta, tabs) {
  var list = tabs || TABS
  var index = tabIndex(id, list)
  if (index < 0) index = 0
  var count = list.length
  return list[((index + delta) % count + count) % count].id
}

// A resolved route id to { tab, menu }. The bare summon (SUPER + SPACE) is
// "root" and opens the launcher on All; "apps" (SUPER + ALT + SPACE) opens the
// Apps tab. Every other route -- `capture`, `style.theme`, `system` -- is a
// place in the system menu, so it opens System already drilled into it.
function tabForRoute(id) {
  var route = String(id || "")
  if (!route || route === "root") return { tab: "all", menu: "root" }
  if (route === "apps") return { tab: "apps", menu: "root" }
  return { tab: "system", menu: route }
}

// Section values ride on ListView's own `section` role, so headers cost no
// rows: the cursor, the row count and every index-based helper stay exactly
// as they were. The prefix keeps them apart from the menu's "drilldown"
// divider, which uses the same role.
var HEADER_PREFIX = "hdr:"

function headerSection(title) {
  return HEADER_PREFIX + String(title || "")
}

function isHeaderSection(section) {
  return String(section || "").indexOf(HEADER_PREFIX) === 0
}

function headerTitle(section) {
  return isHeaderSection(section) ? String(section).slice(HEADER_PREFIX.length) : ""
}

// sections: [{ title, rows }] in display order. Empty sections vanish, each
// keeps at most `perSection` rows, and every row is stamped with its header.
// Rows are copied rather than stamped in place: the same row objects may be
// cached by their builders.
function composeSections(sections, perSection) {
  var out = []
  var limit = perSection > 0 ? perSection : Infinity
  for (var s = 0; s < (sections || []).length; s++) {
    var section = sections[s]
    if (!section || !section.rows || section.rows.length === 0) continue
    var header = section.title ? headerSection(section.title) : ""
    for (var r = 0; r < section.rows.length && r < limit; r++) {
      var copy = {}
      var row = section.rows[r]
      for (var key in row) copy[key] = row[key]
      copy.section = header
      out.push(copy)
    }
  }
  return out
}

// Where the row with this id now sits, or -1. Lets a list rebuilt under the
// cursor -- file results landing after the apps did -- keep the cursor on the
// same item instead of the same index.
function indexOfItem(rows, itemId) {
  if (!itemId) return -1
  for (var i = 0; i < (rows || []).length; i++) if (rows[i] && rows[i].itemId === itemId) return i
  return -1
}

if (typeof module !== "undefined") {
  module.exports = {
    TABS: TABS,
    ALL_SECTIONS: ALL_SECTIONS,
    DEFAULT_TAB_ORDER: DEFAULT_TAB_ORDER,
    DEFAULT_ALL_SECTIONS: DEFAULT_ALL_SECTIONS,
    normalizeOrder: normalizeOrder,
    orderTabs: orderTabs,
    orderSections: orderSections,
    normalizeDisabled: normalizeDisabled,
    normalizeSectionsOff: normalizeSectionsOff,
    visibleTabs: visibleTabs,
    firstEnabledTab: firstEnabledTab,
    tabIndex: tabIndex,
    isTab: isTab,
    cycleTab: cycleTab,
    tabForRoute: tabForRoute,
    headerSection: headerSection,
    isHeaderSection: isHeaderSection,
    headerTitle: headerTitle,
    composeSections: composeSections,
    indexOfItem: indexOfItem
  }
}
