import QtQuick
import Quickshell
import Quickshell.Io
import "Tabs.js" as Tabs

// Per-user files under the state directory: style.json (the card's
// geometry) and state.json (apps view, tab and section order, disabled
// tabs, the last AI agent). Both are re-read on every open, written through
// a temporary file and a rename, and created with defaults when missing so
// their options are there to edit. The values themselves live on the menu,
// which the bindings read; this only loads, validates and saves them.
Item {
  id: store

  required property var menu

  readonly property string statePath: store.menu.stateDir + "/state.json"

  // Everything the file held when last read, unknown keys included, so a
  // save writes back what it did not change instead of dropping it.
  property var stateData: ({})

  readonly property string stylePath: store.menu.stateDir + "/style.json"

  // style.json: the card's geometry, per user. Missing keys fall back to the
  // defaults below, out-of-range values are ignored, and a file that does not
  // exist yet is written with the defaults so the options are there to edit.
  // The defaults keep the stock menu's full-size text and rows that fit their
  // content, but are wide enough for the tabs to sit on one line and pinned
  // near the top, so the card grows downward instead of re-centring as it
  // fills:
  //   fontScale     every text and icon size (stock menu: 1.0)
  //   cardWidth     launcher width in Style.space() units (stock menu: 300)
  //   bodyHeight    results area, share of the screen height (stock menu: 0.7)
  //   fixedHeight   true keeps the card one size; false fits the rows
  //   top           "center" (stock menu) or a share of the screen, e.g. 0.2
  //   pickerHeight  most of the screen a dmenu picker's list may take
  readonly property var styleDefaults: ({
    fontScale: 1.0, cardWidth: 560, bodyHeight: 0.6, fixedHeight: false, top: 0.2, pickerHeight: 0.7
  })

  function loadStyle() {
    if (styleReadProc.running) return
    styleReadProc.command = store.menu.readFileCommand(store.stylePath, 8192)
    styleReadProc.running = true
  }

  function applyStyle(text, exists) {
    var style = null
    var raw = String(text || "").trim()
    if (raw) {
      try { style = JSON.parse(raw) } catch (e) {
        console.warn("[omarchy-menu-omni] style.json is not valid JSON; using defaults")
      }
    }
    if (!style || typeof style !== "object" || Array.isArray(style)) style = ({})
    var d = store.styleDefaults
    function num(key, min, max) {
      var v = Number(style[key])
      return (style[key] !== undefined && isFinite(v) && v >= min && v <= max) ? v : d[key]
    }
    store.menu.menuFontScale = num("fontScale", 0.5, 2)
    store.menu.launcherCardWidth = Math.round(num("cardWidth", 200, 2000))
    store.menu.launcherBodyFraction = num("bodyHeight", 0.1, 0.95)
    store.menu.menuHeightFraction = num("pickerHeight", 0.1, 0.95)
    store.menu.launcherFixedHeight = typeof style.fixedHeight === "boolean" ? style.fixedHeight : d.fixedHeight
    var top = style.top
    store.menu.launcherTopFraction = (typeof top === "number" && isFinite(top) && top >= 0 && top <= 0.9) ? top : -1
    if (!exists) store.writeStyleDefaults()
  }

  function writeStyleDefaults() {
    if (styleWriteProc.running) return
    styleWriteProc.command = store.stateFileWriteCommand(store.stylePath,
      JSON.stringify(store.styleDefaults, null, 2) + "\n", true)
    styleWriteProc.running = true
  }

  // Writes a file under stateDir (0600, directory created as needed) via a
  // temporary file and a rename, so a crash mid-write cannot leave half a
  // file; the path and the content reach bash as positional arguments,
  // never as script text. keepExisting: only create, never replace (mv -n).
  function stateFileWriteCommand(path, content, keepExisting) {
    var move = keepExisting ? 'mv -n -- "$t" "$2"' : 'mv -f -- "$t" "$2"'
    return ["bash", "-c",
      'umask 077; mkdir -p -- "$1" || exit 1; ' + (keepExisting ? '[ -e "$2" ] && exit 0; ' : '')
        + 't=$(mktemp -- "$2.XXXXXX") || exit 1; printf %s "$3" > "$t" && ' + move + '; rm -f -- "$t"',
      "bash", store.menu.stateDir, path, content]
  }

  function loadState() {
    if (stateReadProc.running) return
    stateReadProc.command = store.menu.readFileCommand(store.statePath, 4096)
    stateReadProc.running = true
  }

  // A missing file, or one without the ordering keys, is written back with
  // the defaults filled in: the options are then there to be edited.
  function applyState(text) {
    var state = null
    var raw = String(text || "").trim()
    if (raw) {
      try { state = JSON.parse(raw) } catch (e) {
        // Leave a file that does not parse alone rather than overwrite what
        // may be a half-finished edit.
        console.warn("[omarchy-menu-omni] state.json is not valid JSON; using defaults")
        return
      }
    }
    if (!state || typeof state !== "object" || Array.isArray(state)) state = ({})
    store.stateData = state

    if (state.appsView === "grid" || state.appsView === "list") store.menu.appsView = state.appsView
    store.menu.tabOrder = Tabs.normalizeOrder(state.tabOrder, Tabs.DEFAULT_TAB_ORDER)
    store.menu.allSectionOrder = Tabs.normalizeOrder(state.allSections, Tabs.DEFAULT_ALL_SECTIONS)
    store.menu.disabledTabs = Tabs.normalizeDisabled(state.disabledTabs)
    // Search cursor: "block" (default), "beam", "underline", "outline" or
    // "none"; cursorBlink false keeps it solid.
    var styles = ["block", "beam", "underline", "outline", "none"]
    store.menu.cursorStyle = styles.indexOf(state.cursorStyle) >= 0 ? state.cursorStyle : "block"
    store.menu.cursorBlink = typeof state.cursorBlink === "boolean" ? state.cursorBlink : true
    store.menu.commandsWithoutSlash = typeof state.commandsWithoutSlash === "boolean" ? state.commandsWithoutSlash : true

    // Read after the launcher opened (it re-reads on every open): if All was
    // just switched off, move on to the first tab that is on.
    if (store.menu.opened && store.menu.tabsActive && store.menu.activeTab === "all" && !store.menu.tabEnabled("all"))
      store.menu.setTab(Tabs.firstEnabledTab(store.menu.tabOrder, store.menu.disabledTabs))
    else if (store.menu.opened) {
      store.menu.rebuildDisplay(true)
      store.menu.requestFileSearch()
    }

    if (!Array.isArray(state.tabOrder) || !Array.isArray(state.allSections)
        || !Array.isArray(state.disabledTabs) || !state.appsView
        || state.cursorStyle === undefined || state.cursorBlink === undefined
        || state.commandsWithoutSlash === undefined) store.saveState()
  }

  // Written to a temporary file and renamed over the old one, so a crash
  // mid-write cannot leave half a file; the path and the JSON reach the
  // shell as positional arguments, never as script text.
  function saveState() {
    if (stateWriteProc.running) {
      store.stateSavePending = true
      return
    }
    var next = ({})
    for (var key in store.stateData) next[key] = store.stateData[key]
    next.appsView = store.menu.appsView
    next.tabOrder = store.menu.tabOrder
    next.allSections = store.menu.allSectionOrder
    next.disabledTabs = store.menu.disabledTabs
    next.cursorStyle = store.menu.cursorStyle
    next.cursorBlink = store.menu.cursorBlink
    next.commandsWithoutSlash = store.menu.commandsWithoutSlash
    if (store.menu.aiAgent) next.aiAgent = store.menu.aiAgent
    store.stateData = next
    stateWriteProc.command = store.stateFileWriteCommand(store.statePath, JSON.stringify(next, null, 2) + "\n", false)
    stateWriteProc.running = true
  }

  Process {
    id: styleReadProc
    stdout: StdioCollector { id: styleReadOut; waitForEnd: true }
    onExited: function(exitCode) { store.applyStyle(styleReadOut.text, exitCode === 0) }
  }

  Process {
    id: stateReadProc
    stdout: StdioCollector { id: stateReadOut; waitForEnd: true }
    onExited: store.applyState(stateReadOut.text)
  }

  Process { id: styleWriteProc }

  // A save asked for while one is being written is not dropped: it runs as
  // soon as the first finishes.
  property bool stateSavePending: false

  Process {
    id: stateWriteProc
    onExited: {
      if (!store.stateSavePending) return
      store.stateSavePending = false
      Qt.callLater(store.saveState)
    }
  }
}
