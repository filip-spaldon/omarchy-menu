import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Settings.js" as Settings
import "Roots.js" as Roots
import "FileSearch.js" as FileSearch
import "Tabs.js" as Tabs
import "MenuModel.js" as MenuModel
import "ai/AiAdapters.js" as AiAdapters
import "ai/AiConfig.js" as AiConfig

// Bar button for the launcher. Left click opens a popup, right click the
// menu ("barLeftClick": "menu" in state.json swaps them). The popup holds
// every option the launcher reads from its state directory (state.json,
// style.json and the per-agent entries of ai.json) and, at the bottom, the
// System submenu's actions (lock, screensaver, suspend, logout,
// reboot, shutdown, ...), read from the same JSONC files the menu reads.
//
// The popup edits the files directly; the menu re-reads them on every open.
// Files are read on every popup open through the menu's guarded reader and
// written through a temporary file and a rename. A file that does not parse
// is shown as such and never written over.
Panel {
  id: root
  moduleName: "omarchy-menu-omni"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (homeDir + "/.cache")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (homeDir + "/.local/state")) + "/omarchy-menu-omni"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string stylePath: stateDir + "/style.json"
  readonly property string aiPath: stateDir + "/ai.json"
  readonly property string defaultMenuPath: Quickshell.env("OMARCHY_PATH") + "/default/omarchy/omarchy-menu.jsonc"
  readonly property string userMenuPath: homeDir + "/.config/omarchy/extensions/omarchy-menu.jsonc"

  // Parsed files: {} when missing, null when present but not a JSON object.
  property var stateData: ({})
  property var styleData: ({})
  property var aiData: ({})

  property var defaultMenuItems: []
  property var userMenuItems: []
  property var systemEntries: []
  property var whenResults: ({})
  property var installedAgents: []
  property bool zoxideInstalled: false
  // Roots.parseStatus of the last check, and the root whose removal waits
  // for a second press.
  property var rootStatus: ({})
  property string removeArmed: ""
  property string indexingRoot: ""
  property var indexQueue: []

  property int cursor: -1
  // The options fold away behind one row; the System actions stay open.
  property bool settingsOpen: false
  property bool modelEditing: false
  signal editModelRequested()

  // ---------------------------------------------------------------- values --

  readonly property bool stateValid: stateData !== null
  readonly property bool styleValid: styleData !== null
  readonly property bool aiValid: aiData !== null
  readonly property var st: stateData || ({})
  readonly property var sty: styleData || ({})

  readonly property string appsView: Settings.APPS_VIEWS.indexOf(st.appsView) >= 0 ? st.appsView : "list"
  readonly property var tabOrder: Tabs.normalizeOrder(st.tabOrder, Tabs.DEFAULT_TAB_ORDER)
  readonly property var sectionOrder: Tabs.normalizeOrder(st.allSections, Tabs.DEFAULT_ALL_SECTIONS)
  readonly property var disabledTabs: Tabs.normalizeDisabled(st.disabledTabs)
  readonly property var sectionsOff: Tabs.normalizeSectionsOff(st.allSectionsOff)
  readonly property string cursorStyle: Settings.CURSOR_STYLES.indexOf(st.cursorStyle) >= 0 ? st.cursorStyle : "block"
  readonly property bool cursorBlink: typeof st.cursorBlink === "boolean" ? st.cursorBlink : true
  readonly property bool cursorWhenEmpty: typeof st.cursorWhenEmpty === "boolean" ? st.cursorWhenEmpty : true
  readonly property bool commandsWithoutSlash: typeof st.commandsWithoutSlash === "boolean" ? st.commandsWithoutSlash : true
  // Which click opens the popup; the other opens the launcher.
  readonly property string barLeftClick: Settings.BAR_CLICKS.indexOf(st.barLeftClick) >= 0 ? st.barLeftClick : "settings"
  readonly property var roots: Roots.normalizeRoots(st.searchRoots, homeDir)
  readonly property string zoxideMode: Settings.ZOXIDE_MODES.indexOf(st.zoxide) >= 0 ? st.zoxide : "rank"
  readonly property bool zoxideAdd: typeof st.zoxideAdd === "boolean" ? st.zoxideAdd : true
  readonly property bool fixedHeight: typeof sty.fixedHeight === "boolean" ? sty.fixedHeight : Settings.STYLE_DEFAULTS.fixedHeight

  // The agent the launcher starts on: the remembered pick, else ai.json's
  // agent, else the first installed one (the menu picks it the same way).
  readonly property string aiAgent: {
    var wanted = [String(st.aiAgent || ""), String((aiData || {}).agent || "")]
    for (var i = 0; i < wanted.length; i++) if (installedAgents.indexOf(wanted[i]) >= 0) return wanted[i]
    return installedAgents.length > 0 ? installedAgents[0] : ""
  }
  readonly property string aiModel: agentEntry("models")
  readonly property string aiEffort: agentEntry("efforts")

  function agentEntry(section) {
    var map = aiData && aiData[section]
    var value = map && typeof map === "object" ? map[aiAgent] : ""
    return typeof value === "string" ? value : ""
  }

  function agentLabel(id) {
    var adapter = AiAdapters.get(id)
    return adapter ? adapter.label : id
  }

  function tabIcon(id) {
    for (var i = 0; i < Tabs.TABS.length; i++) if (Tabs.TABS[i].id === id) return Tabs.TABS[i].icon
    return ""
  }

  function percent(v) { return Math.round(v * 100) + " %" }
  function onOff(v) { return v ? "On" : "Off" }
  function capitalize(v) { return v ? v.charAt(0).toUpperCase() + v.slice(1) : "" }

  // ------------------------------------------------------------------ rows --
  // One flat list drives the popup: headers, option rows and the System
  // actions. `adjust` rows take Left/Right (and the ‹ › arrows), `toggle`
  // rows flip on Enter or click, `move` rows reorder with Left/Right.

  // The groups under Settings, in order. One is open at a time.
  readonly property var groups: [
    { id: "bar", label: "Bar button", icon: "󰕮" },
    { id: "launcher", label: "Launcher", icon: "󰍉" },
    { id: "tabs", label: "Tabs", icon: "󰓩" },
    { id: "all", label: "Search in All", icon: "󰈞" },
    { id: "look", label: "Look", icon: "󰏘" },
    { id: "ai", label: "AI", icon: "󰚩" },
    { id: "roots", label: "Search roots", icon: "󰒍" },
    { id: "zoxide", label: "Zoxide", icon: "󰋚" }
  ]
  property string openGroup: ""

  readonly property var rows: {
    var out = []
    function header(text) { out.push({ type: "header", text: text }) }
    function note(text) { out.push({ type: "note", text: text }) }
    function row(r) { r.type = "row"; if (r.enabled === undefined) r.enabled = true; out.push(r) }
    function item(r) { r.indent = true; row(r) }

    row({ key: "settings", label: "Settings", icon: "󰒓", value: settingsOpen ? "⌄" : "›" })
    if (settingsOpen) {
      for (var g = 0; g < groups.length; g++) {
        var group = groups[g]
        var open = openGroup === group.id
        var count = group.id === "roots" && roots.length > 0 ? roots.length + "  " : ""
        row({ key: "group:" + group.id, label: group.label, icon: group.icon, group: true,
              value: count + (open ? "⌄" : "›") })
        if (open) appendGroup(group.id, note, item)
      }
      row({ key: "open:folder", label: "Settings folder", icon: "󰉋", value: "Open" })
    }

    header("SYSTEM")
    for (var e = 0; e < systemEntries.length; e++) {
      var entry = systemEntries[e]
      if (entry.when && whenResults[entry.id] !== true) continue
      row({ key: "system:" + entry.id, label: entry.label, icon: entry.icon, action: entry.action })
    }
    return out
  }

  function appendGroup(id, note, row) {
    if (id === "bar") {
      if (!stateValid) note("state.json is not valid JSON")
      row({ key: "barLeftClick", label: "Left click", value: barLeftClick === "menu" ? "Menu" : "Settings", adjust: true, enabled: stateValid })
      row({ key: "barRightClick", label: "Right click", value: barLeftClick === "menu" ? "Settings" : "Menu", adjust: true, enabled: stateValid })
    } else if (id === "launcher") {
      if (!stateValid) note("state.json is not valid JSON")
      row({ key: "appsView", label: "Apps view", value: capitalize(appsView), adjust: true, enabled: stateValid })
      row({ key: "cursorStyle", label: "Cursor", value: capitalize(cursorStyle), adjust: true, enabled: stateValid })
      row({ key: "cursorBlink", label: "Cursor blink", value: onOff(cursorBlink), toggle: true, enabled: stateValid })
      row({ key: "cursorWhenEmpty", label: "Cursor in empty field", value: onOff(cursorWhenEmpty), toggle: true, enabled: stateValid })
      row({ key: "commandsWithoutSlash", label: "Answers without “/”", value: onOff(commandsWithoutSlash), toggle: true, enabled: stateValid })
    } else if (id === "tabs") {
      note("Enter switches on or off, ← → moves")
      var tabs = Tabs.orderTabs(tabOrder)
      for (var t = 0; t < tabs.length; t++)
        row({ key: "tab:" + tabs[t].id, label: tabs[t].label, icon: tabs[t].icon,
              value: disabledTabs.indexOf(tabs[t].id) >= 0 ? "Off" : "On", toggle: true, move: true, enabled: stateValid })
    } else if (id === "all") {
      note("Enter switches a section on or off, ← → moves")
      var sections = Tabs.orderSections(sectionOrder)
      for (var s = 0; s < sections.length; s++) {
        var tabOff = disabledTabs.indexOf(sections[s].id) >= 0
        row({ key: "section:" + sections[s].id, label: sections[s].title, icon: tabIcon(sections[s].id),
              value: tabOff ? "Tab off" : (sectionsOff.indexOf(sections[s].id) >= 0 ? "Off" : "On"),
              toggle: !tabOff, move: true, enabled: stateValid })
      }
    } else if (id === "look") {
      if (!styleValid) note("style.json is not valid JSON")
      row({ key: "style:fontScale", label: "Text size", value: Settings.styleNumber(sty, "fontScale").toFixed(2) + "×", adjust: true, enabled: styleValid })
      row({ key: "style:cardWidth", label: "Width", value: String(Math.round(Settings.styleNumber(sty, "cardWidth"))), adjust: true, enabled: styleValid })
      row({ key: "style:bodyHeight", label: "Results height", value: percent(Settings.styleNumber(sty, "bodyHeight")), adjust: true, enabled: styleValid })
      row({ key: "style:fixedHeight", label: "Fixed height", value: onOff(fixedHeight), toggle: true, enabled: styleValid })
      var top = Settings.styleTop(sty)
      row({ key: "style:top", label: "Distance from top", value: top < 0 ? "Centred" : percent(top), adjust: true, enabled: styleValid })
      row({ key: "style:pickerHeight", label: "Picker height", value: percent(Settings.styleNumber(sty, "pickerHeight")), adjust: true, enabled: styleValid })
    } else if (id === "ai") {
      if (!aiValid) note("ai.json is not valid JSON")
      row({ key: "ai:agent", label: "Agent", value: aiAgent ? agentLabel(aiAgent) : "None installed", adjust: true,
            enabled: stateValid && installedAgents.length > 1 })
      row({ key: "ai:model", label: "Model", field: true, enabled: aiValid && aiAgent !== "" })
      row({ key: "ai:effort", label: "Effort", value: aiEffort || "CLI default", adjust: true,
            enabled: aiValid && aiAgent !== "" && (Settings.AGENT_EFFORTS[aiAgent] || [""]).length > 1 })
    } else if (id === "roots") {
      note("Mounted folders searched besides your home. Enter on/off · ← → live or index · r reindex · x remove")
      var now = Date.now()
      for (var r = 0; r < roots.length; r++) {
        var rt = roots[r]
        var status = rootStatus[rt.id]
        var value = !rt.enabled ? "Off"
          : indexingRoot === rt.id ? "Indexing…"
          : Roots.cacheLabel(rt.cacheMinutes)
        if (removeArmed === rt.id) value = "x again removes"
        row({ key: "root:" + rt.id, rootId: rt.id, label: rt.label,
              icon: status && Roots.isNetworkFs(status.fsType) ? "󰒍" : "󰉋",
              detail: Roots.describe(rt, status, now), value: value, adjust: true, enabled: stateValid })
      }
      row({ key: "root:add", label: "Add folder…", icon: "󰐕", value: pickProc.running ? "Choosing…" : "Browse", enabled: stateValid })
    } else if (id === "zoxide") {
      note(zoxideInstalled ? "Folders you visit often rank higher" : "zoxide is not installed")
      row({ key: "zoxide:mode", label: "Ranking",
            value: zoxideMode === "off" ? "Off" : zoxideMode === "rank" ? "Boost" : "Boost + results",
            adjust: true, enabled: stateValid && zoxideInstalled })
      row({ key: "zoxide:add", label: "Learn folders opened here", value: onOff(zoxideAdd), toggle: true,
            enabled: stateValid && zoxideInstalled && zoxideMode !== "off" })
    }
  }

  function selectable(index) {
    var r = rows[index]
    return !!r && r.type === "row" && r.enabled
  }

  // Up and Down stop at the ends instead of wrapping around.
  function moveCursor(dy) {
    var i = cursor
    while (true) {
      i += dy
      if (i < 0 || i >= rows.length) return
      if (selectable(i)) { cursor = i; return }
    }
  }

  // The nearest selectable row at or above `index`, else below it.
  function firstSelectableFrom(index) {
    var i = Math.min(index, rows.length - 1)
    for (; i >= 0; i--) if (selectable(i)) { cursor = i; return }
    firstSelectable()
  }

  function firstSelectable() {
    cursor = -1
    moveCursor(1)
  }

  function rowAt(index) { return rows[index] || null }

  // ---------------------------------------------------------------- actions --

  function adjust(r, direction) {
    endFieldEdit()
    if (!r || !r.enabled) return
    var key = r.key
    if (key === "settings") { if (settingsOpen !== direction > 0) activate(r); return }
    if (r.group) { if ((openGroup === key.slice(6)) !== direction > 0) activate(r); return }
    if (r.move) {
      var id = key.slice(key.indexOf(":") + 1)
      if (key.indexOf("tab:") === 0) setState("tabOrder", Settings.moveInOrder(tabOrder, id, direction))
      else setState("allSections", Settings.moveInOrder(sectionOrder, id, direction))
      followRow(key)
      return
    }
    if (r.toggle) { activate(r); return }
    if (!r.adjust) return
    if (key.indexOf("root:") === 0 && r.rootId) {
      updateRoot(r.rootId, function(x) { x.cacheMinutes = Roots.nextCache(x.cacheMinutes, direction); return x })
      return
    }
    if (key === "zoxide:mode") { setState("zoxide", Settings.cycle(Settings.ZOXIDE_MODES, zoxideMode, direction)); return }
    if (key === "barLeftClick" || key === "barRightClick")
      setState("barLeftClick", Settings.cycle(Settings.BAR_CLICKS, barLeftClick, direction))
    else if (key === "appsView") setState("appsView", Settings.cycle(Settings.APPS_VIEWS, appsView, direction))
    else if (key === "cursorStyle") setState("cursorStyle", Settings.cycle(Settings.CURSOR_STYLES, cursorStyle, direction))
    else if (key === "style:top") {
      var top = Settings.stepTop(Settings.styleTop(sty), direction)
      setStyle("top", top < 0 ? "center" : top)
    } else if (key.indexOf("style:") === 0) {
      var name = key.slice(6)
      setStyle(name, Settings.stepNumber(Settings.styleNumber(sty, name), Settings.STYLE_RANGES[name], direction))
    } else if (key === "ai:agent") setState("aiAgent", Settings.cycle(installedAgents, aiAgent, direction))
    else if (key === "ai:effort") setAgentEntry("efforts", Settings.cycle(Settings.AGENT_EFFORTS[aiAgent] || [""], aiEffort, direction))
  }

  // A click elsewhere ends an edit of the model field: otherwise the field
  // keeps the keyboard (hidden, once its group closes) and the arrows stop
  // moving the cursor.
  function endFieldEdit() {
    if (modelEditing) keyCatcher.forceActiveFocus()
  }

  function activate(r) {
    endFieldEdit()
    if (!r || !r.enabled) return
    var key = r.key
    if (key === "settings") {
      settingsOpen = !settingsOpen
      openGroup = ""
      followRow("settings")
    } else if (r.group) {
      var group = key.slice(6)
      openGroup = openGroup === group ? "" : group
      followRow(key)
    } else if (key === "cursorBlink") setState("cursorBlink", !cursorBlink)
    else if (key === "cursorWhenEmpty") setState("cursorWhenEmpty", !cursorWhenEmpty)
    else if (key === "commandsWithoutSlash") setState("commandsWithoutSlash", !commandsWithoutSlash)
    else if (key === "style:fixedHeight") setStyle("fixedHeight", !fixedHeight)
    else if (key === "zoxide:add") setState("zoxideAdd", !zoxideAdd)
    else if (key === "root:add") pickFolders()
    else if (key.indexOf("root:") === 0 && r.rootId)
      updateRoot(r.rootId, function(x) { x.enabled = !x.enabled; return x })
    else if (key.indexOf("section:") === 0) {
      if (r.toggle) setState("allSectionsOff", Settings.toggleListed(sectionsOff, key.slice(8)))
    } else if (key.indexOf("tab:") === 0)
      setState("disabledTabs", Settings.toggleDisabled(disabledTabs, key.slice(4), Tabs.DEFAULT_TAB_ORDER))
    else if (key === "ai:model") root.editModelRequested()
    else if (key === "open:folder") {
      close()
      Quickshell.execDetached(["bash", "-c", 'mkdir -p -- "$1" && exec xdg-open "$1"', "bash", root.stateDir])
    } else if (key.indexOf("system:") === 0) {
      close()
      Util.execDetached(r.action)
    } else if (r.adjust) adjust(r, 1)
  }

  // ---------------------------------------------------------------- roots --

  function updateRoot(id, change) {
    removeArmed = ""
    setState("searchRoots", Roots.updateRoot(st.searchRoots, homeDir, id, change))
    Qt.callLater(refreshRootStatus)
  }

  // x on a root: the first press arms, the second removes (and deletes its
  // index). Anything else in between disarms.
  function removeRoot(r) {
    if (!r || !r.rootId || !r.enabled) return
    if (removeArmed !== r.rootId) { removeArmed = r.rootId; return }
    var id = r.rootId
    removeArmed = ""
    setState("searchRoots", Roots.updateRoot(st.searchRoots, homeDir, id, function() { return null }))
    Quickshell.execDetached(["rm", "-f", "--", Roots.indexPath(cacheHome, id), Roots.indexPath(cacheHome, id) + ".lock"])
    Qt.callLater(function() { root.firstSelectableFrom(root.cursor) })
  }

  function reindexRoot(r) {
    if (!r || !r.rootId) return
    var target = null
    for (var i = 0; i < roots.length; i++) if (roots[i].id === r.rootId) target = roots[i]
    if (!target || !target.enabled || target.cacheMinutes <= 0) return
    if (indexQueue.indexOf(target.id) < 0 && indexingRoot !== target.id) indexQueue = indexQueue.concat([target.id])
    runIndexQueue()
  }

  function runIndexQueue() {
    if (indexProc.running || indexQueue.length === 0) return
    var id = indexQueue[0]
    indexQueue = indexQueue.slice(1)
    for (var i = 0; i < roots.length; i++) {
      if (roots[i].id !== id) continue
      indexingRoot = id
      indexProc.command = Roots.indexCommand(cacheHome, roots[i], FileSearch.EXCLUDES)
      indexProc.running = true
      return
    }
    runIndexQueue()
  }

  function refreshRootStatus() {
    if (statusProc.running || roots.length === 0) return
    statusProc.command = Roots.statusCommand(cacheHome, roots)
    statusProc.running = true
  }

  // The file manager's folder chooser (through the desktop portal) comes up
  // over everything; the popup closes so it cannot hold the keyboard. The
  // chosen folders are added when it returns.
  function pickFolders() {
    if (pickProc.running || !stateValid) return
    close()
    pickProc.command = Roots.pickCommand("Add search roots")
    pickProc.running = true
  }

  function addPicked(text) {
    var picked = Roots.parsePicked(text)
    if (picked.length === 0) return
    var list = st.searchRoots
    for (var i = 0; i < picked.length; i++) list = Roots.addRoot(list, picked[i].path, homeDir, picked[i].fsType)
    setState("searchRoots", list)
    // New indexed roots get their first index now rather than within the
    // launcher's next minute.
    Qt.callLater(function() {
      var queue = root.indexQueue.slice()
      for (var j = 0; j < root.roots.length; j++) {
        var rt = root.roots[j]
        var s = root.rootStatus[rt.id]
        if (rt.cacheMinutes > 0 && (!s || !s.indexedAt) && queue.indexOf(rt.id) < 0) queue.push(rt.id)
      }
      root.indexQueue = queue
      root.runIndexQueue()
      root.refreshRootStatus()
    })
  }

  // Keeps the cursor on a row that moved.
  function followRow(key) {
    Qt.callLater(function() {
      for (var i = 0; i < root.rows.length; i++) if (root.rows[i].key === key) { root.cursor = i; return }
    })
  }

  // Empty clears the agent's entry, so the CLI's own model applies again.
  function saveModel(text) {
    var value = String(text || "").trim()
    if (value !== "" && !Settings.MODEL_PATTERN.test(value)) return false
    setAgentEntry("models", value)
    return true
  }

  // ----------------------------------------------------------------- files --

  function setState(key, value) {
    if (!stateValid) return
    stateData = Settings.withKey(stateData, key, value)
    stateWriter.save(JSON.stringify(stateData, null, 2) + "\n")
  }

  function setStyle(key, value) {
    if (!styleValid) return
    styleData = Settings.withKey(styleData, key, value)
    styleWriter.save(JSON.stringify(styleData, null, 2) + "\n")
  }

  function setAgentEntry(section, value) {
    if (!aiValid || !aiAgent) return
    var map = aiData[section] && typeof aiData[section] === "object" && !Array.isArray(aiData[section]) ? aiData[section] : ({})
    var next = Settings.withKey(map, aiAgent, value === "" ? undefined : value)
    aiData = Settings.withKey(aiData, section, next)
    aiWriter.save(JSON.stringify(aiData, null, 2) + "\n")
  }

  function reload() {
    stateReader.load(root.statePath, Settings.STATE_MAX_BYTES)
    styleReader.load(root.stylePath, 8192)
    aiReader.load(root.aiPath, 16384)
    defaultMenuReader.load(root.defaultMenuPath, 1048576)
    userMenuReader.load(root.userMenuPath, 1048576)
    if (!agentProbe.running) {
      var binaries = []
      for (var i = 0; i < AiConfig.SUPPORTED_AGENTS.length; i++) {
        var adapter = AiAdapters.get(AiConfig.SUPPORTED_AGENTS[i])
        if (adapter && !adapter.disabledReason) binaries.push(adapter.binary)
      }
      binaries.push("zoxide")
      agentProbe.command = ["sh", "-c",
        'for b; do command -v -- "$b" >/dev/null 2>&1 && printf "%s\\n" "$b"; done', "sh"].concat(binaries)
      agentProbe.running = true
    }
  }

  // The System submenu's actions, defaults merged with the user's extension
  // the way the menu merges them; their `when:` guards run once per open.
  function rebuildSystemEntries() {
    var merged = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    var entries = []
    var guarded = ({})
    for (var i = 0; i < merged.itemOrder.length; i++) {
      var entry = merged.items[merged.itemOrder[i]]
      if (!entry || entry.parent !== "system" || entry.kind !== "action") continue
      entries.push({
        id: entry.id,
        label: MenuModel.sanitizeText(entry.label),
        icon: MenuModel.sanitizeText(entry.icon, MenuModel.ICON_CEILING),
        action: entry.action,
        when: entry.when
      })
      if (entry.when) guarded[entry.id] = { when: entry.when }
    }
    root.systemEntries = entries
    var script = MenuModel.guardScript(guarded)
    if (script && !guardProc.running) {
      // Its output is collected whole: capped at 256 KiB, like the menu's.
      guardProc.command = ["bash", "-c", 'timeout -k 2 5 bash -lc "$1" | head -c 262144', "bash", script]
      guardProc.running = true
    }
  }

  Component.onCompleted: reload()

  onOpenedChanged: if (opened) {
    reload()
    removeArmed = ""
    modelEditing = false
    settingsOpen = false
    openGroup = ""
    Qt.callLater(function() {
      root.firstSelectable()
      flick.contentY = 0
      keyCatcher.forceActiveFocus()
    })
  }

  onCursorChanged: {
    var r = rows[cursor]
    if (removeArmed && (!r || r.rootId !== removeArmed)) removeArmed = ""
    Qt.callLater(ensureCursorVisible)
  }

  function ensureCursorVisible() {
    var item = rowRepeater.itemAt(cursor)
    if (!item) return
    var y = item.mapToItem(content, 0, 0).y
    if (y < flick.contentY) flick.contentY = Math.max(0, y - Style.space(28))
    else if (y + item.height > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, y + item.height - flick.height)
  }

  component FileReader: Process {
    id: reader
    signal loaded(string text, bool exists)
    function load(path, maxBytes) {
      if (running) return
      command = Settings.readFileCommand(path, maxBytes, 5)
      running = true
    }
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: function(exitCode) { reader.loaded(out.text, exitCode === 0) }
  }

  // A save asked for while one is being written runs as soon as it ends,
  // with the newest content.
  component FileWriter: Process {
    id: writer
    required property string path
    property string pending: ""
    function save(content) {
      if (running) { pending = content; return }
      command = Settings.writeCommand(root.stateDir, path, content, false)
      running = true
    }
    onExited: {
      if (!pending) return
      var next = pending
      pending = ""
      Qt.callLater(function() { writer.save(next) })
    }
  }

  // A read that fails (missing file, or one the reader refuses) counts as
  // empty: the popup shows defaults and a save creates the file.
  FileReader {
    id: stateReader
    onLoaded: function(text) {
      root.stateData = Settings.parseObject(text)
      if (root.opened) root.refreshRootStatus()
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: root.rootStatus = Roots.parseStatus(statusOut.text || "")
  }

  Process {
    id: indexProc
    onExited: {
      root.indexingRoot = ""
      root.refreshRootStatus()
      root.runIndexQueue()
    }
  }

  // Folder picker output: capped, like every helper's.
  Process {
    id: pickProc
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(exitCode) { if (exitCode === 0) root.addPicked(String(pickOut.text || "").slice(0, 65536)) }
  }
  FileReader { id: styleReader; onLoaded: function(text) { root.styleData = Settings.parseObject(text) } }
  FileReader { id: aiReader; onLoaded: function(text) { root.aiData = Settings.parseObject(text) } }
  FileReader {
    id: defaultMenuReader
    onLoaded: function(text) { root.defaultMenuItems = MenuModel.parseMenuJsonc(text); root.rebuildSystemEntries() }
  }
  FileReader {
    id: userMenuReader
    onLoaded: function(text) { root.userMenuItems = MenuModel.parseMenuJsonc(text); root.rebuildSystemEntries() }
  }

  FileWriter { id: stateWriter; path: root.statePath }
  FileWriter { id: styleWriter; path: root.stylePath }
  FileWriter { id: aiWriter; path: root.aiPath }

  Process {
    id: guardProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = /^([^:]+):w:([01])$/.exec(lines[i].trim())
          if (m) next[m[1]] = m[2] === "1"
        }
        root.whenResults = next
      }
    }
  }

  Process {
    id: agentProbe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = String(text || "").split("\n")
        var agents = []
        for (var i = 0; i < AiConfig.SUPPORTED_AGENTS.length; i++) {
          var adapter = AiAdapters.get(AiConfig.SUPPORTED_AGENTS[i])
          if (adapter && !adapter.disabledReason && found.indexOf(adapter.binary) >= 0) agents.push(adapter.id)
        }
        root.installedAgents = agents
        root.zoxideInstalled = found.indexOf("zoxide") >= 0
      }
    }
  }

  // -------------------------------------------------------------------- UI --

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    text: "\ue900"
    fontFamily: "omarchy"
    // Each monitor's bar has its own button: re-read the click mapping when
    // the pointer arrives, so a change made from another bar applies here.
    onTooltipHoveredChanged: if (tooltipHovered && !root.opened) stateReader.load(root.statePath, Settings.STATE_MAX_BYTES)
    tooltipText: root.barLeftClick === "menu"
      ? "Left click: menu\nRight click: settings and system"
      : "Left click: settings and system\nRight click: menu"
    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.LeftButton && buttonCode !== Qt.RightButton) return
      var popup = (buttonCode === Qt.LeftButton) === (root.barLeftClick === "settings")
      if (popup) root.toggle()
      else {
        root.close()
        Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.modelEditing
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.adjust(root.rowAt(root.cursor), dx)
      }
      onActivateRequested: root.activate(root.rowAt(root.cursor))
      onCloseRequested: root.close()
      onDeleteRequested: root.removeRoot(root.rowAt(root.cursor))
      onTextKey: function(text) { if (text === "r") root.reindexRoot(root.rowAt(root.cursor)) }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: content
          width: flick.width
          spacing: Style.space(4)

          PanelHero {
            width: parent.width
            title: "Omarchy Menu Omni"
            meta: root.settingsOpen ? "Changes apply on the next open" : "Launcher settings and system actions"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "\ue900"
                color: root.foreground
                font.family: "omarchy"
                font.pixelSize: Style.font.display
              }
            }
          }

          // Delegates are kept across changes (the model is only the row
          // count, each reads its row by index): recreating them all on every
          // edit would re-trigger the hover under a resting pointer and throw
          // the cursor to wherever the mouse happens to be.
          Repeater {
            id: rowRepeater
            model: root.rows.length

            delegate: Loader {
              id: rowLoader
              required property int index
              readonly property var modelData: root.rows[index] || ({ type: "note", text: "" })
              width: content.width
              sourceComponent: modelData.type === "header" ? headerComponent
                : modelData.type === "note" ? noteComponent : rowComponent

              Component {
                id: headerComponent
                Column {
                  width: content.width
                  topPadding: rowLoader.index === 0 ? 0 : Style.space(8)
                  spacing: Style.space(2)

                  PanelSeparator { visible: rowLoader.index > 0; foreground: root.foreground }

                  PanelSectionHeader {
                    text: rowLoader.modelData.text
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }
                }
              }

              Component {
                id: noteComponent
                Text {
                  width: content.width
                  leftPadding: Style.spacing.rowPaddingX + Style.space(14)
                  rightPadding: Style.spacing.rowPaddingX
                  topPadding: Style.space(2)
                  bottomPadding: Style.space(2)
                  text: rowLoader.modelData.text
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Component {
                id: rowComponent
                OptionRow { row: rowLoader.modelData; rowIndex: rowLoader.index }
              }
            }
          }
        }
      }
    }
  }

  component OptionRow: CursorSurface {
    id: optionRow

    required property var row
    required property int rowIndex

    width: content.width
    implicitHeight: (optionRow.row.detail || "") !== "" ? Style.space(46) : Style.space(30)
    foreground: root.foreground
    hasCursor: root.cursor === rowIndex && !modelField.activeFocus
    opacity: row.enabled ? 1 : 0.5

    MouseArea {
      anchors.fill: parent
      enabled: optionRow.row.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // Only a pointer that moves takes the cursor: a row sliding under a
      // resting pointer (a group opening above it) does not.
      onPositionChanged: if (root.cursor !== optionRow.rowIndex) root.cursor = optionRow.rowIndex
      onClicked: {
        root.cursor = optionRow.rowIndex
        root.activate(optionRow.row)
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX + (optionRow.row.indent ? Style.space(14) : 0)
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(8)

      Text {
        visible: (optionRow.row.icon || "") !== ""
        text: optionRow.row.icon || ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      Column {
        Layout.fillWidth: !optionRow.row.field
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(1)

        Text {
          width: optionRow.row.field ? implicitWidth : parent.width
          text: optionRow.row.label
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: optionRow.hasCursor
          elide: Text.ElideRight
        }

        Text {
          visible: (optionRow.row.detail || "") !== ""
          width: parent.width
          text: optionRow.row.detail || ""
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      TextField {
        id: modelField
        visible: !!optionRow.row.field
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.aiModel
        placeholderText: "CLI default"
        foreground: root.foreground
        font.family: root.fontFamily
        hasCursor: false
        onActiveFocusChanged: {
          root.modelEditing = activeFocus
          // An edit left without Enter is dropped, not kept on show unsaved.
          if (!activeFocus) text = root.aiModel
        }
        // The row it sits in became another row (a group closed): let go.
        onVisibleChanged: if (!visible && activeFocus) keyCatcher.forceActiveFocus()
        onAccepted: {
          if (!root.saveModel(text)) return
          focus = false
          keyCatcher.forceActiveFocus()
        }
        Keys.onPressed: function(event) {
          if (event.key !== Qt.Key_Escape) return
          text = root.aiModel
          focus = false
          keyCatcher.forceActiveFocus()
          event.accepted = true
        }
        Connections {
          target: root
          enabled: !!optionRow.row.field
          function onEditModelRequested() { modelField.forceActiveFocus() }
        }
      }

      Arrow { row: optionRow.row; rowIndex: optionRow.rowIndex; direction: -1 }

      Text {
        visible: !optionRow.row.field && (optionRow.row.value || "") !== ""
        text: optionRow.row.value || ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignRight
        Layout.maximumWidth: Style.space(200)
        Layout.alignment: Qt.AlignVCenter
      }

      Arrow { row: optionRow.row; rowIndex: optionRow.rowIndex; direction: 1 }
    }

  }

  component Arrow: Text {
    id: arrow
    required property var row
    required property int rowIndex
    required property int direction
    visible: !!(row.adjust || row.move)
    text: direction < 0 ? "‹" : "›"
    color: arrowMouse.containsMouse ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    Layout.alignment: Qt.AlignVCenter

    MouseArea {
      id: arrowMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      enabled: arrow.row.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: if (root.cursor !== arrow.rowIndex) root.cursor = arrow.rowIndex
      onClicked: {
        root.cursor = arrow.rowIndex
        root.adjust(arrow.row, arrow.direction)
      }
    }
  }
}
