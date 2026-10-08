import QtQuick
import Quickshell
import Quickshell.Io
import "Tabs.js" as Tabs
import "Settings.js" as Settings
import "Roots.js" as Roots

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
  property bool stateWritable: false
  property string stateError: ""
  property string styleError: ""
  readonly property string error: stateError || styleError

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
  //   tabSlide      false turns the tab animations off (Settings.tabAnim has
  //                 the opt-in keys that tune them)
  //   top           "center" (stock menu) or a share of the screen, e.g. 0.2
  //   pickerHeight  most of the screen a dmenu picker's list may take
  //   position      opt-in, written by Alt+arrows and the bar popup: the edge
  //                 the card is pinned to and how far from it (see
  //                 Settings.stylePosition); wins over "top" when set
  readonly property var styleDefaults: Settings.STYLE_DEFAULTS

  // Position saves asked for and finished, and what the read in flight saw
  // when it started. A read that began before the last save finished may hold
  // the older position, so it leaves the menu's newer value alone.
  property int positionSaves: 0
  property int positionSavesDone: 0
  property int styleReadSaves: -1

  function savePosition(position) {
    store.positionSaves++
    styleWriteProc.save(Settings.positionPatch(position))
  }

  function loadStyle() {
    if (styleReadProc.running || !styleWatch.stale) return
    styleWatch.beginRead()
    store.styleReadSaves = store.positionSaves === store.positionSavesDone ? store.positionSaves : -1
    styleReadProc.command = store.menu.readFileCommand(store.stylePath, 8192)
    styleReadProc.running = true
  }

  function applyStyle(text, exitCode, exitStatus) {
    var result = Settings.readObject(text, exitCode, exitStatus)
    if (!result.ok) { store.styleError = result.error; return }
    store.styleError = ""
    var style = result.missing ? store.styleDefaults : result.data
    store.menu.menuFontScale = Settings.styleNumber(style, "fontScale")
    store.menu.launcherCardWidth = Math.round(Settings.styleNumber(style, "cardWidth"))
    store.menu.launcherBodyFraction = Settings.styleNumber(style, "bodyHeight")
    store.menu.menuHeightFraction = Settings.styleNumber(style, "pickerHeight")
    store.menu.launcherFixedHeight = typeof style.fixedHeight === "boolean" ? style.fixedHeight : store.styleDefaults.fixedHeight
    store.menu.tabAnim = Settings.tabAnim(style)
    store.menu.moveAnim = Settings.moveAnim(style)
    if (store.styleReadSaves === store.positionSaves) store.menu.launcherPosition = Settings.stylePosition(style)
    if (result.missing) {
      var ops = []
      for (var key in store.styleDefaults) ops = ops.concat(Settings.patch(key, store.styleDefaults[key], true))
      styleWriteProc.save(ops)
    }
  }

  function loadState() {
    if (stateReadProc.running || stateWriteProc.running || stateWriteProc.pending.length || !stateWatch.stale) return
    store.stateWritable = false
    stateWatch.beginRead()
    stateReadProc.command = store.menu.readFileCommand(store.statePath, Settings.STATE_MAX_BYTES)
    stateReadProc.running = true
  }

  // A missing file, or one without the ordering keys, is written back with
  // the defaults filled in: the options are then there to be edited.
  function applyState(text, exitCode, exitStatus) {
    var result = Settings.readObject(text, exitCode, exitStatus)
    store.stateWritable = result.ok
    if (!result.ok) { store.stateError = result.error; return }
    store.stateError = ""
    var state = result.data
    store.stateData = state

    if (state.appsView === "grid" || state.appsView === "list") store.menu.appsView = state.appsView
    store.menu.tabOrder = Tabs.normalizeOrder(state.tabOrder, Tabs.DEFAULT_TAB_ORDER)
    store.menu.allSectionOrder = Tabs.normalizeOrder(state.allSections, Tabs.DEFAULT_ALL_SECTIONS)
    store.menu.disabledTabs = Tabs.normalizeDisabled(state.disabledTabs)
    store.menu.allSectionsOff = Tabs.normalizeSectionsOff(state.allSectionsOff)
    // The tab SUPER + SPACE opens on: "first" (default) or a tab id.
    store.menu.openTab = Settings.OPEN_TABS.indexOf(state.openTab) >= 0 ? state.openTab : "first"
    // Search cursor: "block" (default), "beam", "underline", "outline" or
    // "none"; cursorBlink false keeps it solid.
    store.menu.cursorStyle = Settings.CURSOR_STYLES.indexOf(state.cursorStyle) >= 0 ? state.cursorStyle : "block"
    store.menu.cursorBlink = typeof state.cursorBlink === "boolean" ? state.cursorBlink : true
    store.menu.cursorWhenEmpty = typeof state.cursorWhenEmpty === "boolean" ? state.cursorWhenEmpty : true
    store.menu.commandsWithoutSlash = typeof state.commandsWithoutSlash === "boolean" ? state.commandsWithoutSlash : true
    // Only reassigned when it changed: a new list restarts the roots' status
    // check and search.
    var roots = Roots.normalizeRoots(state.searchRoots, store.menu.homeDir)
    if (JSON.stringify(roots) !== JSON.stringify(store.menu.searchRoots)) store.menu.searchRoots = roots
    store.menu.zoxideMode = Settings.ZOXIDE_MODES.indexOf(state.zoxide) >= 0 ? state.zoxide : "rank"
    store.menu.zoxideAdd = typeof state.zoxideAdd === "boolean" ? state.zoxideAdd : true

    // Read after the launcher opened (it re-reads on every open). A bare
    // summon picked its tab from the last read: re-pick it from this one,
    // unless the user already switched tab or typed. Otherwise, if All was
    // just switched off, move on to the first tab that is on.
    var openTab = Tabs.openTabFor(store.menu.openTab, store.menu.tabOrder, store.menu.disabledTabs)
    var live = store.menu.opened && store.menu.tabsActive
    if (live && store.menu.openTabPending && !store.menu.filterText && store.menu.activeTab !== openTab)
      store.menu.setTab(openTab)
    else if (live && store.menu.activeTab === "all" && !store.menu.tabEnabled("all"))
      store.menu.setTab(Tabs.firstEnabledTab(store.menu.tabOrder, store.menu.disabledTabs))
    else if (store.menu.opened) {
      store.menu.rebuildDisplay(true)
      store.menu.requestFileSearch()
    }

    // Missing keys are filled under the writer's lock.
    var defaults = {
      appsView: store.menu.appsView, tabOrder: store.menu.tabOrder,
      allSections: store.menu.allSectionOrder, disabledTabs: store.menu.disabledTabs,
      allSectionsOff: store.menu.allSectionsOff, openTab: store.menu.openTab,
      cursorStyle: store.menu.cursorStyle,
      cursorBlink: store.menu.cursorBlink, cursorWhenEmpty: store.menu.cursorWhenEmpty,
      commandsWithoutSlash: store.menu.commandsWithoutSlash, searchRoots: [],
      zoxide: store.menu.zoxideMode, zoxideAdd: store.menu.zoxideAdd
    }
    // Wrong-typed keys are replaced by the default, as before; absent ones
    // only filled in.
    var valid = {
      appsView: state.appsView === "grid" || state.appsView === "list",
      tabOrder: Array.isArray(state.tabOrder), allSections: Array.isArray(state.allSections),
      disabledTabs: Array.isArray(state.disabledTabs), allSectionsOff: Array.isArray(state.allSectionsOff),
      openTab: Settings.OPEN_TABS.indexOf(state.openTab) >= 0,
      cursorStyle: Settings.CURSOR_STYLES.indexOf(state.cursorStyle) >= 0,
      cursorBlink: typeof state.cursorBlink === "boolean",
      cursorWhenEmpty: typeof state.cursorWhenEmpty === "boolean",
      commandsWithoutSlash: typeof state.commandsWithoutSlash === "boolean",
      searchRoots: Array.isArray(state.searchRoots),
      zoxide: Settings.ZOXIDE_MODES.indexOf(state.zoxide) >= 0,
      zoxideAdd: typeof state.zoxideAdd === "boolean"
    }
    var ops = []
    for (var key in defaults)
      if (!valid[key]) ops = ops.concat(Settings.patch(key, defaults[key], state[key] === undefined))
    if (ops.length) stateWriteProc.save(ops)
  }

  function saveState(key, value) {
    if (!store.stateWritable) return false
    store.stateData = Settings.withKey(store.stateData, key, value)
    stateWriteProc.save(Settings.patch(key, value))
    return true
  }

  // Only re-read on open when changed (FileWatch has the rules).
  FileWatch { id: styleWatch; path: store.stylePath }
  FileWatch { id: stateWatch; path: store.statePath }

  Process {
    id: styleReadProc
    stdout: StdioCollector { id: styleReadOut; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) styleWatch.readFailed(exitCode)
      store.applyStyle(styleReadOut.text, exitCode, exitStatus)
    }
  }

  Process {
    id: stateReadProc
    stdout: StdioCollector { id: stateReadOut; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) stateWatch.readFailed(exitCode)
      store.applyState(stateReadOut.text, exitCode, exitStatus)
    }
  }

  SettingsWriter {
    id: styleWriteProc
    directory: store.menu.stateDir
    path: store.stylePath
    maxBytes: 8192
    onSaved: store.positionSavesDone = store.positionSaves
    onFailed: function(message) {
      store.positionSavesDone = store.positionSaves
      store.styleError = message
      styleWatch.stale = true
    }
  }

  SettingsWriter {
    id: stateWriteProc
    directory: store.menu.stateDir
    path: store.statePath
    onSaved: function(text) { store.stateData = Settings.parseObject(text) || store.stateData }
    onFailed: function(message) {
      store.stateError = message
      store.stateWritable = false
      stateWatch.stale = true
    }
  }
}
