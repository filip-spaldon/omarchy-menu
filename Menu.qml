import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

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
  property bool currencyCacheRead: false
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
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null; utilityAnswers = ({}) }
  // Currency conversion typed into the search: "123 eur to usd". The rates
  // behind it are exchangerate-api's free daily snapshot, which needs no key,
  // cached under ~/.cache and refetched about once a day.
  readonly property string currencyRatesUrl: "https://open.er-api.com/v6/latest/EUR"
  readonly property string currencyRatesPath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy/menu-exchange-rates.json"
  property var currencyRates: null
  property bool currencyFetchFailed: false
  property real currencyFetchedAt: 0

  // Randomness for the rows that make some. Math.random is not something to
  // build a password out of, so bytes come from /dev/urandom in bulk and are
  // drawn down from a pool; a row that needs more than is left says so and
  // waits rather than making do with less.
  property var randomPool: []
  property real randomFetchedAt: 0
  // A generated answer must not change while the query that asked for it is
  // still being typed, so each is kept against the query that produced it --
  // and thrown away when the menu closes, so the next one is new.
  property var utilityAnswers: ({})
  // The last `ps` listing, and when it was taken.
  property string processList: ""
  property real processListedAt: 0
  // The system's zone database, borrowed rather than reimplemented: the zone
  // list from timedatectl, and each zone's current offset from `date`. The
  // engine QML runs has no Intl, so the offset is what the clock is built on.
  property var timeZones: []
  property var zoneOffsets: ({})
  property real localZoneOffset: 0

  // Where a search that matched nothing gets offered.
  //
  // By default the engine is not chosen here at all: the query is handed to
  // the browser behind a "?", which is what its own address bar treats as
  // "search with the configured engine". So the menu follows whatever is set
  // in the browser, including a later change to it, and no template here has
  // to be kept in step. Chromium-family browsers understand the prefix from
  // the command line; Firefox does not, and takes the template below instead.
  //
  // Set to false to always use webSearchTemplate.
  readonly property bool webSearchUsesBrowserDefault: true

  // The fallback, and what a `false` above selects. A template rather than a
  // base URL, so swapping engines stays one line however that engine spells
  // its parameters.
  readonly property string webSearchTemplate: "https://duckduckgo.com/?q={query}"
  readonly property string webSearchName: "DuckDuckGo"

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
  // The three dials this fork adds on top of the stock geometry. Everything
  // below derives from them, so a redesign is an edit here rather than a hunt
  // through the delegate. They are deliberately not themed: the shell's own
  // `Style` tokens are shared with the bar and every panel, and shrinking the
  // menu should not shrink those.
  //
  //   menuFontScale      multiplies every text and icon size in the card
  //   menuCardWidth      card width in Style.space() units (stock: 300)
  //   menuHeightFraction most of the screen the row list may take (stock: 0.7)
  readonly property real menuFontScale: 0.85
  readonly property int menuCardWidth: 360
  readonly property real menuHeightFraction: 0.5

  // Row height follows the font: the stock minimums (50 and 58) were sized for
  // full-size text and would otherwise hold the rows tall while the labels
  // shrank inside them, which reads as padding rather than a smaller menu.
  readonly property int menuRowFloor: Math.round(Style.space(50) * root.menuFontScale)
  readonly property int menuDetailRowFloor: Math.round(Style.space(58) * root.menuFontScale)

  // The icon column keeps its proportion to the glyph rather than staying at
  // the stock 36: a shrunken icon in a full-width slot leaves the labels
  // floating away from the edge.
  readonly property int iconSlotWidth: Math.round(Style.space(36) * root.menuFontScale)

  // Apps are their own menu (SUPER + ALT + SPACE) rather than a third of every
  // result list. With hundreds of desktop entries, a search from the root was
  // mostly applications, and the command actually being looked for sat under
  // them. They stay fully searchable once inside the Apps submenu, and the
  // Apps row itself is untouched, so nothing becomes unreachable.
  //
  // Set to true to get the stock behaviour back.
  readonly property bool appsInRootSearch: false

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

  // True for an app row being searched from outside the Apps submenu.
  function hiddenFromSearch(entry) {
    if (root.appsInRootSearch) return false
    if (!entry || entry.kind !== "app") return false
    return !(root.activeMenu === "apps" || root.isDescendantOf(root.activeMenu, "apps"))
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
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(root.menuCardWidth)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

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
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
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
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
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
      total += root.rowHeightForDetail(row.detail)
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
  readonly property string fileReaderProgram: [
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

  function readFileCommand(path, maxBytes) {
    return ["timeout", String(root.fileReadDeadline),
            "perl", "-e", root.fileReaderProgram,
            "--", path, String(maxBytes)]
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

  function loadCurrencyCache() {
    if (currencyCacheProc.running) return
    currencyCacheProc.command = root.readFileCommand(root.currencyRatesPath, root.currencyFileCeiling)
    currencyCacheProc.running = true
  }

  Component.onCompleted: root.loadMenuSources()

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
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue
      // Enumerating every desktop entry for rows the search is about to throw
      // away is the one provider worth skipping.
      if (entry.provider === "apps" && !root.appsInRootSearch
          && !(active === "apps" || root.isDescendantOf(active, "apps"))) continue

      root.loadProviderForMenu(entry.id)
    }
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
      section: ""
    }
  }

  // The self-answering searches, in the order they get asked. Each builder
  // takes the query and returns a row, a list of rows, or null for a query it
  // does not recognise; the first one that recognises it wins.
  //
  // Order settles the overlaps. Arithmetic goes first because it is the
  // strictest grammar. Currency goes before units so that "100 cup to eur" is
  // the Cuban peso, while units still take "2 cup to ml" -- currency declines
  // it, since "ml" is not money.
  function queryRows(query) {
    var builders = [
      root.calculatorRow,
      root.currencyRow,
      root.unitRow,
      root.timeRow,
      root.utilityRow,
      root.urlRow,
      root.killRows
    ]

    for (var i = 0; i < builders.length; i++) {
      var produced = null
      // These parse whatever was typed, and a throw in one of them would
      // otherwise take the whole result list down with it -- the search would
      // go blank rather than lose a row. Log it and carry on without it.
      try {
        produced = builders[i](query)
      } catch (e) {
        console.warn("omarchy.menu: query row builder failed:", e)
        continue
      }

      if (!produced) continue
      var list = (produced instanceof Array) ? produced : [produced]
      if (list.length > 0) return list
    }

    return []
  }

  // A search that reads as arithmetic answers itself. Nothing in the menu
  // matches "2+3", so without this the query that most obviously has an answer
  // is the one that comes back empty; the result leads the list, and Enter
  // copies it, which is the whole of what a calculator is wanted for here.
  function calculatorRow(query) {
    var result = MenuModel.evaluateMath(query)
    if (!result) return null

    return root.queryRow({
      kind: "calc",
      icon: "󰃬",
      label: result,
      detail: "Copy to clipboard"
    })
  }

  // Currency's twin, answered from a table that ships with the plugin: no
  // network, no cache, and an answer on the first keystroke that completes the
  // query. A pair is only a unit conversion when both sides measure the same
  // thing, which is what keeps it from arguing with the currency table.
  function unitRow(query) {
    var parsed = MenuModel.parseUnitQuery(query)
    if (!parsed) return null

    var converted = MenuModel.convertUnit(parsed)
    if (!converted) return null

    var asked = MenuModel.formatMathResult(parsed.amount) + " " + parsed.from.symbol
    // Temperature scales disagree about zero, so there is no ratio between
    // them to show and the row just restates what was asked.
    var detail = converted.rate
      ? asked + " at " + MenuModel.formatUnitValue(converted.rate)
      : asked

    return root.queryRow({
      kind: "unit",
      icon: "󰓡",
      label: MenuModel.formatUnitValue(converted.value) + " " + parsed.to.symbol,
      detail: detail,
      payload: MenuModel.formatUnitValue(converted.value)
    })
  }

  // The small answers a terminal usually gets opened for. A keyword and the
  // rest of the line; the answer leads the list and Enter copies it.
  function utilityRow(query) {
    var parsed = MenuModel.parseUtilityQuery(query)
    if (!parsed) return null

    var answer = root.utilityAnswer(query, parsed)
    if (!answer) return null

    if (answer === "pending") {
      return root.queryRow({
        kind: "util",
        icon: "󰅴",
        label: parsed.keyword,
        detail: "Gathering randomness…",
        ready: false
      })
    }

    return root.queryRow({
      kind: "util",
      icon: "󰅴",
      label: answer.label,
      // A reroll is only discoverable if the row says so.
      detail: root.regenerableQuery() ? answer.detail + " · Ctrl+R for another" : answer.detail,
      payload: answer.copy
    })
  }

  // Keywords whose answer is a fresh draw rather than a function of what was
  // typed. Only these are offered a reroll: running sha256 over the same
  // argument again returns the same digest, and a shortcut that visibly does
  // nothing is worse than no shortcut.
  readonly property var regenerableUtilities: ["uuid", "password", "epoch"]

  // The current query when it is a draw worth repeating, "" otherwise.
  function regenerableQuery() {
    var query = root.filterText.trim()
    if (!query) return ""
    var parsed = MenuModel.parseUtilityQuery(query)
    if (!parsed || root.regenerableUtilities.indexOf(parsed.keyword) < 0) return ""
    // `epoch <value>` reads back the value it was given; only a bare `epoch`
    // is the clock, and worth asking again.
    if (parsed.keyword === "epoch" && parsed.argument) return ""
    return query
  }

  // Forget this query's answer and let the row builder draw another. The map
  // is replaced rather than written into: an in-place write into a QML `var`
  // object is occasionally dropped by the engine.
  function regenerateUtility() {
    var query = root.regenerableQuery()
    if (!query) return false

    var next = ({})
    for (var key in root.utilityAnswers)
      if (key !== query) next[key] = root.utilityAnswers[key]
    root.utilityAnswers = next

    root.rebuildDisplay()
    return true
  }

  function utilityAnswer(query, parsed) {
    if (Object.prototype.hasOwnProperty.call(root.utilityAnswers, query))
      return root.utilityAnswers[query]

    var answer = root.computeUtility(parsed)
    // A row still waiting on /dev/urandom has no answer to remember yet.
    if (answer === "pending") return answer

    root.utilityAnswers[query] = answer
    return answer
  }

  // Returns the answer, "pending" while the randomness for it is still being
  // read, or null for a keyword that was given nothing to work on -- which
  // leaves "base64" on its own an ordinary search.
  function computeUtility(parsed) {
    var argument = parsed.argument
    var keyword = parsed.keyword

    if (keyword === "uuid") {
      if (argument) return null
      if (!root.ensureRandomBytes(16)) return "pending"
      var uuid = MenuModel.uuidFromBytes(root.takeRandomBytes(16))
      return { label: uuid, detail: "Random UUID v4", copy: uuid }
    }

    if (keyword === "password") {
      var length = argument ? parseInt(argument, 10) : 20
      if (!(length > 0)) return null
      length = Math.min(length, 64)
      // Three bytes per character leaves room for the ones rejection sampling
      // throws away, with plenty of margin.
      var needed = length * 3
      if (!root.ensureRandomBytes(needed)) return "pending"
      var password = MenuModel.passwordFromBytes(root.takeRandomBytes(needed), length)
      if (!password) return "pending"
      return { label: password, detail: length + " random characters", copy: password }
    }

    if (keyword === "base64" || keyword === "b64") {
      if (!argument) return null
      var encoded = MenuModel.base64Encode(argument)
      return { label: encoded, detail: "base64 of “" + argument + "”", copy: encoded }
    }

    if (keyword === "b64d" || keyword === "unbase64") {
      if (!argument) return null
      var decoded = MenuModel.base64Decode(argument)
      if (!decoded) return null
      return { label: decoded, detail: "Decoded from base64", copy: decoded }
    }

    if (keyword === "urlencode") {
      if (!argument) return null
      var escaped = encodeURIComponent(argument)
      return { label: escaped, detail: "Percent-encoded", copy: escaped }
    }

    if (keyword === "urldecode") {
      if (!argument) return null
      var unescaped = ""
      try { unescaped = decodeURIComponent(argument) } catch (e) { return null }
      return { label: unescaped, detail: "Percent-decoded", copy: unescaped }
    }

    if (keyword === "sha256") {
      if (!argument) return null
      var digest = MenuModel.sha256Hex(argument)
      return { label: digest, detail: "SHA-256 of “" + argument + "”", copy: digest }
    }

    if (keyword === "epoch") {
      if (!argument) {
        var now = String(Math.floor(Date.now() / 1000))
        return {
          label: now,
          detail: "Seconds since 1970 · " + Qt.formatDateTime(new Date(), "d MMM HH:mm:ss"),
          copy: now
        }
      }
      var milliseconds = MenuModel.epochMilliseconds(argument)
      if (milliseconds === null) return null
      var when = Qt.formatDateTime(new Date(milliseconds), "ddd d MMM yyyy HH:mm:ss")
      return { label: when, detail: "Local time for " + argument, copy: when }
    }

    return null
  }

  // True when the pool can already cover `needed`. When it cannot, one read of
  // /dev/urandom is started and the answer waits for it.
  function ensureRandomBytes(needed) {
    if (root.randomPool.length >= needed) return true
    if (randomProc.running) return false

    var now = Math.floor(Date.now() / 1000)
    // Every keystroke asks, so a read that failed must not be retried by the
    // next character typed.
    if (now - root.randomFetchedAt < 5) return false
    root.randomFetchedAt = now

    randomProc.command = root.boundedCommand("od -An -v -tu1 -N 1024 /dev/urandom", 5, 16384)
    randomProc.running = true
    return false
  }

  function takeRandomBytes(count) {
    if (root.randomPool.length < count) return null

    var taken = root.randomPool.slice(0, count)
    root.randomPool = root.randomPool.slice(count)
    // Top up before the pool is empty, so the next answer does not have to
    // wait on a read that could have happened already.
    if (root.randomPool.length < 256) root.ensureRandomBytes(1024)
    return taken
  }

  // The one search that answers with a list rather than a single row. `ps` is
  // the same answer whoever is asking, so it is run once and filtered here --
  // no listing per keystroke, and none at all until "kill" is typed.
  function killRows(query) {
    var filter = MenuModel.parseKillQuery(query)
    if (filter === null) return null

    root.ensureProcessList()

    if (!root.processList) {
      return [root.queryRow({
        kind: "kill", icon: "󰚌",
        label: filter, detail: "Listing processes…", ready: false
      })]
    }

    var found = MenuModel.parseProcessList(root.processList, filter, 8)
    if (found.length === 0) {
      return [root.queryRow({
        kind: "kill", icon: "󰚌",
        label: filter, detail: "No process by that name", ready: false
      })]
    }

    var rows = []
    for (var i = 0; i < found.length; i++) {
      rows.push(root.queryRow({
        id: "kill." + found[i].pid,
        kind: "kill",
        icon: "󰚌",
        label: found[i].name,
        detail: "pid " + found[i].pid + " · " + found[i].cpu.toFixed(1)
              + "% cpu · " + MenuModel.formatMemory(found[i].rss),
        payload: String(found[i].pid)
      }))
    }

    return rows
  }

  // Held for a few seconds rather than debounced: the listing is what is
  // expensive, and one that is seconds old is still the right answer to
  // "what is called firefox".
  function ensureProcessList() {
    if (processProc.running) return

    var now = Math.floor(Date.now() / 1000)
    if (root.processList && now - root.processListedAt < 5) return
    root.processListedAt = now

    processProc.command = root.boundedCommand("ps -eo pid,comm,pcpu,rss --sort=-pcpu --no-headers", 5, 262144)
    processProc.running = true
  }

  // "time in tokyo". Two things have to be fetched before this can answer --
  // the zone list once, then the zone's offset -- and each one that is missing
  // shows as a row that says so rather than as nothing at all.
  function timeRow(query) {
    var place = MenuModel.parseTimeQuery(query)
    if (place === null) return null

    if (!root.ensureTimeZones()) return root.timePendingRow(place)

    var zone = MenuModel.resolveZone(place, root.timeZones)
    // Not a place the system has heard of. Fall through, so "now playing"
    // stays an ordinary search.
    if (!zone) return null

    if (!root.ensureZoneOffset(zone)) return root.timePendingRow(place)

    var offset = root.zoneOffsets[zone].offset
    var there = MenuModel.zoneClock(Date.now(), offset)
    var here = MenuModel.zoneClock(Date.now(), root.localZoneOffset)
    // The day only earns a place on the line when it is not today's.
    var sameDay = there.date === here.date && there.month === here.month && there.year === here.year
    var weekday = MenuModel.zoneWeekdayName(there.weekday).slice(0, 3)

    return root.queryRow({
      kind: "time",
      icon: "󰅐",
      label: sameDay ? there.time : there.time + " " + weekday,
      detail: zone + " · " + MenuModel.zoneDifference(offset, root.localZoneOffset),
      payload: there.time
    })
  }

  function timePendingRow(place) {
    return root.queryRow({
      kind: "time",
      icon: "󰅐",
      label: place,
      detail: "Reading the zone database…",
      ready: false
    })
  }

  function ensureTimeZones() {
    if (root.timeZones.length > 0) return true
    if (!zoneListProc.running) zoneListProc.running = true
    return false
  }

  // Offsets are re-read after half an hour. They only move when a zone enters
  // or leaves summer time, and a shell that has been up for a week should not
  // still be an hour out because of it.
  function ensureZoneOffset(zone) {
    var known = root.zoneOffsets[zone]
    var now = Math.floor(Date.now() / 1000)
    if (known && now - known.readAt < 1800) return true
    if (zoneOffsetProc.running) return false

    zoneOffsetProc.zone = zone
    zoneOffsetProc.command = root.boundedCommand(
      "TZ=" + Util.shellQuote(zone) + " date +%z; date +%z", 5, 256)
    zoneOffsetProc.running = true
    return false
  }

  // A pasted link opens rather than matching nothing. Recognising one is
  // deliberately conservative -- see parseUrlQuery -- because "MenuModel.js"
  // gets typed into this field more often than a link to Moldova.
  function urlRow(query) {
    var link = MenuModel.parseUrlQuery(query)
    if (!link) return null

    // The link itself on the top line: it is the part worth reading, and the
    // card is narrow enough that a leading "Open " pushes the end of it out.
    return root.queryRow({
      kind: "url",
      icon: "󰖟",
      label: link.display,
      detail: "Open in browser",
      payload: link.url
    })
  }

  // The last resort, and the reason the menu no longer dead-ends: a search
  // that matched nothing at all is offered to the web instead. Appended rather
  // than returned by queryRows, so it can never crowd out a real answer.
  function webSearchRow(query) {
    var text = String(query || "").trim()
    if (!text) return null

    // "? <query>" is not a URL, and openUrl() hands it over quoted, so the
    // browser receives it as the single argument its address bar would.
    var payload = root.webSearchUsesBrowserDefault
      ? "? " + text
      : MenuModel.webSearchUrl(text, root.webSearchTemplate)
    if (!payload) return null

    // The query is already on the line above, so the row says what will
    // happen to it rather than repeating it back.
    return root.queryRow({
      kind: "websearch",
      icon: "󰍉",
      label: "Search the web",
      detail: root.webSearchUsesBrowserDefault
        ? "Look up “" + text + "” in your browser"
        : "Look up “" + text + "” on " + root.webSearchName,
      payload: payload
    })
  }

  // The other search that answers itself, give or take a table of rates. Same
  // shape as the calculator row, except the answer lives on a server: the
  // first conversion anyone types asks for the rates and stands in for the
  // answer until they land, and every one after it reads the cached snapshot.
  function currencyRow(query) {
    var parsed = MenuModel.parseCurrencyQuery(query)
    if (!parsed) return null

    root.ensureCurrencyRates()

    var snapshot = root.currencyRates
    var converted = snapshot ? MenuModel.convertCurrency(parsed, snapshot.rates) : null
    var asked = MenuModel.formatMathResult(parsed.amount) + " " + parsed.from
    var label = ""
    var detail = ""

    if (converted) {
      label = MenuModel.formatCurrencyValue(converted.value) + " " + parsed.to
      // Terse because the row is one line of a narrow card: what was asked,
      // the rate it went through, and how old that rate is.
      detail = asked + " at " + MenuModel.formatCurrencyRate(converted.rate)
      var asOf = root.currencyRatesDate()
      if (asOf) detail += " · " + asOf
    } else {
      label = asked + " → " + parsed.to
      if (!snapshot)
        detail = root.currencyFetchFailed ? "Exchange rates unavailable" : "Fetching exchange rates…"
      else
        detail = "No rate for " + (snapshot.rates[parsed.from] ? parsed.to : parsed.from)
    }

    return root.queryRow({
      kind: "currency",
      icon: "󰄔",
      label: label,
      detail: detail,
      payload: converted ? MenuModel.formatCurrencyValue(converted.value) : "",
      ready: !!converted
    })
  }

  // The date the snapshot was published, which is the honest thing to put
  // next to a rate that is up to a day old.
  function currencyRatesDate() {
    var snapshot = root.currencyRates
    if (!snapshot) return ""
    if (snapshot.updated > 0) return Qt.formatDate(new Date(snapshot.updated * 1000), "d MMM")
    return snapshot.date || ""
  }

  // Fetched on demand -- the first conversion someone types -- so a menu never
  // used as a converter never reaches the network, and one that is reaches it
  // about as often as the rates change. Written to a temporary name and moved
  // into place so a fetch cut off halfway cannot leave half a snapshot behind.
  function ensureCurrencyRates() {
    if (currencyRatesProc.running || currencyCacheProc.running) return

    // The cache is read on the first conversion typed rather than at startup,
    // so a menu never used as a converter never touches the file at all. Its
    // collector rebuilds the row, which comes back through here to decide
    // whether what it found is still current.
    if (!root.currencyCacheRead) {
      root.currencyCacheRead = true
      root.loadCurrencyCache()
      return
    }

    var now = Math.floor(Date.now() / 1000)
    if (!MenuModel.currencyRatesStale(root.currencyRates, now)) return
    // Every keystroke of a conversion comes through here, so a fetch that
    // failed has to stay failed for a while rather than be retried by the
    // next character typed.
    if (now - root.currencyFetchedAt < 60) return
    root.currencyFetchedAt = now

    var target = root.currencyRatesPath
    var directory = target.substring(0, target.lastIndexOf("/"))

    // Nothing here writes to a name anyone could have guessed. mktemp creates
    // with O_EXCL and mode 600, so a pre-placed file or symlink at the
    // temporary path makes the fetch fail rather than redirect it; the cache
    // directory is checked to be ours and not writable by anyone else before
    // that; curl is capped so a source that answers with gigabytes cannot fill
    // the disk; and the move is a rename, which replaces a symlink sitting at
    // the target instead of writing through it.
    var script = [
      'set -u',
      'd=' + Util.shellQuote(directory),
      't=',
      'cleanup() { [ -n "$t" ] && rm -f -- "$t"; }',
      'trap cleanup EXIT',
      'mkdir -p -m 700 -- "$d" 2>/dev/null',
      // A directory that is a symlink, or belongs to someone else, or that
      // anyone can write to, cannot hold a cache worth trusting.
      'if [ -L "$d" ] || [ ! -d "$d" ]; then exit 1; fi',
      'find "$d" -maxdepth 0 -uid "$(id -u)" ! -perm /022 -print -quit 2>/dev/null | grep -q . || exit 1',
      't=$(mktemp -- "$d/.rates.XXXXXXXXXXXX") || exit 1',
      'curl -fsS --max-time 8 --max-filesize ' + root.currencyFileCeiling
        + ' -o "$t" -- ' + Util.shellQuote(root.currencyRatesUrl) + ' || exit 1',
      // curl only enforces --max-filesize against a declared length, so a
      // chunked reply is measured here before it is kept.
      '[ "$(wc -c < "$t")" -le ' + root.currencyFileCeiling + ' ] || exit 1',
      'mv -f -- "$t" ' + Util.shellQuote(target) + ' || exit 1',
      't='
    ].join("\n")

    currencyRatesProc.command = ["bash", "-c", script]
    currencyRatesProc.running = true
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

  // Park the cursor on a selectable row after the rows underneath it changed.
  // A menu with nothing selectable in it -- every app in it already installed
  // -- shows no cursor at all, and grows one the moment a row can take it.
  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
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
        section: ""
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

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (root.hiddenFromSearch(entry)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)

      rows = root.queryRows(query).concat(rows)

      // Nothing in the menu, and nothing that answered itself. Offer to look
      // it up rather than showing the empty state.
      if (rows.length === 0) {
        var fallback = root.webSearchRow(query)
        if (fallback) rows.push(fallback)
      }
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (root.hiddenFromList(child)) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    // Sanitized here rather than in each builder: this is the one place
    // every row passes through on its way to the ListView.
    for (var k = 0; k < rows.length; k++) displayModel.append(MenuModel.sanitizeRow(rows[k]))
    layoutSerial += 1

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

  function select(delta) {
    if (displayModel.count === 0) return

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
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
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
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.launchApp(appId, label)
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
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
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
    id: zoneListProc
    command: root.boundedCommand("timedatectl list-timezones", 5, 65536)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var zones = String(text || "").split("\n")
        var kept = []
        for (var i = 0; i < zones.length; i++) {
          var zone = zones[i].trim()
          if (zone) kept.push(zone)
        }
        if (kept.length === 0) return

        root.timeZones = kept
        if (root.filterText.trim()) root.rebuildDisplay()
      }
    }
  }

  Process {
    id: zoneOffsetProc
    property string zone: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var offset = MenuModel.parseZoneOffset(lines[0])
        var local = lines.length > 1 ? MenuModel.parseZoneOffset(lines[1]) : null
        if (offset === null) return

        if (local !== null) root.localZoneOffset = local
        var next = root.zoneOffsets
        next[zoneOffsetProc.zone] = { offset: offset, readAt: Math.floor(Date.now() / 1000) }
        root.zoneOffsets = next
        if (root.filterText.trim()) root.rebuildDisplay()
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

  Process {
    id: processProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.processList = String(text || "")
        if (root.filterText.trim()) root.rebuildDisplay()
      }
    }
  }

  Process {
    id: randomProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split(/\s+/)
        var bytes = []
        for (var i = 0; i < parts.length; i++) {
          if (!parts[i]) continue
          var value = parseInt(parts[i], 10)
          if (value >= 0 && value <= 255) bytes.push(value)
        }
        if (bytes.length === 0) return

        root.randomPool = root.randomPool.concat(bytes)
        if (root.filterText.trim()) root.rebuildDisplay()
      }
    }
  }

  Process {
    id: currencyRatesProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) {
        root.loadCurrencyCache()
        return
      }

      // Offline, or the source is down. The row says so rather than sitting on
      // "fetching…" forever; `currencyFetchedAt` keeps the retry off the next
      // keystroke.
      root.currencyFetchFailed = true
      if (root.filterText.trim()) root.rebuildDisplay()
    }
  }

  // The cached snapshot, which is a plain copy of what the rate source last
  // answered. Missing on a machine that has never converted anything, which is
  // what the first conversion typed goes and fixes. Read through the same
  // helper as the menu sources: the cache lives under ~/.cache, so the file at
  // that path is not necessarily the file this shell last wrote there.
  Process {
    id: currencyCacheProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var snapshot = MenuModel.parseCurrencyRates(String(text || ""))
        root.currencyRates = snapshot
        if (snapshot) root.currencyFetchFailed = false
        // Rebuild either way. A cache that was missing or stale leaves the row
        // to ask ensureCurrencyRates again, which is what starts the fetch.
        if (root.filterText.trim()) root.rebuildDisplay()
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
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
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

          if (event.key === Qt.Key_Delete) {
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
                     && root.regenerateUtility()) {
            // Only claimed when there was something to reroll, so Ctrl+R stays
            // free everywhere else in the menu.
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
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
            else if (displayModel.count > 0) root.cursorActive = true
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
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // Bounded like the rows: the prompt comes from whoever invoked
            // the dmenu, and the title from the JSONC.
            text: MenuModel.sanitizeText(root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…")))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.heading)
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: root.scaledFont(Style.font.iconLarge)
                width: root.iconSlotWidth
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: root.scaledFont(Style.font.iconLarge)
                height: root.scaledFont(Style.font.iconLarge)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp ? root.appIconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (root.iconSlotWidth - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.scaledFont(Style.font.heading)
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: root.scaledFont(Style.font.bodySmall)
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: root.scaledFont(Style.font.body)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: root.scaledFont(Style.font.heading)
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
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
            visible: displayModel.count === 0 && root.mode !== "input"

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
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.title)
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
