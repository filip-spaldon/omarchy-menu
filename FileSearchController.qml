import QtQuick
import Quickshell
import Quickshell.Io
import "FileSearch.js" as FileSearch

// File and folder search for the Files and Folders tabs and All's sections:
// what to ask fd for the current tab and query, running fd (debounced, one
// generation at a time) and stat, the results and their ranking into rows.
// The ranking itself is FileSearch.js; opening, copying and terminal actions
// stay in Menu.qml, which owns the selected row. Reaches the menu through
// `menu` for the query, the tab, row building and redraws.
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

  function fileFilterFor(kind) {
    return FileSearch.filterAt(kind, kind === "folders" ? searcher.folderFilterIndex : searcher.fileFilterIndex)
  }

  // What the current tab and query ask of fd, or null for nothing: which
  // types to list and with which filter.
  function fileSearchSpec() {
    if (searcher.menu.dmenuActive || !searcher.menu.opened || searcher.menu.isAiMode || searcher.menu.commandMode) return null
    var query = searcher.menu.filterText.trim()
    if (searcher.menu.activeTab === "files")
      return { scope: "files|" + searcher.fileFilterIndex, key: "files|" + searcher.fileFilterIndex + "|" + query, query: query, dirs: false, files: true, filter: searcher.fileFilterFor("files") }
    if (searcher.menu.activeTab === "folders")
      return { scope: "folders|" + searcher.folderFilterIndex, key: "folders|" + searcher.folderFilterIndex + "|" + query, query: query, dirs: true, files: false, filter: searcher.fileFilterFor("folders") }
    if (searcher.menu.activeTab === "all") {
      if (query.length < searcher.allFileMinQuery) return null
      // An answer that computed itself (arithmetic, a conversion, a password)
      // is not also a file name worth walking $HOME for.
      if (searcher.menu.queryRows(query).length > 0) return null
      var dirs = searcher.menu.inAll("folders")
      var files = searcher.menu.inAll("files")
      if (!dirs && !files) return null
      var kinds = (dirs ? "d" : "") + (files ? "f" : "")
      return { scope: "all" + kinds, key: "all" + kinds + "|" + query, query: query, dirs: dirs, files: files, filter: FileSearch.ALL_FILTER }
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
    if (dirSearchProc.running || fileSearchProc.running) {
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

    // timeout ends an fd that stalls on a slow mount; --max-results already
    // bounds how much one can print.
    if (spec.dirs) {
      searcher.filePending += 1
      dirSearchProc.gen = gen
      dirSearchProc.key = spec.key
      dirSearchProc.command = ["timeout", "5"].concat(FileSearch.buildArgv(spec.query, spec.filter, true, searcher.menu.homeDir))
      dirSearchProc.running = true
    }
    if (spec.files) {
      searcher.filePending += 1
      fileSearchProc.gen = gen
      fileSearchProc.key = spec.key
      fileSearchProc.command = ["timeout", "5"].concat(FileSearch.buildArgv(spec.query, spec.filter, false, searcher.menu.homeDir))
      fileSearchProc.running = true
    }
    if (searcher.filePending === 0) searcher.fileSearching = false
  }

  function fileSearchFinished(proc, text, isDir) {
    if (proc.gen !== searcher.fileLaunchGen) return
    if (proc.gen === searcher.fileSearchGen)
      searcher.filePendingItems = searcher.filePendingItems.concat(FileSearch.parseLines(text, isDir, searcher.menu.homeDir))
    searcher.filePending -= 1
    if (searcher.filePending > 0) return

    searcher.fileSearching = false
    if (searcher.fileRerunPending) {
      var spec = searcher.fileSearchSpec()
      if (spec) searcher.launchFileSearch(spec)
      else searcher.fileRerunPending = false
      return
    }
    if (proc.gen !== searcher.fileSearchGen) return

    var items = searcher.filePendingItems
    for (var i = 0; i < items.length; i++) {
      var known = searcher.fileMtimes[items[i].path]
      if (known !== undefined) items[i].mtimeMs = known
    }
    searcher.fileResults = items
    searcher.fileResultsKey = proc.key
    searcher.fileResultsScope = proc.key.slice(0, proc.key.lastIndexOf("|"))
    searcher.menu.rebuildDisplay(true)
    searcher.fetchFileMtimes()
  }

  // Modification times for the sort modes and the right-hand column, fetched
  // in one stat call after the list is already on screen.
  function fetchFileMtimes() {
    if (statProc.running || searcher.fileResults.length === 0) return
    var paths = []
    for (var i = 0; i < searcher.fileResults.length && paths.length < 300; i++) {
      if (searcher.fileMtimes[searcher.fileResults[i].path] === undefined) paths.push(searcher.fileResults[i].path)
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
    searcher.menu.rebuildDisplay(true)
  }

  function cancelFileSearch() {
    fileDebounce.stop()
    searcher.fileSearchGen += 1
    searcher.fileRerunPending = false
    if (dirSearchProc.running) dirSearchProc.running = false
    if (fileSearchProc.running) fileSearchProc.running = false
    searcher.fileSearching = false
  }

  // Rows for the current results. While fd is still answering a newer query,
  // the previous results are re-ranked against it instead of vanishing: fd
  // matches the full path, so typing further only ever narrows them, and the
  // list settles in place rather than blinking empty on every keystroke.
  function fileRows(spec, limit) {
    if (!spec || spec.scope !== searcher.fileResultsScope) return []
    var ranked = FileSearch.rankResults(searcher.fileResults, spec.query, limit, searcher.menu.homeDir, searcher.fileSortMode)
    var now = Date.now()
    var rows = []
    for (var i = 0; i < ranked.length; i++) {
      var item = ranked[i]
      rows.push(searcher.menu.queryRow({
        id: (item.isDir ? "folder:" : "file:") + item.path,
        kind: item.isDir ? "folder" : "file",
        icon: item.icon,
        label: item.name,
        detail: item.dir,
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

  Process {
    id: dirSearchProc
    property int gen: 0
    property string key: ""
    stdout: StdioCollector { id: dirSearchOut; waitForEnd: true }
    onExited: searcher.fileSearchFinished(dirSearchProc, dirSearchOut.text || "", true)
  }

  Process {
    id: fileSearchProc
    property int gen: 0
    property string key: ""
    stdout: StdioCollector { id: fileSearchOut; waitForEnd: true }
    onExited: searcher.fileSearchFinished(fileSearchProc, fileSearchOut.text || "", false)
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
}
