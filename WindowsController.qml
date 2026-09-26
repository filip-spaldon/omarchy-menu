import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Windows.js" as Windows

// Open windows for the Windows tab and All's Windows section. The list is
// read from `hyprctl -j clients` each time the menu opens, and again while it
// is open whenever Hyprland reports a window opening, closing, moving or
// being retitled. Parsing, grouping and ranking are Windows.js; focusing runs
// its argv. Reaches the menu through `menu` for the tab, the query and
// redraws.
Item {
  id: windows

  required property var menu

  property var list: []
  // class -> { name, icon } or null, looked up in the desktop entries once
  // per class and kept for the life of the shell.
  property var appCache: ({})

  readonly property bool wanted: windows.menu.opened && !windows.menu.dmenuActive
    && (windows.menu.activeTab === "windows"
        || (windows.menu.activeTab === "all" && windows.menu.inAll("windows")))

  function refresh() {
    if (clientsProc.running) { refreshTimer.restart(); return }
    clientsProc.command = windows.menu.boundedCommand("hyprctl -j clients", 3, 1048576)
    clientsProc.running = true
  }

  function appInfo(cls) {
    var key = String(cls || "")
    if (!key) return null
    if (windows.appCache.hasOwnProperty(key)) return windows.appCache[key]
    var info = null
    try {
      var entry = DesktopEntries.heuristicLookup(key) || windows.webappEntry(key)
      if (entry) info = { name: String(entry.name || ""), icon: String(entry.icon || "") }
    } catch (e) {
      info = null
    }
    windows.appCache[key] = info
    return info
  }

  // A web app whose class names only its URL: its host against the
  // installed entries' names (Windows.webappKeys has the rules).
  function webappEntry(cls) {
    var keys = Windows.webappKeys(cls)
    if (keys.length === 0) return null
    var values = (DesktopEntries.applications && DesktopEntries.applications.values) || []
    for (var k = 0; k < keys.length; k++)
      for (var i = 0; i < values.length; i++)
        if (values[i] && Windows.normalizeName(values[i].name) === keys[k]) return values[i]
    return null
  }

  function rows(query) {
    return Windows.windowRows(windows.list, query, windows.appInfo)
  }

  // Not `focus`: every Item already has a `focus` property, which wins.
  function focusWindow(address) {
    var command = Windows.focusCommand(address)
    if (command) Quickshell.execDetached(command)
  }

  Connections {
    target: windows.menu
    function onOpenedChanged() {
      if (windows.menu.opened) windows.refresh()
    }
  }

  // Several events arrive for one change (openwindow, then the title), so
  // they are coalesced into one read.
  Timer {
    id: refreshTimer
    interval: 120
    onTriggered: windows.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!windows.menu.opened) return
      var name = String(event && event.name || "")
      if (/^(openwindow|closewindow|movewindow|movewindowv2|windowtitle|windowtitlev2|changefloatingmode)$/.test(name))
        refreshTimer.restart()
    }
  }

  Process {
    id: clientsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!windows.menu.opened) return
        windows.list = Windows.parseClients(text)
        if (windows.wanted) windows.menu.rebuildDisplay(true)
      }
    }
  }
}
