import QtQuick
import Quickshell
import Quickshell.Io
import "FileSearch.js" as FileSearch
import "Roots.js" as Roots

// File and folder search for the Files and Folders tabs and All's sections:
// what to ask fd for the current tab and query, running fd (debounced, one
// generation at a time) and stat, the results and their ranking into rows.
// The ranking itself is FileSearch.js; opening, copying and terminal actions
// stay in Menu.qml, which owns the selected row. Reaches the menu through
// `menu` for the query, the tab, row building and redraws.
//
// Besides $HOME it searches the search roots (Roots.js): an indexed root
// through its index, a live one with fd -- the latter only once the root
// answered a status check, and in a lane of its own, so a slow share adds
// its results late instead of holding back the rest. It also keeps those
// indexes fresh in the background, and reads zoxide's folder scores for
// the ranking.
Item {
  id: searcher

  required property var menu

  // File search (Files, Folders, and their sections in All). One search is
  // current at a time; every fd/stat run carries the generation it was started
  // for, and output from an older one is dropped on arrival.
  property int fileFilterIndex: 0
  property int folderFilterIndex: 0
  property string fileSortMode: "relevance"
  property int fileDisplayLimit: 60
  property int fileSearchGen: 0
  // The generation the running fd pair was launched for. Exits are counted
  // against it alone, so a cancelled pair that dies after a new one started
  // cannot eat the new pair's count.
  property int fileLaunchGen: 0
  property bool fileSearching: false
  property bool fileRerunPending: false
  property int filePending: 0
  property var filePendingItems: []
  // The items the current search found, and the key (tab, filter, query) they
  // answer, so a rebuild can tell results for this query from stale ones.
  property var fileResults: []
  property string fileResultsKey: ""
  property string fileResultsScope: ""
  property var fileMtimes: ({})
  // All only asks fd once the query is this long: one letter matches most of
  // $HOME, and the answer would be noise ranked by path depth.
  readonly property int allFileMinQuery: 2

  // ------------------------------------------------------------ roots --

  readonly property var roots: Roots.enabledRoots(searcher.menu.searchRoots)
  readonly property bool hasRoots: searcher.roots.length > 0
  onRootsChanged: {
    searcher.rootStatus = ({})
    searcher.refreshRootStatus()
  }
  // Roots.parseStatus of the last check: { id: { online, indexedAt, ... } }.
  property var rootStatus: ({})
  // A root going offline or coming back changes the rows ("· offline"), not
  // the results: count it as a change so memoized rows are rebuilt.
  onRootStatusChanged: searcher.fileResultsVersion += 1
  // Index rebuilds that failed, by root id: when, so they wait before retrying.
  property var indexFailedAt: ({})
  // The live lane: whether its results are still to come for this search.
  property bool livePending: false
  property var liveNext: null

  function rootOnline(id) {
    var s = searcher.rootStatus[id]
    return !!s && s.online
  }

  function liveRoots() {
    return searcher.roots.filter(function(r) { return r.cacheMinutes === 0 && searcher.rootOnline(r.id) })
  }

  function indexedRoots() {
    return searcher.roots.filter(function(r) {
      var s = searcher.rootStatus[r.id]
      return r.cacheMinutes > 0 && !!s && s.indexedAt > 0
    })
  }

  // Part of every search key, so a root coming online (or getting its first
  // index) runs the search again.
  function rootsSignature() {
    var parts = []
    for (var i = 0; i < searcher.roots.length; i++) {
      var r = searcher.roots[i]
      var s = searcher.rootStatus[r.id]
      parts.push(r.id + (s && s.online ? "+" : "-") + (s ? s.indexedAt : 0) + ":" + r.cacheMinutes)
    }
    return parts.join(",")
  }

  function refreshRootStatus() {
    if (!searcher.hasRoots || statusProc.running) return
    statusProc.command = Roots.statusCommand(searcher.menu.cacheHome, searcher.roots)
    statusProc.running = true
  }

  function applyRootStatus(text) {
    var before = searcher.rootsSignature()
    searcher.rootStatus = Roots.parseStatus(text)
    searcher.indexDueRoots()
    if (searcher.menu.opened && searcher.rootsSignature() !== before) searcher.requestFileSearch()
  }

  // Starts the next index rebuild that is due, one at a time.
  function indexDueRoots() {
    if (indexProc.running) return
    var now = Date.now()
    for (var i = 0; i < searcher.roots.length; i++) {
      var r = searcher.roots[i]
      var s = searcher.rootStatus[r.id]
      if (!s || !Roots.indexDue(r, s.indexedAt, searcher.indexFailedAt[r.id], now)) continue
      indexProc.rootId = r.id
      indexProc.command = Roots.indexCommand(searcher.menu.cacheHome, r, FileSearch.EXCLUDES)
      indexProc.running = true
      return
    }
  }

  // ----------------------------------------------------------- zoxide --

  // zoxide's folder scores, { path: score }, read on every open.
  property var frecency: ({})
  onFrecencyChanged: searcher.fileResultsVersion += 1

  function loadZoxide() {
    if (searcher.menu.zoxideMode === "off") {
      searcher.frecency = ({})
      return
    }
    if (zoxideProc.running) return
    // zoxide checks each folder still exists; the timeout keeps a hung mount
    // among them from holding the list back.
    zoxideProc.command = ["bash", "-c",
      'command -v zoxide >/dev/null 2>&1 || exit 0; timeout -k 1 2 zoxide query --list --score 2>/dev/null | head -c 1048576']
    zoxideProc.running = true
  }

  // A folder opened from the launcher counts as a visit, as `z` would.
  function learnFolder(path) {
    if (!path || searcher.menu.zoxideMode === "off" || !searcher.menu.zoxideAdd) return
    Quickshell.execDetached(["bash", "-c", 'command -v zoxide >/dev/null 2>&1 && exec zoxide add -- "$1"', "bash", path])
  }

  // Each open: the roots' status (which also starts due index rebuilds) and
  // zoxide's scores.
  function prepare() {
    searcher.refreshRootStatus()
    searcher.loadZoxide()
  }

  // ----------------------------------------------------------- search --

  function fileFilterFor(kind) {
    return FileSearch.filterAt(kind, kind === "folders" ? searcher.folderFilterIndex : searcher.fileFilterIndex)
  }

  // Where Files and Folders look (the third chip row, Ctrl+R): everywhere,
  // only $HOME, or one root. All always searches everywhere.
  property string rootScope: "all"

  readonly property var scopeChoices: {
    var out = [{ id: "all", label: "Everywhere", icon: "" }, { id: "home", label: "Home", icon: "" }]
    for (var i = 0; i < searcher.roots.length; i++) out.push({ id: searcher.roots[i].id, label: searcher.roots[i].label, icon: "" })
    return out
  }

  // The scope in effect: a root that was switched off or removed falls back
  // to everywhere.
  function currentScope() {
    for (var i = 0; i < searcher.scopeChoices.length; i++) if (searcher.scopeChoices[i].id === searcher.rootScope) return searcher.rootScope
    return "all"
  }

  function setRootScope(id) {
    searcher.rootScope = id
    searcher.menu.selectedIndex = 0
    searcher.menu.rebuildDisplay()
    searcher.requestFileSearch()
  }

  function cycleRootScope() {
    if (!searcher.hasRoots) return false
    var current = searcher.currentScope()
    var ids = searcher.scopeChoices.map(function(c) { return c.id })
    searcher.setRootScope(ids[(ids.indexOf(current) + 1) % ids.length])
    return true
  }

  // The roots a search spec covers.
  function rootsFor(spec) {
    if (spec.filter.systemFolders || spec.rootScope === "home") return []
    if (spec.rootScope === "all") return searcher.roots
    return searcher.roots.filter(function(r) { return r.id === spec.rootScope })
  }

  // What the current tab and query ask of fd, or null for nothing: which
  // types to list and with which filter.
  function fileSearchSpec() {
    if (searcher.menu.dmenuActive || !searcher.menu.opened || searcher.menu.isAiMode || searcher.menu.commandMode) return null
    var query = searcher.menu.filterText.trim()
    var sig = "|" + searcher.rootsSignature() + "|"
    var where = searcher.currentScope()
    if (searcher.menu.activeTab === "files" || searcher.menu.activeTab === "folders") {
      var folders = searcher.menu.activeTab === "folders"
      var scope = searcher.menu.activeTab + "|" + (folders ? searcher.folderFilterIndex : searcher.fileFilterIndex) + "|" + where
      return { scope: scope, key: scope + sig + query, query: query, dirs: folders, files: !folders,
               rootScope: where, filter: searcher.fileFilterFor(searcher.menu.activeTab) }
    }
    if (searcher.menu.activeTab === "all") {
      if (query.length < searcher.allFileMinQuery) return null
      // An answer that computed itself (arithmetic, a conversion, a password)
      // is not also a file name worth walking $HOME for.
      if (searcher.menu.queryRows(query).length > 0) return null
      var dirs = searcher.menu.inAll("folders")
      var files = searcher.menu.inAll("files")
      if (!dirs && !files) return null
      var kinds = (dirs ? "d" : "") + (files ? "f" : "")
      return { scope: "all" + kinds, key: "all" + kinds + sig + query, query: query, dirs: dirs, files: files,
               rootScope: "all", filter: FileSearch.ALL_FILTER }
    }
    return null
  }

  function requestFileSearch() {
    var spec = searcher.fileSearchSpec()
    if (!spec) {
      fileDebounce.stop()
      return
    }
    if (spec.key === searcher.fileResultsKey && !searcher.fileSearching) return
    fileDebounce.restart()
  }

  function runFileSearch() {
    var spec = searcher.fileSearchSpec()
    if (!spec) return
    searcher.fileSearchGen += 1
    if (dirSearchProc.running || fileSearchProc.running || indexSearchProc.running) {
      // Let the running search finish into the void; its generation is stale
      // now. Starting a Process that is still being torn down is not safe.
      searcher.fileRerunPending = true
      return
    }
    searcher.launchFileSearch(spec)
  }

  function launchFileSearch(spec) {
    searcher.fileRerunPending = false
    searcher.fileSearching = true
    searcher.filePendingItems = []
    searcher.filePending = 0
    var gen = searcher.fileSearchGen
    searcher.fileLaunchGen = gen
    var home = spec.rootScope === "all" || spec.rootScope === "home"
    var inScope = searcher.rootsFor(spec)
    var excludes = Roots.homeExcludes(searcher.roots, searcher.menu.homeDir)

    // timeout ends an fd that stalls on a slow mount; --max-results already
    // bounds how much one can print.
    if (spec.dirs && home) {
      searcher.filePending += 1
      dirSearchProc.gen = gen
      dirSearchProc.key = spec.key
      dirSearchProc.scope = spec.scope
      dirSearchProc.command = ["timeout", "5"].concat(FileSearch.buildArgv(spec.query, spec.filter, true, searcher.menu.homeDir, excludes))
      dirSearchProc.running = true
    }
    if (spec.files && home) {
      searcher.filePending += 1
      fileSearchProc.gen = gen
      fileSearchProc.key = spec.key
      fileSearchProc.scope = spec.scope
      fileSearchProc.command = ["timeout", "5"].concat(FileSearch.buildArgv(spec.query, spec.filter, false, searcher.menu.homeDir, excludes))
      fileSearchProc.running = true
    }

    var indexed = searcher.indexedRoots().filter(function(r) { return inScope.indexOf(r) >= 0 })
    if (indexed.length > 0) {
      var pairs = indexed.map(function(r) { return { root: r.path, index: Roots.indexPath(searcher.menu.cacheHome, r.id) } })
      searcher.filePending += 1
      indexSearchProc.gen = gen
      indexSearchProc.key = spec.key
      indexSearchProc.scope = spec.scope
      indexSearchProc.command = Roots.indexSearchCommand((spec.dirs ? "d" : "") + (spec.files ? "f" : ""), spec.filter.hidden === true,
        spec.files ? spec.filter.exts : [], FileSearch.extractTerms(spec.query), pairs)
      indexSearchProc.running = true
    }

    var live = searcher.liveRoots().filter(function(r) { return inScope.indexOf(r) >= 0 })
    searcher.livePending = live.length > 0
    if (live.length > 0) {
      var next = {
        gen: gen, key: spec.key, scope: spec.scope,
        command: ["timeout", "-k", "1", "5"].concat(FileSearch.buildRootArgv(spec.query, spec.filter, spec.dirs, spec.files,
          live.map(function(r) { return r.path })))
      }
      // A live search still running belongs to an older query: stop it and
      // start this one once it is gone.
      if (liveSearchProc.running) {
        searcher.liveNext = next
        liveSearchProc.running = false
      } else searcher.startLive(next)
    }

    if (searcher.filePending === 0 && !searcher.livePending) searcher.fileSearching = false
  }

  function startLive(next) {
    liveSearchProc.gen = next.gen
    liveSearchProc.key = next.key
    liveSearchProc.scope = next.scope
    liveSearchProc.command = next.command
    liveSearchProc.running = true
  }

  function fileSearchFinished(proc, text, isDir) {
    if (proc.gen !== searcher.fileLaunchGen) return
    if (proc.gen === searcher.fileSearchGen)
      searcher.filePendingItems = searcher.filePendingItems.concat(FileSearch.parseLines(text, isDir, searcher.menu.homeDir, searcher.roots))
    searcher.filePending -= 1
    if (searcher.filePending > 0) return

    searcher.fileSearching = searcher.livePending
    if (searcher.fileRerunPending) {
      var spec = searcher.fileSearchSpec()
      if (spec) searcher.launchFileSearch(spec)
      else searcher.fileRerunPending = false
      return
    }
    if (proc.gen !== searcher.fileSearchGen) return
    searcher.publish(searcher.filePendingItems, proc.key, proc.scope)
  }

  // The live lane's answer: folded into what is already on screen, or into
  // what the other lanes are still collecting.
  function liveSearchFinished(text) {
    var gen = liveSearchProc.gen
    if (searcher.liveNext) {
      var next = searcher.liveNext
      searcher.liveNext = null
      if (next.gen === searcher.fileSearchGen) {
        searcher.startLive(next)
        return
      }
    }
    if (gen !== searcher.fileSearchGen || gen !== searcher.fileLaunchGen) return
    searcher.livePending = false
    var items = FileSearch.parseLines(text, null, searcher.menu.homeDir, searcher.roots)
    if (searcher.filePending > 0) {
      searcher.filePendingItems = searcher.filePendingItems.concat(items)
      return
    }
    searcher.fileSearching = false
    if (searcher.fileResultsKey === liveSearchProc.key) searcher.publish(searcher.fileResults.concat(items), liveSearchProc.key, liveSearchProc.scope)
    else searcher.publish(searcher.filePendingItems.concat(items), liveSearchProc.key, liveSearchProc.scope)
  }

  function publish(items, key, scope) {
    for (var i = 0; i < items.length; i++) {
      var known = searcher.fileMtimes[items[i].path]
      if (known !== undefined) items[i].mtimeMs = known
    }
    searcher.fileResults = items
    searcher.fileResultsKey = key
    searcher.fileResultsScope = scope
    searcher.menu.rebuildDisplay(true)
    searcher.fetchFileMtimes()
  }

  // Modification times for the sort modes and the right-hand column, fetched
  // in one stat call after the list is already on screen. Paths on a root
  // that did not answer its status check are left out: stat would only wait
  // on them.
  function fetchFileMtimes() {
    if (statProc.running || searcher.fileResults.length === 0) return
    var paths = []
    for (var i = 0; i < searcher.fileResults.length && paths.length < 300; i++) {
      var item = searcher.fileResults[i]
      if (searcher.fileMtimes[item.path] !== undefined) continue
      if (item.rootId && !searcher.rootOnline(item.rootId)) continue
      paths.push(item.path)
    }
    if (paths.length === 0) return
    statProc.gen = searcher.fileSearchGen
    statProc.command = ["timeout", "5", "stat", "--printf", "%Y\t%n\\0", "--"].concat(paths)
    statProc.running = true
  }

  function applyFileMtimes(map) {
    var next = ({})
    for (var known in searcher.fileMtimes) next[known] = searcher.fileMtimes[known]
    for (var path in map) next[path] = map[path]
    searcher.fileMtimes = next
    for (var i = 0; i < searcher.fileResults.length; i++) {
      var ms = next[searcher.fileResults[i].path]
      if (ms !== undefined) searcher.fileResults[i].mtimeMs = ms
    }
    searcher.fileResultsVersion += 1
    searcher.menu.rebuildDisplay(true)
  }

  function cancelFileSearch() {
    fileDebounce.stop()
    searcher.fileSearchGen += 1
    searcher.fileRerunPending = false
    searcher.liveNext = null
    searcher.livePending = false
    if (dirSearchProc.running) dirSearchProc.running = false
    if (fileSearchProc.running) fileSearchProc.running = false
    if (indexSearchProc.running) indexSearchProc.running = false
    if (liveSearchProc.running) liveSearchProc.running = false
    searcher.fileSearching = false
  }

  // Rows for the current results. While fd is still answering a newer query,
  // the previous results are re-ranked against it instead of vanishing: fd
  // matches the full path, so typing further only ever narrows them, and the
  // list settles in place rather than blinking empty on every keystroke.
  // Ranking up to 1000 results is the costly part, and every rebuild asked
  // for it twice (Files and Folders both split one ranking) while a
  // keystroke rebuilds 3-5 times. The rows only change with the query, the
  // results (fileResultsVersion, bumped on new results, mtimes and zoxide
  // scores), the sort, zoxide's mode, the limit, and -- for "Yesterday
  // 16:27" -- the minute.
  property int fileResultsVersion: 0
  onFileResultsChanged: searcher.fileResultsVersion += 1
  readonly property var rowsMemo: ({ key: "", rows: [] })

  function fileRows(spec, limit) {
    if (!spec || spec.scope !== searcher.fileResultsScope) return []
    var key = [spec.key, searcher.fileResultsScope, searcher.fileResultsVersion, searcher.fileSortMode,
               searcher.menu.zoxideMode, limit, Math.floor(Date.now() / 60000)].join("\n")
    if (searcher.rowsMemo.key !== key) {
      searcher.rowsMemo.rows = searcher.computeFileRows(spec, limit)
      searcher.rowsMemo.key = key
    }
    return searcher.rowsMemo.rows.slice()
  }

  function computeFileRows(spec, limit) {
    var items = searcher.fileResults
    // "results": the folders zoxide knows join the candidates.
    if (spec.dirs && searcher.menu.zoxideMode === "results" && !spec.filter.systemFolders) {
      var known = FileSearch.zoxideItems(searcher.frecency, spec.query, searcher.menu.homeDir, searcher.roots, 200)
      if (spec.rootScope === "home") known = known.filter(function(it) { return it.rootId === "" })
      else if (spec.rootScope !== "all") known = known.filter(function(it) { return it.rootId === spec.rootScope })
      items = items.concat(known)
    }
    var ranked = FileSearch.rankResults(items, spec.query, limit, searcher.menu.homeDir, searcher.fileSortMode,
      searcher.menu.zoxideMode === "off" ? null : searcher.frecency)
    var now = Date.now()
    var rows = []
    for (var i = 0; i < ranked.length; i++) {
      var item = ranked[i]
      var offline = item.rootId && !searcher.rootOnline(item.rootId)
      rows.push(searcher.menu.queryRow({
        id: (item.isDir ? "folder:" : "file:") + item.path,
        kind: item.isDir ? "folder" : "file",
        icon: item.icon,
        label: item.name,
        detail: offline ? item.dir + " · offline" : item.dir,
        payload: item.path,
        trail: item.mtimeMs ? FileSearch.formatMtime(item.mtimeMs, now) : ""
      }))
    }
    return rows
  }

  function filesTabRows() {
    return searcher.fileRows(searcher.fileSearchSpec(), searcher.fileDisplayLimit)
  }

  // The kind-split halves All needs from one combined search.
  function fileSectionRows(isDir) {
    var rows = searcher.fileRows(searcher.fileSearchSpec(), searcher.fileDisplayLimit)
    var out = []
    for (var i = 0; i < rows.length; i++) if ((rows[i].kind === "folder") === isDir) out.push(rows[i])
    return out
  }

  function cycleFileFilter() {
    if (searcher.menu.activeTab === "files")
      searcher.fileFilterIndex = (searcher.fileFilterIndex + 1) % FileSearch.FILE_FILTERS.length
    else if (searcher.menu.activeTab === "folders")
      searcher.folderFilterIndex = (searcher.folderFilterIndex + 1) % FileSearch.FOLDER_FILTERS.length
    else return
    searcher.menu.selectedIndex = 0
    searcher.menu.rebuildDisplay()
    searcher.requestFileSearch()
  }

  function setFileFilter(id) {
    var list = FileSearch.filtersFor(searcher.menu.activeTab)
    for (var i = 0; i < list.length; i++) {
      if (list[i].id !== id) continue
      if (searcher.menu.activeTab === "folders") searcher.folderFilterIndex = i
      else searcher.fileFilterIndex = i
      searcher.menu.selectedIndex = 0
      searcher.menu.rebuildDisplay()
      searcher.requestFileSearch()
      return
    }
  }

  Timer {
    id: fileDebounce
    interval: 200
    onTriggered: searcher.runFileSearch()
  }

  // Keeps indexes fresh while the launcher is closed too: every minute the
  // roots' status is read again, which starts a rebuild that is due.
  Timer {
    interval: 60000
    repeat: true
    running: searcher.roots.some(function(r) { return r.cacheMinutes > 0 })
    onTriggered: searcher.refreshRootStatus()
  }

  Process {
    id: dirSearchProc
    property int gen: 0
    property string key: ""
    property string scope: ""
    stdout: StdioCollector { id: dirSearchOut; waitForEnd: true }
    onExited: searcher.fileSearchFinished(dirSearchProc, dirSearchOut.text || "", true)
  }

  Process {
    id: fileSearchProc
    property int gen: 0
    property string key: ""
    property string scope: ""
    stdout: StdioCollector { id: fileSearchOut; waitForEnd: true }
    onExited: searcher.fileSearchFinished(fileSearchProc, fileSearchOut.text || "", false)
  }

  // Indexed roots: fast (a local file), so part of the main search.
  Process {
    id: indexSearchProc
    property int gen: 0
    property string key: ""
    property string scope: ""
    stdout: StdioCollector { id: indexSearchOut; waitForEnd: true }
    onExited: searcher.fileSearchFinished(indexSearchProc, indexSearchOut.text || "", null)
  }

  Process {
    id: liveSearchProc
    property int gen: 0
    property string key: ""
    property string scope: ""
    stdout: StdioCollector { id: liveSearchOut; waitForEnd: true }
    onExited: searcher.liveSearchFinished(liveSearchOut.text || "")
  }

  Process {
    id: statProc
    property int gen: 0
    stdout: StdioCollector { id: statOut; waitForEnd: true }
    onExited: {
      if (statProc.gen === searcher.fileSearchGen) searcher.applyFileMtimes(FileSearch.parseStatLines(statOut.text || ""))
      else searcher.fetchFileMtimes()
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: searcher.applyRootStatus(statusOut.text || "")
  }

  Process {
    id: indexProc
    property string rootId: ""
    onExited: function(exitCode) {
      var failed = ({})
      for (var id in searcher.indexFailedAt) failed[id] = searcher.indexFailedAt[id]
      if (exitCode === 0) delete failed[indexProc.rootId]
      else failed[indexProc.rootId] = Date.now()
      searcher.indexFailedAt = failed
      // Read the new index's time, which also moves on to the next due root.
      Qt.callLater(searcher.refreshRootStatus)
    }
  }

  Process {
    id: zoxideProc
    stdout: StdioCollector { id: zoxideOut; waitForEnd: true }
    onExited: {
      searcher.frecency = FileSearch.parseZoxide(zoxideOut.text || "")
      if (searcher.menu.opened) searcher.menu.rebuildDisplay(true)
    }
  }
}
