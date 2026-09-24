import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Settings.js" as Settings
import "MenuModel.js" as MenuModel
import "Tabs.js" as Tabs
import "FileSearch.js" as FileSearch
import "ai/AiBackend.js" as AiBackend

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    // Re-read here rather than watching the files: a live edit still lands
    // without restarting the shell, and an unchanged file is compared and
    // dropped before anything is rebuilt.
    root.loadMenuSources()

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    root.loadMenuSources()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  // The bytes each source last yielded. Compared before anything is rebuilt so
  // re-reading on open is cheap when nothing was edited.
  property string defaultMenuRaw: ""
  property string userMenuRaw: ""
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  // Launcher tabs. Only the menu proper has them: a dmenu request (emoji,
  // keybindings, anything piping options through omarchy-menu-select) is
  // somebody else's picker and keeps its plain list.
  property string activeTab: "all"
  readonly property bool tabsActive: !root.dmenuActive
  // Command mode: a query that starts with "/" asks for an answer only --
  // `/2+3`, `/100 km to miles`, `/password`, `/shell ls` -- and the list
  // shows the answers alone, with no apps, files or menu entries mixed in.
  // Without the slash the same text is an ordinary search that still puts
  // any answer on top. answerQuery is the text the answer builders read.
  readonly property bool commandMode: root.tabsActive && /^\s*\//.test(root.filterText) && !aiCtl.isAiMode
  readonly property string answerQuery: root.filterText.replace(/^\s*\//, "").trim()
  // Search cursor look, from state.json (SettingsStore.qml).
  property string cursorStyle: "block"
  property bool cursorBlink: true
  // state.json "commandsWithoutSlash": false makes answers (math, units,
  // password, shell, kill, ai...) answer only after "/"; plain text is then
  // purely a search. Default true: plain text also shows any answer on top.
  property bool commandsWithoutSlash: true
  // All with nothing typed is just the search field and the tab chips: the
  // card is a prompt, and picking a tab or typing is what opens it up.
  readonly property bool compact: root.tabsActive && root.activeTab === "all" && !root.filterText.trim()

  // System as two panes, like a settings app: the top-level categories on the
  // left, the highlighted category's items on the right, updating as the
  // left side is browsed. Only while nothing is typed -- a search is a flat,
  // sectioned list as everywhere else. systemPane is where the keyboard is.
  // Typing keeps the panes and moves the selection in the tree to the best
  // matching entry (systemMatches, cycled with Ctrl+Up/Down); only a query
  // that matches no entry -- arithmetic, `shell ...`, a web search -- falls
  // back to the flat list of answers.
  property var systemMatches: []
  property int systemMatchIndex: 0
  readonly property bool systemTwoPane: root.tabsActive && root.activeTab === "system" && !aiCtl.isAiMode && !root.commandMode
    && (!root.filterText.trim() || root.systemMatches.length > 0)
  property string systemPane: "left"
  property int systemCategoryIndex: 0
  readonly property var systemCategories: root.systemTwoPane ? root.systemCategoryRows(root.layoutSerial) : []

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property bool isAiMode: aiCtl.isAiMode

  // Apps as a grid or a list (Ctrl+G), remembered across opens and restarts
  // under the XDG state directory. Not next to this file: the shell watches
  // every plugin directory with inotify and reloads *all* plugins -- bar,
  // panels, widgets -- on any write there, so saving a preference into it
  // looked like the whole shell restarting.
  property string appsView: "list"
  readonly property bool gridActive: root.tabsActive && !root.commandMode && root.activeTab === "apps" && root.appsView === "grid"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.homeDir + "/.local/state")) + "/omarchy-menu-omni"

  // Per-user ordering, also from state.json and hand-editable there:
  //   "tabOrder":    the tabs left to right, e.g. ["all","apps","system","files","folders"]
  //   "allSections": the order of All's result sections, e.g. ["apps","system","files","folders"]
  //   "disabledTabs": tabs switched off, e.g. ["files","folders"]; a disabled
  //                  tab also drops out of All, and if All itself is off,
  //                  SUPER + SPACE opens the first tab that is on
  // Unknown ids are ignored and missing ones appended, so an ordering edit
  // can reorder but never hide a tab -- only disabledTabs does that. The file
  // is re-read on every open.
  property var tabOrder: Tabs.DEFAULT_TAB_ORDER
  property var allSectionOrder: Tabs.DEFAULT_ALL_SECTIONS
  property var disabledTabs: []
  readonly property var orderedTabs: Tabs.visibleTabs(root.tabOrder, root.disabledTabs, root.activeTab)

  function tabEnabled(id) {
    return root.disabledTabs.indexOf(id) < 0
  }

  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: {
    if (opened) return
    deleteConfirmOpen = false
    deleteTarget = null
    answerEngine.utilityAnswers = ({})
    fileCtl.cancelFileSearch()
    aiCtl.aiCancel()
    aiCtl.aiSession = AiBackend.snapshot()
    fileCtl.fileResults = []
    fileCtl.fileResultsKey = ""
    fileCtl.fileResultsScope = ""
  }




  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  // --- Look ------------------------------------------------------------------
  // The dials this fork adds on top of the stock geometry. Everything below
  // derives from them, so a redesign is an edit here rather than a hunt
  // through the delegate. They are deliberately not themed: the shell's own
  // `Style` tokens are shared with the bar and every panel, and resizing the
  // menu should not resize those.
  //
  //   menuFontScale        multiplies every text and icon size in the card
  //   menuHeightFraction   most of the screen a dmenu picker's list may take
  //   launcherCardWidth    launcher width, in Style.space() units
  //   launcherBodyFraction launcher results area, as a share of the screen
  //   launcherTopFraction  where the launcher's top edge sits on the screen
  //
  // The launcher (every non-dmenu open) is a fixed-size card, so switching
  // tabs or typing never makes it jump; only the compact All prompt is
  // shorter.
  //
  // All of them come from style.json next to state.json (SettingsStore.qml),
  // re-read on every open; the values here are the fallbacks (styleDefaults there).
  property real menuFontScale: 1.0
  property real menuHeightFraction: 0.7
  property int launcherCardWidth: 560
  property real launcherBodyFraction: 0.6
  // < 0 centres the card, as the stock menu does; >= 0 pins its top edge.
  property real launcherTopFraction: 0.2
  // false: the results area fits its rows (up to launcherBodyFraction), as the
  // stock menu does; true: it always takes launcherBodyFraction, so the card
  // never changes size while typing or switching tabs.
  property bool launcherFixedHeight: false

  // Row height follows the font: the stock minimums (50 and 58) were sized for
  // full-size text and would otherwise hold the rows tall while the labels
  // shrank inside them, which reads as padding rather than a smaller menu.
  readonly property int menuRowFloor: Math.round(Style.space(50) * root.menuFontScale)
  readonly property int menuDetailRowFloor: Math.round(Style.space(58) * root.menuFontScale)

  // The icon column keeps its proportion to the glyph rather than staying at
  // the stock 36: a shrunken icon in a full-width slot leaves the labels
  // floating away from the edge.
  readonly property int iconSlotWidth: Math.round(Style.space(36) * root.menuFontScale)

  // Rows kept off the root list. Applications have their own binding
  // (SUPER + ALT + SPACE) and the submenu still opens by route, so the row was
  // only taking the first line of every visit to the root menu.
  //
  // Done here rather than with `"apps": {"when": "false"}` in the user JSONC:
  // that merge copies every field of the override, so an entry restating only
  // `when` blanks the label, icon, aliases and -- fatally -- the `apps`
  // provider, and restating them all freezes a packaged row that updates would
  // otherwise keep current.
  readonly property var rootHiddenIds: ["apps"]

  function hiddenFromList(entry) {
    return !!entry && root.rootHiddenIds.indexOf(entry.id) >= 0
  }

  // Applications live in the Apps tab (and the Apps section of All), so the
  // System tab is the menu without them: neither the Apps row nor any app.
  function isAppEntry(entry) {
    return !!entry && (entry.kind === "app" || entry.id === "apps")
  }

  readonly property int sectionHeaderHeight: root.scaledFont(Style.font.caption) + Style.space(14)

  // The key hints under the results, for what the current tab can do.
  function footerHints() {
    if (root.commandMode) return root.answerQuery ? "Answers only · Enter use · Ctrl+R new value · Esc clear"
                                                  : "Type a command after / · Esc clear"
    if (root.activeTab === "apps")
      return "Enter launch · Ctrl+G " + (root.appsView === "grid" ? "list" : "grid") + " · Del uninstall · Tab next tab · Esc close"
    if (root.activeTab === "files" || root.activeTab === "folders")
      return "Enter open · Alt+Enter folder · Ctrl+C copy path · Ctrl+T terminal\nCtrl+F type · Ctrl+S sort · Ctrl+L limit · Tab next tab · Esc close"
    if (root.activeTab === "system")
      return root.systemTwoPane
        ? "↑↓ browse · →/Enter open · ← back · type to search · Tab next tab · Esc close"
        : "Enter open · ←/Backspace back · Tab next tab · Esc close"
    return "↑↓ move · Enter open · Tab next tab · ai <question> ask AI · Esc close"
  }

  // What the search field says before anything is typed.
  function promptText() {
    if (root.dmenuActive) return root.dmenuPrompt + "…"
    if (root.activeTab === "system") {
      var menu = root.item(root.activeMenu)
      if (menu && root.activeMenu !== "root") return (menu.title || menu.label) + "…"
      return "Search the system menu…"
    }
    if (root.activeTab === "apps") return "Search applications…"
    if (root.activeTab === "files") return "Search files…"
    if (root.activeTab === "folders") return "Search folders…"
    return "Search apps, files, folders and system…"
  }

  function scaledFont(px) {
    return Math.max(1, Math.round(Number(px) * root.menuFontScale))
  }

  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Math.round(Style.space(34) * root.menuFontScale), root.scaledFont(Style.font.title) + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(root.menuRowFloor, root.scaledFont(Style.font.body) + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(root.menuDetailRowFloor, root.scaledFont(Style.font.body) + root.scaledFont(Style.font.caption) + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : Style.space(root.launcherCardWidth), panel.width - Style.gapsOut * 2)
  readonly property int launcherBodyHeight: Math.max(root.baseRowHeight * 3, Math.round(panel.height * root.launcherBodyFraction))
  // A fitted body still takes the full height for the grid and AI answers,
  // whose size is not a row count.
  property int visibleRowsHeight: root.dmenuActive
    ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText)
    : (root.compact ? 0
      : (root.launcherFixedHeight || root.gridActive || aiCtl.isAiMode || root.systemTwoPane
        ? root.launcherBodyHeight
        : Math.min(root.launcherBodyHeight, Math.max(root.baseRowHeight * 3,
            rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)))))
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + tabBar.height
        + (fileBar.visible ? contentSpacing + fileBar.height : 0)
        + (root.compact ? 0 : contentSpacing + visibleRowsHeight)
        + (footer.visible ? contentSpacing + footer.implicitHeight : 0), panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail, kind) {
    // Command hints are a compact, smaller-type list.
    if (kind === "example") return Math.round(root.detailRowHeight * 0.72)
    return root.showsDetail("", detail) ? root.detailRowHeight : root.baseRowHeight
  }

  // The second line under a label: always for dmenu rows and file results
  // (where the folder is half the answer), otherwise only while searching.
  function showsDetail(kind, detail) {
    if (!detail) return false
    if (root.filterText || root.dmenuActive) return true
    return kind === "file" || kind === "folder" || root.activeTab === "files" || root.activeTab === "folders"
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    // (dmenu pickers only: the launcher opens compact, so its starting height
    // would cap every result list at nothing.)
    if (panel.maxRowsHeight >= 0 && !root.tabsActive) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * root.menuHeightFraction))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail, row.kind)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  // ------------------------------------------------------------------
  // Reading files off disk.
  //
  // Every path this shell reads sits somewhere another process can arrange:
  // the user extension under ~/.config, the rate cache under ~/.cache. A
  // pathname is only ever a hint -- checking it and then opening it by name
  // again is two separate resolutions of that hint, and whatever sits at the
  // path can change in between. So the path is resolved exactly once: open
  // first, then every check -- and the read itself -- work off that same
  // descriptor, never the name again.
  //
  // O_NOFOLLOW on the open rejects a symlink at the final component outright,
  // so a swap cannot redirect it to another file. O_NONBLOCK means a FIFO or
  // device planted at the path returns from the open instead of blocking the
  // thread that draws the menu. The fstat that follows reads the open
  // descriptor -- regular file, ours or root's, within the ceiling -- which
  // describes the bytes about to be read rather than whatever the name
  // resolves to by then. timeout remains as the backstop for a descriptor
  // that opened clean but stalls on read, e.g. a hung network mount.
  readonly property int menuFileCeiling: 1048576     // 1 MiB of JSONC
  readonly property int currencyFileCeiling: 262144  // 256 KiB of rates
  readonly property int fileReadDeadline: 5          // seconds

  // perl is a hard dependency of the omarchy package itself, so it is always
  // present -- no fallback path that would reintroduce a weaker read. Path
  // and byte ceiling arrive as argv, never interpolated into a script, so
  // there is no shell and nothing here to quote.
  readonly property string fileReaderProgram: Settings.FILE_READER_PROGRAM

  function readFileCommand(path, maxBytes) {
    return Settings.readFileCommand(path, maxBytes, root.fileReadDeadline)
  }

  // ------------------------------------------------------------------
  // Running helpers.
  //
  // Every helper below writes to a pipe this shell drains on the thread that
  // draws the menu, so each is bounded twice: `timeout` ends one that stalls,
  // and `head -c` ends output that will not stop on its own. Neither bound is
  // optional -- `ps`, `wl-paste`, a provider script and a guard batch are all
  // capable of producing more than there is memory for, and a helper that
  // never exits is a menu that never opens again.
  readonly property int helperDeadline: 10           // seconds
  readonly property int helperOutputCeiling: 262144  // 256 KiB

  function boundedCommand(script, seconds, maxBytes) {
    return ["bash", "-c",
      'timeout ' + (seconds > 0 ? seconds : root.helperDeadline)
      + ' bash -c ' + Util.shellQuote(script)
      + ' | head -c ' + (maxBytes > 0 ? maxBytes : root.helperOutputCeiling)]
  }

  // Providers and guards keep their own exit codes -- both read them to tell a
  // batch that finished from one that was cut off -- so they take the deadline
  // without a pipe, and their ceiling is applied as their output is collected.
  function guardedCommand(script) {
    return ["timeout", "-k", "2", String(root.helperDeadline), "bash", "-lc", script]
  }

  function loadMenuSources() {
    if (!defaultMenuProc.running) {
      defaultMenuProc.command = root.readFileCommand(root.defaultMenuPath, root.menuFileCeiling)
      defaultMenuProc.running = true
    }
    if (!userMenuProc.running) {
      userMenuProc.command = root.readFileCommand(root.userMenuPath, root.menuFileCeiling)
      userMenuProc.running = true
    }
    // Only the fallback list needs these: AppLibrary applies them itself.
    if (root.usingFallbackApps && !appHidesProc.running) {
      appHidesProc.command = root.readFileCommand(root.appHidesPath, root.menuFileCeiling)
      appHidesProc.running = true
    }
  }


  Component.onCompleted: {
    root.loadMenuSources()
    settingsStore.loadStyle()
    settingsStore.loadState()
    aiCtl.loadAiConfig()
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The host only injects `appLibrary` into first-party menus: a cloned menu
  // is third-party, gets a scoped shell, and finds it null, which used to
  // leave the Apps submenu permanently empty. Everything it wrapped is
  // reachable without it -- DesktopEntries is a Quickshell singleton, and
  // launching and removal are the two commands AppLibrary itself runs -- so
  // the list is rebuilt here rather than given up on. The injected library is
  // still preferred when there is one: it also carries the launch OSD and a
  // live icon index this cannot reproduce.
  readonly property bool usingFallbackApps: !root.appLibrary
  readonly property string appHidesPath: omarchyPath + "/default/omarchy/launcher.hides"
  property var fallbackHiddenIds: ({})

  function fallbackEntryName(entry) {
    return String((entry && entry.name) || (entry && entry.id) || "")
  }

  function fallbackEntrySubtext(entry) {
    return String((entry && entry.genericName) || "")
  }

  // Mirrors AppLibrary.sortedEntries("") for the no-query case: NoDisplay and
  // the hidden-id list are dropped, the rest is sorted by name. Rows are
  // wrapped in { entry } so the caller reads both sources the same way.
  function fallbackAppEntries() {
    var values = []
    try {
      values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    } catch (e) {
      console.warn("omarchy.menu: DesktopEntries unavailable:", e)
      return []
    }

    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      if (root.fallbackHiddenIds[String(entry.id || "")] === true) continue
      var name = root.fallbackEntryName(entry)
      if (!name) continue
      rows.push({ entry: entry, key: name.toLowerCase() })
    }

    rows.sort(function(a, b) {
      if (a.key < b.key) return -1
      if (a.key > b.key) return 1
      return 0
    })
    return rows
  }

  // AppLibrary keeps an index of icons installed after this process started,
  // which a plugin cannot rebuild; the themed lookup is what is left.
  function fallbackIconSource(icon) {
    var value = String(icon || "")
    if (!value) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function appIconSource(icon) {
    return root.appLibrary ? root.appLibrary.iconSource(icon) : root.fallbackIconSource(icon)
  }

  // The same command AppLibrary runs: the scope keeps the app out of
  // wayland-wm@.service, and the .desktop suffix is what gtk-launch resolves
  // (ids like org.telegram.desktop break without it).
  function launchApp(appId, label) {
    if (root.appLibrary) { root.appLibrary.launch(appId, label); return }
    var id = String(appId || "")
    if (!id) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  function removeApp(appId, label) {
    if (root.appLibrary) { root.appLibrary.remove(appId, label); return }
    var id = String(appId || "")
    if (!id) return
    Util.execDetached(Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry")
      + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(label || id)))
  }

  function refreshAppIcons() {
    root.refreshAppIcons()
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    var rows = root.appLibrary ? root.appLibrary.sortedEntries("") : root.fallbackAppEntries()
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary ? root.appLibrary.entrySubtext(entry) : root.fallbackEntrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary ? root.appLibrary.entryName(entry) : root.fallbackEntryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = root.guardedCommand(spec.script)
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    // All and Apps search applications; only System is scoped to the submenu
    // it is showing, and only System searches without them.
    var active = "root"
    var wantsApps = root.activeTab === "apps" || (root.activeTab === "all" && root.tabEnabled("apps"))

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue
      // Enumerating every desktop entry for rows the search is about to throw
      // away is the one provider worth skipping.
      if (entry.provider === "apps" && !wantsApps) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  // ------------------------------------------------------------ file search













  function selectedFileRow() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    var row = displayModel.get(root.selectedIndex)
    return row && (row.kind === "file" || row.kind === "folder") ? row : null
  }

  function closeLauncher() {
    applySerial = requestSerial
    opened = false
    filterText = ""
  }

  // gio open honours Terminal=true desktop entries (a TUI editor opens in a
  // terminal) where xdg-open would exec it blind. Argument vectors throughout:
  // a path is never re-parsed by a shell.
  function openPath(path) {
    if (!path) return
    root.closeLauncher()
    Quickshell.execDetached(["gio", "open", path])
  }

  function enclosingDir(row) {
    if (row.kind === "folder") return row.target
    var slash = row.target.lastIndexOf("/")
    return slash > 0 ? row.target.slice(0, slash) : root.homeDir
  }

  function openEnclosingFolder(row) {
    root.openPath(root.enclosingDir(row))
  }

  function copyPath(row) {
    root.closeLauncher()
    Quickshell.execDetached(["wl-copy", "--", row.target])
  }


  function runInTerminal(command) {
    if (!command) return
    root.closeLauncher()
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + root.homeDir, "--",
      "bash", "-lc", 'eval "$1"; exec "${SHELL:-bash}"', "bash", command])
  }

  function openTerminalAt(row) {
    root.closeLauncher()
    // The equals form: xdg-terminal-exec reads "--dir DIR" as a command.
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + root.enclosingDir(row)])
  }

  function toggleAppsView() {
    root.appsView = root.appsView === "grid" ? "list" : "grid"
    settingsStore.saveState()
    Qt.callLater(function() { if (displayModel.count > 0) root.revealCursor() })
  }

  // Arrow keys in the grid: sideways by one tile, up and down by a row.
  // Unlike the list it does not wrap -- off the edge of a grid is nowhere.
  function gridMove(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = 0
    } else {
      root.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, root.selectedIndex + delta))
    }
    root.revealCursor()
  }











  // ------------------------------------------------------ System two panes

  function systemCategoryRows(_serial) {
    var rows = root.systemTabRows("", "root")
    for (var i = 0; i < rows.length; i++) rows[i] = MenuModel.sanitizeRow(rows[i])
    return rows
  }

  // The top-level category an id sits under ("" for root itself).
  function systemCategoryOf(id) {
    var current = String(id || "")
    while (current && current !== "root") {
      var entry = root.item(current)
      if (!entry) return ""
      if (entry.parent === "root") return current
      current = entry.parent
    }
    return ""
  }

  // Line the left pane up with whatever the right pane shows: after a route
  // (`capture` highlights Trigger), after Back, after a drill-down.
  function syncSystemCategory() {
    var categories = root.systemCategories
    var current = root.systemCategoryOf(root.activeMenu)
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].itemId === current) { root.systemCategoryIndex = i; return }
    }
    root.systemCategoryIndex = Math.max(0, Math.min(root.systemCategoryIndex, categories.length - 1))
  }

  function syncSystemCategoryTo(categoryId) {
    var categories = root.systemCategories
    for (var i = 0; i < categories.length; i++)
      if (categories[i].itemId === categoryId) { root.systemCategoryIndex = i; return }
  }

  // Browsing the left pane previews the category on the right. A category
  // that is an action (About) previews nothing; Enter runs it.
  function selectSystemCategory(index) {
    var categories = root.systemCategories
    if (categories.length === 0) return
    index = Math.max(0, Math.min(index, categories.length - 1))
    root.systemCategoryIndex = index
    var row = categories[index]
    var target = row.kind === "link" ? row.target : row.itemId
    root.navStack = []
    if (row.kind === "menu" || row.kind === "link") root.setActiveMenu(target, false)
    else root.setActiveMenu("root", false)
    root.systemPane = "left"
    root.cursorActive = true
    root.selectedIndex = 0
  }

  function enterSystemPanes() {
    if (!root.systemTwoPane || root.systemMatches.length > 0) return
    if (root.activeMenu === "root") {
      root.selectSystemCategory(root.systemCategoryIndex)
    } else {
      root.syncSystemCategory()
      // A route (SUPER + ESCAPE opens `system`, SUPER + CTRL + C `capture`)
      // or a submenu picked from All asked for that menu, so the keyboard
      // goes to its items on the right -- as in the stock menu -- with the
      // category highlighted on the left. Only a menu with nothing to list
      // leaves the keyboard on the left.
      root.systemPane = displayModel.count > 0 ? "right" : "left"
      if (root.systemPane === "right") {
        root.cursorActive = true
        var first = root.nextSelectable(0, 1)
        root.selectedIndex = first >= 0 ? first : 0
        root.revealCursor()
      }
    }
  }

  function activateSystemCategory() {
    var categories = root.systemCategories
    var row = categories[root.systemCategoryIndex]
    if (!row) return
    if (row.kind === "menu" || row.kind === "link") {
      if (displayModel.count === 0) return
      root.systemPane = "right"
      root.cursorActive = true
      root.selectedIndex = root.nextSelectable(0, 1) >= 0 ? root.nextSelectable(0, 1) : 0
      root.revealCursor()
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  // Left from the right pane: up one submenu level, or back to the left pane
  // once at the category itself.
  function systemBack() {
    if (root.activeMenu !== "root" && root.item(root.activeMenu)
        && root.item(root.activeMenu).parent !== "root") {
      root.goBack()
      root.systemPane = "right"
      return
    }
    root.systemPane = "left"
  }

  // Switching tab keeps whatever was typed: the same question, asked of
  // another source. The System tab keeps its place in the menu too.
  function setTab(id) {
    if (!Tabs.isTab(id) || root.dmenuActive) return
    panel.freezeCardTop()
    root.activeTab = id
    root.selectedIndex = 0
    root.cursorActive = true
    // Switching to System by hand starts at the top of the tree, not on
    // whatever was browsed last. (Routes such as `capture` open a specific
    // place and go through openRoute, not here.)
    if (id === "system" && !root.filterText.trim()) {
      root.activeMenu = "root"
      root.navStack = []
      root.systemCategoryIndex = 0
    }
    if (id === "system") Qt.callLater(root.enterSystemPanes)
    root.disarmPointer()
    if (id === "apps") root.loadProviderForMenu("apps")
    if (root.filterText.trim()) root.loadProvidersForSearch()
    root.updateSystemMatches()
    root.rebuildDisplay()
    if (root.systemTwoPane && root.systemMatches.length > 0) root.jumpToSystemMatch(0)
    fileCtl.requestFileSearch()
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  // Some searches answer themselves. They all end up as one row at the top of
  // the list with the same shape, so only the icon, the two lines of text and
  // what Enter does with it are worth writing out each time.
  // What a lone "/" lists: one example per answer, each a row that fills the
  // query when picked, so the commands are discoverable without docs.
  readonly property var commandExamples: [
    { icon: "󰃬", example: "2+3*4", detail: "Calculator", starts: /^[\d.(+\-]|^(sqrt|abs|log|ln|sin|cos|tan|pi)/ },
    { icon: "󰓡", example: "100 km to miles", detail: "Units", starts: /^[\d.]/ },
    { icon: "󰄔", example: "123 eur to usd", detail: "Currency", starts: /^[\d.$€£¥]/ },
    { icon: "󰅐", example: "time in tokyo", detail: "Time zones" },
    { icon: "󰅴", example: "password 24", detail: "Password (Ctrl+R for another)" },
    { icon: "󰅴", example: "uuid", detail: "UUID v4" },
    { icon: "󰅴", example: "epoch", detail: "Unix time, or `epoch 1700000000`" },
    { icon: "󰅴", example: "sha256 text", detail: "SHA-256" },
    { icon: "󰅴", example: "base64 text", detail: "Base64 encode (b64d to decode)" },
    { icon: "󰅴", example: "urlencode a b&c", detail: "URL encode (urldecode to decode)" },
    { icon: "󰚌", example: "kill firefox", detail: "End a process" },
    { icon: "󰖟", example: "github.com", detail: "Open a URL" },
    { icon: "󰆍", example: "shell htop", detail: "Run in a terminal" },
    { icon: "󰚩", example: "ai what is Omarchy?", detail: "Ask an AI agent" }
  ]

  // A hint fits what is typed so far when the typed text is a start of its
  // example ("pa" → "password 24"), its command word starts with the typed
  // one ("sha" → "sha256"), or it opens the way its answers do (a digit for
  // math, units and currency).
  function commandHintMatches(hint, query) {
    var q = String(query || "").toLowerCase()
    if (!q) return true
    var example = hint.example.toLowerCase()
    if (example.indexOf(q) === 0 || q.indexOf(example.split(" ")[0]) === 0) return true
    var word = q.split(/\s+/)[0]
    if (example.split(" ")[0].indexOf(word) === 0) return true
    return !!hint.starts && hint.starts.test(q)
  }

  function commandExampleRows(query) {
    var rows = []
    for (var i = 0; i < root.commandExamples.length; i++) {
      var c = root.commandExamples[i]
      if (!root.commandHintMatches(c, query)) continue
      rows.push(root.queryRow({ id: "example." + i, kind: "example", icon: c.icon,
                                label: "/" + c.example, detail: c.detail, payload: "/" + c.example }))
    }
    return rows
  }

  function queryRow(spec) {
    return {
      itemId: spec.id || (spec.kind + ".result"),
      // A row still waiting on something it needs cannot be acted on, so the
      // cursor steps over it until it can.
      disabled: spec.ready === false,
      kind: spec.kind,
      icon: spec.icon,
      iconFont: "",
      appIcon: "",
      appId: "",
      label: spec.label,
      // Rows that copy or open carry their payload here. The label is written
      // to be read, and it is rarely the exact text that is wanted.
      target: spec.payload || "",
      detail: spec.detail || "",
      path: "",
      childCount: 0,
      action: "",
      provider: "",
      score: -1,
      section: "",
      trailText: spec.trail || ""
    }
  }























  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  // First selectable row at or past `from`, continuing in the direction of
  // travel and wrapping. -1 when every row is disabled, which leaves the menu
  // with no cursor at all rather than one parked on a row Enter won't run.
  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1

    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }

    return -1
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append(MenuModel.sanitizeRow({
        itemId: "dmenu." + i,
        disabled: false,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: "",
        trailText: ""
      }))
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // How many rows each source gets in All before its own tab is the place to
  // look further.
  readonly property int allSectionLimit: 5

  // Menu entries under `scope` matching `query`, best first. Applications are
  // never part of it: they have their own tab and their own section.
  // `markDrilldown` splits direct children from deeper matches with the
  // divider the System tab has always drawn; All sections them itself.
  function systemSearchRows(query, scope, markDrilldown) {
    var currentRows = []
    var drilldownRows = []

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || entry.id === "root") continue
      if (root.isAppEntry(entry)) continue
      if (!root.isDescendantOf(entry.id, scope)) continue
      var score
      if (root.matchesQuery(entry, query)) {
        score = root.searchScore(entry, query)
      } else {
        // "update omarchy": matched along the path, ranked by the terms the
        // entry matched itself, after every direct match.
        var ownTerms = MenuModel.pathMatchTerms(root.items, entry, query, root.isVisible(entry))
        if (ownTerms === null) continue
        score = root.searchScore(entry, ownTerms) + 100000000
      }

      var row = root.displayRow(entry, root.parentPathFor(entry.id), score)
      if (entry.parent === scope) currentRows.push(row)
      else drilldownRows.push(row)
    }

    var searchSort = function(a, b) {
      if (a.score !== b.score) return a.score - b.score
      return a.path.localeCompare(b.path)
    }
    currentRows.sort(searchSort)
    drilldownRows.sort(searchSort)

    if (markDrilldown && currentRows.length > 0 && drilldownRows.length > 0) {
      root.searchDivider = true
      for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
    }
    return currentRows.concat(drilldownRows)
  }

  // The System tab: the menu as it always was, minus applications.
  function systemTabRows(query, active) {
    var rows = []
    if (query) {
      // The launcher's System tab searches the whole menu: with two panes the
      // active menu is merely the category being browsed, not a scope anyone
      // chose. (Without tabs -- never the case here -- the stock submenu
      // scope still applies.)
      var scope = root.tabsActive ? "root" : active
      rows = root.plainAnswerRows(query).concat(root.systemSearchRows(query, scope, true))
      // Nothing in the menu, and nothing that answered itself. Offer to look
      // it up rather than showing the empty state.
      if (rows.length === 0) {
        var fallback = answerEngine.webSearchRow(query)
        if (fallback) rows.push(fallback)
      }
      return rows
    }

    for (var j = 0; j < root.itemOrder.length; j++) {
      var child = root.item(root.itemOrder[j])
      if (!child || child.parent !== active) continue
      if (root.hiddenFromList(child) || root.isAppEntry(child)) continue
      if (!root.isVisible(child)) continue
      rows.push(root.displayRow(child, child.description, child.order))
    }
    return rows
  }

  // The Apps tab: every application, alphabetical, or the matches for the
  // query, best first. DesktopEntries can reorder its values when an
  // application starts, so the order is imposed here rather than inherited.
  function appTabRows(query) {
    var rows = []
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || entry.kind !== "app") continue
      if (query && !root.matchesQuery(entry, query)) continue
      rows.push(root.displayRow(entry, entry.description, query ? root.searchScore(entry, query) : 0))
    }

    rows.sort(function(a, b) {
      if (query && a.score !== b.score) return a.score - b.score
      var aLabel = String(a.label || "").toLowerCase()
      var bLabel = String(b.label || "").toLowerCase()
      if (aLabel !== bLabel) return aLabel < bLabel ? -1 : 1
      return String(a.itemId || "") < String(b.itemId || "") ? -1 : 1
    })
    return rows
  }

  // All: nothing until something is typed, then the answers that computed
  // themselves on top and a section per source under them.
  function allTabRows(query) {
    if (!query) return []

    var sections = []
    var order = Tabs.orderSections(root.allSectionOrder)
    for (var i = 0; i < order.length; i++) {
      var id = order[i].id
      if (!root.tabEnabled(id)) continue
      var sectionRows = id === "apps" ? root.appTabRows(query)
        : id === "files" ? fileCtl.fileSectionRows(false)
        : id === "folders" ? fileCtl.fileSectionRows(true)
        : root.systemSearchRows(query, "root", false)
      sections.push({ title: order[i].title, rows: sectionRows })
    }
    var rows = root.plainAnswerRows(query).concat(Tabs.composeSections(sections, root.allSectionLimit))

    if (rows.length === 0) {
      var fallback = answerEngine.webSearchRow(query)
      if (fallback) rows.push(fallback)
    }
    return rows
  }

  // keepSelection: the list is being rebuilt under an unchanged query (late
  // results, a provider refresh), so the cursor follows its item rather than
  // staying on an index that now holds something else.
  function rebuildDisplay(keepSelection) {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    var previousId = ""
    if (keepSelection && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count)
      previousId = displayModel.get(root.selectedIndex).itemId

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var query = root.filterText.trim()
    root.searchDivider = false

    var rows = []
    // A question for the agent is not also a search: the AI panel takes the
    // card's body, and nothing is looked up until Enter.
    if (aiCtl.isAiMode) rows = []
    // Command mode: the answer once there is one; until then the hints that
    // still fit what is typed.
    else if (root.commandMode) {
      rows = root.answerQuery ? answerEngine.queryRows(root.answerQuery) : []
      if (rows.length === 0) rows = root.commandExampleRows(root.answerQuery)
    }
    // Two panes show the active menu's own entries, never filtered: a search
    // moves the selection instead. A category that is an action (About) has
    // no entries to show, and "root" would otherwise list the categories
    // again on the right.
    else if (root.activeTab === "system" && root.systemTwoPane)
      rows = active === "root" ? [] : root.systemTabRows("", active)
    else if (root.activeTab === "system") rows = root.systemTabRows(query, active)
    else if (root.activeTab === "apps") rows = root.appTabRows(query)
    else if (root.activeTab === "all") rows = root.allTabRows(query)
    else if (root.activeTab === "files" || root.activeTab === "folders") rows = fileCtl.filesTabRows()

    root.showingCommandHints = root.commandMode && rows.length > 0 && rows[0].kind === "example"
    if (root.showingCommandHints) root.cursorActive = false

    // Sanitized here rather than in each builder: this is the one place
    // every row passes through on its way to the ListView.
    for (var k = 0; k < rows.length; k++) displayModel.append(MenuModel.sanitizeRow(rows[k]))
    layoutSerial += 1

    var kept = Tabs.indexOfItem(rows, previousId)
    if (kept >= 0) selectedIndex = kept

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    if (root.gridActive) {
      appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
      return
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  // The examples under a lone "/" are a read-only hint: no cursor, nothing
  // to pick.
  property bool showingCommandHints: false // set by rebuildDisplay

  function select(delta) {
    if (displayModel.count === 0 || root.showingCommandHints) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && !root.commandMode && root.filterText.trim()) root.loadProvidersForSearch()
    root.updateSystemMatches()
    root.rebuildDisplay()
    if (root.systemTwoPane && root.systemMatches.length > 0) root.jumpToSystemMatch(0)
    fileCtl.requestFileSearch()
  }

  // Menu entries matching the query, best first (ids).
  function updateSystemMatches() {
    var query = root.filterText.trim()
    if (!query || !root.tabsActive || root.activeTab !== "system" || aiCtl.isAiMode || root.commandMode) {
      root.systemMatches = []
      root.systemMatchIndex = 0
      return
    }
    var rows = root.systemSearchRows(query, "root", false)
    var ids = []
    for (var i = 0; i < rows.length; i++) ids.push(rows[i].itemId)
    root.systemMatches = ids
    root.systemMatchIndex = 0
  }

  // Put the tree on a match: open the menu it lives in and park the cursor on
  // it, or -- for a top-level category -- highlight it on the left. The query
  // stays; Esc clears it and leaves the tree where it is.
  function jumpToSystemMatch(index) {
    var count = root.systemMatches.length
    if (count === 0) return
    index = ((index % count) + count) % count
    root.systemMatchIndex = index
    var entry = root.item(root.systemMatches[index])
    if (!entry) return
    root.navStack = []
    root.cursorActive = true
    if (entry.parent === "root") {
      root.activeMenu = (entry.kind === "menu") ? entry.id : (entry.kind === "link" ? entry.target : "root")
      root.rebuildDisplay()
      root.syncSystemCategoryTo(entry.id)
      root.systemPane = "left"
      root.selectedIndex = 0
      return
    }
    root.activeMenu = entry.parent
    root.rebuildDisplay()
    root.syncSystemCategory()
    root.systemPane = "right"
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).itemId === entry.id) { root.selectedIndex = i; break }
    }
    root.revealCursor()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.systemMatches = []
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false
    if (root.systemTwoPane) Qt.callLater(root.syncSystemCategory)

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      // A submenu found from All is entered where submenus live, with the
      // left pane lined up on it rather than on whatever was browsed last.
      var fromOtherTab = root.activeTab !== "system"
      if (fromOtherTab) root.activeTab = "system"
      root.setActiveMenu(row.target || row.itemId, !fromOtherTab, fromPointer)
      if (fromOtherTab) root.navStack = []
      if (root.systemTwoPane) root.enterSystemPanes()
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.launchApp(appId, label)
    } else if (row.kind === "example") {
      return // read-only hint
    } else if (row.kind === "shell") {
      root.runInTerminal(row.target)
    } else if (row.kind === "file" || row.kind === "folder") {
      root.openPath(row.target)
    } else if (row.kind === "kill") {
      root.killProcess(row.target)
    } else if (row.kind === "url" || row.kind === "websearch") {
      root.openUrl(row.target)
    } else if (row.kind === "calc" || row.kind === "currency" || row.kind === "unit"
             || row.kind === "util" || row.kind === "time") {
      root.copyToClipboard(row.target || row.label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    root.removeApp(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  // SIGTERM rather than SIGKILL: the point is to close something that has
  // stopped behaving, and letting it clean up after itself is the better
  // default. Anything that ignores it is a job for a terminal.
  function killProcess(pid) {
    if (!pid) return
    applySerial = requestSerial
    opened = false
    filterText = ""
    Util.execDetached("kill " + Util.shellQuote(pid))
  }

  // Read at the moment it is asked for rather than watched in the background:
  // the menu wants the clipboard once, and nothing here should be holding on
  // to whatever was copied. A clipboard with no text in it -- an image, say --
  // makes wl-paste fail, which is the right outcome: nothing is pasted.
  function pasteIntoFilter() {
    if (pasteProc.running) return
    pasteProc.command = root.boundedCommand("wl-paste --no-newline --type text 2>/dev/null", 5, 4096)
    pasteProc.running = true
  }

  // omarchy-launch-browser rather than xdg-open: it resolves the default
  // browser through xdg-settings and focuses the window once it is up.
  //
  // Also carries the "? <query>" search handoff, which is not a URL. Both are
  // a single quoted argument to the browser, so they travel the same way.
  function openUrl(url) {
    if (!url) return
    applySerial = requestSerial
    opened = false
    filterText = ""
    Util.execDetached("omarchy-launch-browser " + Util.shellQuote(url))
  }

  // printf rather than echo so the result lands without a trailing newline,
  // and shellQuote so it lands as text however it was spelled.
  function copyToClipboard(text) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Every Text in this file sets `textFormat: Text.PlainText`. The rows show
  // strings nobody here wrote -- desktop-entry names, process names, clipboard
  // text, JSONC labels, currency codes off the wire -- and the default,
  // AutoText, sniffs a string for markup and renders it as rich text if it
  // finds any. That turns `<img src=http://...>` in an application's Name into
  // an outbound fetch the moment the row is drawn. PlainText is the whole fix;
  // MenuModel.sanitizeRow bounds and control-filters the same strings on the
  // way in.
  ListModel { id: displayModel }






  AiController {
    id: aiCtl
    menu: root
  }

  FileSearchController {
    id: fileCtl
    menu: root
  }

  SettingsStore {
    id: settingsStore
    menu: root
  }

  AnswerEngine {
    id: answerEngine
    menu: root
  }

  // What the controllers reach for through `menu`.
  readonly property var stateData: settingsStore.stateData
  readonly property string aiAgent: aiCtl.aiAgent
  function saveState() { settingsStore.saveState() }
  function requestFileSearch() { fileCtl.requestFileSearch() }
  function queryRows(query) { return root.plainAnswerRows(query) }

  // Answers for a plain (slash-less) search, or none when those are off.
  function plainAnswerRows(query) {
    return root.commandsWithoutSlash ? answerEngine.queryRows(query) : []
  }





  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    var place = Tabs.tabForRoute(id)
    aiCtl.loadAiConfig()
    settingsStore.loadStyle()
    settingsStore.loadState()
    if (place.tab === "all" && !root.tabEnabled("all"))
      place = { tab: Tabs.firstEnabledTab(root.tabOrder, root.disabledTabs), menu: "root" }
    root.activeTab = place.tab
    // Type filters start over with each open, as in omarchy-find; the sort
    // mode and the result limit are preferences and stay.
    fileCtl.fileFilterIndex = 0
    fileCtl.folderFilterIndex = 0
    root.pendingInitialMenu = place.menu
    root.openExistingMenu(place.menu)
    root.systemPane = place.menu === "root" ? "left" : "right"
    if (place.tab === "system") Qt.callLater(root.enterSystemPanes)
    if (place.tab === "apps") root.loadProviderForMenu("apps")
    fileCtl.requestFileSearch()
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (root.showingCommandHints) return
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) {
        // A provider script that never stops printing would otherwise grow
        // this string until the shell runs out of memory. Stop reading and
        // end it; what arrived already is merged as a partial list.
        if (providerProc.collected.length >= root.helperOutputCeiling) {
          if (providerProc.running) providerProc.running = false
          return
        }
        providerProc.collected += data + "\n"
      }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // Without an injected library there is no appsChanged() to listen to, so the
  // entry list is watched directly: installing or removing a package updates
  // an open Apps submenu the same way.
  Connections {
    target: root.usingFallbackApps ? DesktopEntries.applications : null
    function onValuesChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The package-owned hidden-entry list AppLibrary applies. Read through the
  // same guarded reader as the JSONC sources rather than FileView.
  Process {
    id: appHidesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var id = lines[i].trim()
          if (id && id.charAt(0) !== "#") next[id] = true
        }
        root.fallbackHiddenIds = next
        if (root.providersLoaded["apps"]) root.mergeAppRows()
      }
    }
  }

  // The JSONC sources, read through readFileCommand rather than FileView. Both
  // sit in directories somebody can write to -- the user extension especially
  // -- and FileView opens whatever the path resolves to: it follows a symlink
  // out of the directory, blocks forever on a FIFO, and reads a device or a
  // multi-gigabyte file to the end, all on the path that draws the menu.
  //
  // Re-read on every open() instead of watched, and the raw text is compared
  // before anything is rebuilt, so a live edit still takes effect the next
  // time the menu is opened without paying for a guard batch when nothing
  // changed.
  Process {
    id: defaultMenuProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw === root.defaultMenuRaw && root.rowsLoaded) return
        root.defaultMenuRaw = raw
        root.defaultMenuItems = root.parseMenuJsonc(raw)
        root.rebuildItemsFromSources()
      }
    }
  }

  // A missing user extension is the ordinary case, and reads as empty here:
  // the helper exits non-zero and the collector finishes with no text.
  Process {
    id: userMenuProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw === root.userMenuRaw && root.rowsLoaded) return
        root.userMenuRaw = raw
        root.userMenuItems = root.parseMenuJsonc(raw)
        root.rebuildItemsFromSources()
      }
    }
  }



  Process {
    id: pasteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The search field is one line, so newlines and tabs come in as
        // spaces, and a clipboard holding half a file cannot become the whole
        // query.
        var pasted = String(text || "").replace(/\s+/g, " ").trim()
        if (!pasted) return
        if (pasted.length > 512) pasted = pasted.slice(0, 512)

        // Appended, because the caret is always at the end here: "sha256 " and
        // then a paste is a reasonable way to ask.
        root.setFilter(root.filterText + pasted)
      }
    }
  }





  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = root.guardedCommand(script)
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) {
        // Same ceiling as the providers. Ending the process here leaves a
        // non-zero exit status, which onExited already reads as a batch that
        // was cut off -- so the last complete set of guards is kept.
        if (guardProc.collected.length >= root.helperOutputCeiling) {
          if (guardProc.running) guardProc.running = false
          return
        }
        guardProc.collected += data + "\n"
      }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    // The launcher opens at a fixed line near the top, Spotlight-style, so
    // growing from the compact prompt into a full card only ever extends
    // downward. A dmenu picker keeps the centered, freeze-on-type behaviour.
    readonly property int launcherTop: Math.round(height * root.launcherTopFraction)
    readonly property int effectiveCardTop: root.tabsActive && root.launcherTopFraction >= 0
      ? launcherTop
      : (cardTop >= 0 ? cardTop : centeredTop)
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (aiCtl.isAiMode && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            // In AI mode the bar holds agents, not tabs.
            aiCtl.cycleAiAgent(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (aiCtl.isAiMode && (event.modifiers & Qt.ControlModifier)
                     && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + aiCtl.aiAgents.length) {
            aiCtl.setAiAgent(aiCtl.aiAgents[event.key - Qt.Key_1])
            event.accepted = true
          } else if (root.tabsActive && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            // Claimed before anything else: left alone, Tab moves QML focus
            // off the key catcher and the menu stops hearing the keyboard.
            var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            root.setTab(Tabs.cycleTab(root.activeTab, back ? -1 : 1, root.orderedTabs))
            event.accepted = true
          } else if (root.tabsActive && (event.modifiers & Qt.ControlModifier)
                     && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.orderedTabs.length) {
            root.setTab(root.orderedTabs[event.key - Qt.Key_1].id)
            event.accepted = true
          } else if (root.systemTwoPane && root.systemMatches.length > 0
                     && (event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            root.jumpToSystemMatch(root.systemMatchIndex + (event.key === Qt.Key_Down ? 1 : -1))
            event.accepted = true
          } else if (root.systemTwoPane && root.systemPane === "left"
                     && (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                         || event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
              var n = root.systemCategories.length
              if (n > 0) root.selectSystemCategory((root.systemCategoryIndex + (event.key === Qt.Key_Down ? 1 : -1) + n) % n)
            } else {
              root.activateSystemCategory()
            }
            event.accepted = true
          } else if (root.systemTwoPane && root.systemPane === "right"
                     && (event.key === Qt.Key_Left || (event.key === Qt.Key_Backspace && !root.filterText))) {
            root.systemBack()
            event.accepted = true
          } else if (aiCtl.isAiMode && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            if (!event.isAutoRepeat) {
              var aiState = aiCtl.aiSession ? aiCtl.aiSession.state : "idle"
              if (aiState === "idle" || aiState === "error") aiCtl.aiSubmit()
              else if (aiState === "ready") aiCtl.aiHandoff()
            }
            event.accepted = true
          } else if (aiCtl.isAiMode && event.key === Qt.Key_C && event.modifiers === Qt.ControlModifier) {
            aiCtl.aiCopyAnswer()
            event.accepted = true
          } else if (aiCtl.isAiMode && (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                     || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)) {
            var step = (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)
              ? aiPanel.answerFlick.height : aiCtl.aiLineHeight * 2
            var maxY = Math.max(0, aiPanel.answerFlick.contentHeight - aiPanel.answerFlick.height)
            var down = event.key === Qt.Key_Down || event.key === Qt.Key_PageDown
            aiPanel.answerFlick.contentY = down ? Math.min(maxY, aiPanel.answerFlick.contentY + step)
                                          : Math.max(0, aiPanel.answerFlick.contentY - step)
            aiPanel.answerFlick.pinnedToBottom = aiPanel.answerFlick.contentY >= maxY - 4
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && (event.modifiers & Qt.AltModifier) && root.selectedFileRow()) {
            root.openEnclosingFolder(root.selectedFileRow())
            event.accepted = true
          } else if (event.key === Qt.Key_C && event.modifiers === Qt.ControlModifier && root.selectedFileRow()) {
            root.copyPath(root.selectedFileRow())
            event.accepted = true
          } else if (event.key === Qt.Key_T && event.modifiers === Qt.ControlModifier && root.selectedFileRow()) {
            root.openTerminalAt(root.selectedFileRow())
            event.accepted = true
          } else if ((root.activeTab === "files" || root.activeTab === "folders") && root.tabsActive
                     && event.modifiers === Qt.ControlModifier
                     && (event.key === Qt.Key_F || event.key === Qt.Key_S || event.key === Qt.Key_L)) {
            if (event.key === Qt.Key_F) fileCtl.cycleFileFilter()
            else {
              if (event.key === Qt.Key_S) fileCtl.fileSortMode = FileSearch.nextSortMode(fileCtl.fileSortMode)
              else fileCtl.fileDisplayLimit = FileSearch.nextDisplayLimit(fileCtl.fileDisplayLimit)
              root.selectedIndex = 0
              root.rebuildDisplay()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if ((event.key === Qt.Key_V && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))
                     || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
            // Super+V never arrives as Super+V: omarchy binds it to "universal
            // paste", which sends Ctrl+V on to whatever has focus -- layer
            // surfaces like this one included. Ctrl+V is therefore the binding
            // that matters, with Shift+Insert alongside it as the other paste
            // the rest of Linux knows, and Super+V handled directly for anyone
            // running this without that bind.
            root.pasteIntoFilter()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)
                     && answerEngine.regenerateUtility()) {
            // Only claimed when there was something to reroll, so Ctrl+R stays
            // free everywhere else in the menu.
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (root.tabsActive && root.activeTab === "apps" && event.key === Qt.Key_G
                     && event.modifiers === Qt.ControlModifier) {
            root.toggleAppsView()
            event.accepted = true
          } else if (root.gridActive && (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                     || event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            var cols = appGrid.columns
            root.gridMove(event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1
                          : event.key === Qt.Key_Up ? -cols : cols)
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            // Only System has submenus to back out of.
            if (!root.tabsActive || root.activeTab === "system") root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0 && !root.showingCommandHints) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            id: viewToggle
            textFormat: Text.PlainText
            visible: root.tabsActive && root.activeTab === "apps"
            text: root.appsView === "grid" ? "󰕰" : "󰈚"
            color: root.foreground
            opacity: viewToggleMouse.containsMouse ? 0.9 : 0.5
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.iconLarge)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              id: viewToggleMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.toggleAppsView()
                Qt.callLater(function() { keyCatcher.forceActiveFocus() })
              }
            }
          }

          Text {
            id: searchGlyph
            textFormat: Text.PlainText
            visible: root.tabsActive
            text: "󰍉"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.iconLarge)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
          }

          // Terminal-style cursor at the end of the query; with nothing typed
          // it sits on the first letter of the placeholder, as a terminal's
          // does on the first cell. Style and blinking come from state.json:
          // cursorStyle "block" | "beam" | "underline" | "outline" | "none",
          // cursorBlink true | false. It holds solid while typing.
          Item {
            id: searchCursor
            readonly property real textEnd: searchText.x + (root.filterText ? Math.min(searchText.contentWidth, searchText.width) : 0)
            readonly property int cellWidth: Math.max(2, Math.round(searchText.font.pixelSize * 0.55))
            visible: root.opened && root.cursorStyle !== "none"
            width: root.cursorStyle === "beam" ? Math.max(2, Math.round(searchText.font.pixelSize / 8)) : cellWidth
            height: Math.round(searchText.font.pixelSize * 1.15)
            x: root.filterText ? textEnd + 1 : searchText.x
            anchors.verticalCenter: parent.verticalCenter
            // Over the placeholder a filled block stays see-through enough
            // to leave its letter readable.
            opacity: (!root.cursorBlink || cursorBlink.on)
              ? (!root.filterText && (root.cursorStyle === "block") ? 0.5 : 0.85) : 0

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: root.cursorStyle === "underline" ? Math.max(2, Math.round(parent.height / 8)) : parent.height
              color: root.cursorStyle === "outline" ? "transparent" : root.foreground
              border.width: root.cursorStyle === "outline" ? 1 : 0
              border.color: root.foreground
            }

            Timer {
              id: cursorBlink
              property bool on: true
              interval: 530
              repeat: true
              running: searchCursor.visible && root.cursorBlink
              onTriggered: on = !on
            }
            Connections {
              target: root
              function onFilterTextChanged() { cursorBlink.on = true; cursorBlink.restart() }
            }
          }

          Text {
            id: searchText
            textFormat: Text.PlainText
            anchors.left: root.tabsActive ? searchGlyph.right : parent.left
            // Empty: the placeholder starts after the cursor block.
            anchors.leftMargin: root.tabsActive ? Style.space(10) : 0
            anchors.right: viewToggle.visible ? viewToggle.left : parent.right
            anchors.rightMargin: viewToggle.visible ? Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            // Bounded like the rows: the prompt comes from whoever invoked
            // the dmenu, and the title from the JSONC.
            text: MenuModel.sanitizeText(root.filterText || root.promptText())
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.heading)
            elide: Text.ElideRight
          }

        }

        TabBar {
          id: tabBar
          // Hidden in command mode: the tabs choose where to search, and a
          // command does not search.
          visible: root.tabsActive && !root.commandMode
          height: visible ? implicitHeight : 0
          tabs: aiCtl.isAiMode ? aiCtl.aiAgentTabs : root.orderedTabs
          activeTab: aiCtl.isAiMode ? aiCtl.aiAgent : root.activeTab
          fontFamily: root.fontFamily
          foreground: root.foreground
          accent: Color.accent
          fontSize: root.scaledFont(Style.font.body)
          onTabClicked: function(id) {
            if (aiCtl.isAiMode) aiCtl.setAiAgent(id)
            else root.setTab(id)
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }

        Item {
          id: fileBar
          visible: root.tabsActive && !aiCtl.isAiMode && !root.commandMode && (root.activeTab === "files" || root.activeTab === "folders")
          width: parent.width
          height: visible ? fileFilterChips.implicitHeight : 0

          TabBar {
            id: fileFilterChips
            anchors.left: parent.left
            width: parent.width - fileSortLabel.implicitWidth - Style.space(12)
            tabs: FileSearch.filtersFor(root.activeTab).map(function(f) { return { id: f.id, label: f.label, icon: "" } })
            activeTab: fileCtl.fileFilterFor(root.activeTab).id
            fontFamily: root.fontFamily
            foreground: root.foreground
            accent: Color.accent
            fontSize: root.scaledFont(Style.font.caption)
            onTabClicked: function(id) {
              fileCtl.setFileFilter(id)
              Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            }
          }

          Text {
            id: fileSortLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.top: parent.top
            text: (fileCtl.fileSearching ? "searching… · " : "")
              + FileSearch.sortMode(fileCtl.fileSortMode).icon + " " + FileSearch.sortMode(fileCtl.fileSortMode).label
              + " · " + displayModel.count + "/" + fileCtl.fileDisplayLimit
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.caption)
          }
        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight
          visible: height > 0

          AiPanel {
            id: aiPanel
            menu: root
            ai: aiCtl
            anchors.fill: parent
            visible: aiCtl.isAiMode
          }

          AppGrid {
            id: appGrid
            menu: root
            // As wide as the whole columns that fit, and centred: the leftover
            // part of a column sits evenly on both sides instead of all at the
            // right edge.
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(cellWidth, Math.floor(parent.width / cellWidth) * cellWidth)
            visible: root.gridActive && !aiCtl.isAiMode
            model: root.gridActive ? displayModel : null
          }

          // System's left pane: the top-level categories.
          ListView {
            id: systemCategoryList
            visible: root.systemTwoPane
            width: visible ? Math.round(parent.width * 0.34) : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            model: root.systemCategories
            currentIndex: root.systemCategoryIndex

            delegate: SystemCategoryItem { menu: root }
          }

          Rectangle {
            id: systemPaneDivider
            visible: root.systemTwoPane
            width: visible ? Style.spacing.hairline : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: systemCategoryList.right
            anchors.leftMargin: visible ? Style.space(8) : 0
            color: Util.alpha(root.foreground, 0.15)
          }

          // A category that is an action (About) has nothing to preview.
          Text {
            visible: root.systemTwoPane && displayModel.count === 0
            anchors.centerIn: resultList
            textFormat: Text.PlainText
            text: "Enter to open"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.body)
          }

          // Right pane heading: where in the menu the list below is.
          Text {
            id: systemPaneTitle
            visible: root.systemTwoPane
            // Fixed from the font rather than implicitHeight: an elided Text's
            // implicit height depends on its own size, a binding loop.
            height: visible ? root.scaledFont(Style.font.caption) + Style.space(12) : 0
            verticalAlignment: Text.AlignTop
            anchors.top: parent.top
            anchors.left: systemPaneDivider.right
            anchors.leftMargin: visible ? Style.space(12) : 0
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: (root.activeMenu === "root" ? "" : MenuModel.sanitizeText(root.pathFor(root.activeMenu)).toUpperCase())
              + (root.systemMatches.length > 0
                 ? "   ·   MATCH " + (root.systemMatchIndex + 1) + "/" + root.systemMatches.length
                   + (root.systemMatches.length > 1 ? "  CTRL+↑↓" : "")
                 : "")
            color: root.foreground
            opacity: 0.45
            elide: Text.ElideLeft
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.caption)
            font.weight: Font.DemiBold
            font.letterSpacing: 1
          }

          ListView {
            id: resultList
            anchors.top: systemPaneTitle.bottom
            anchors.bottom: parent.bottom
            anchors.left: systemPaneDivider.right
            anchors.leftMargin: root.systemTwoPane ? Style.space(8) : 0
            anchors.right: parent.right
            visible: !root.gridActive && !aiCtl.isAiMode
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section
              readonly property bool isHeader: Tabs.isHeaderSection(section)

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : (isHeader ? root.sectionHeaderHeight : 0)
              visible: section === "drilldown" || isHeader

              Text {
                visible: parent.isHeader
                textFormat: Text.PlainText
                text: Tabs.headerTitle(parent.section).toUpperCase()
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: root.scaledFont(Style.font.caption)
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(10)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(4)
              }

              Rectangle {
                visible: parent.section === "drilldown"
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: ResultRow { menu: root }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input" && !aiCtl.isAiMode && !root.systemTwoPane

            Text {
              textFormat: Text.PlainText
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.displayLarge)
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.commandMode ? "No answer for “" + root.answerQuery + "” · Backspace to / for examples"
                : fileCtl.fileSearching ? "Searching…"
                : (root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet")
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.title)
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Text {
          id: footer
          visible: root.tabsActive && !root.compact && !aiCtl.isAiMode
          width: parent.width
          textFormat: Text.PlainText
          text: root.footerHints()
          color: root.foreground
          opacity: 0.4
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: root.scaledFont(Style.font.caption)
        }
      }
    }
  }
}
