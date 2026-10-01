import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Windows.js" as Windows

// Open windows for the Windows tab, All's Windows section and the running
// marker in Apps. The list is read from `hyprctl -j clients` each time the
// menu opens, and again while it is open whenever Hyprland reports a window
// opening, closing, moving or being retitled. Parsing, ranking and matching
// are Windows.js; this file does the I/O and the desktop-entry lookups.
// Reaches the menu through `menu` for the tab, the query and redraws.
Item {
  id: tracker

  required property var menu

  // Parsed by Windows.parseClients.
  property var openWindows: []
  // Window class -> { id, name, icon } of its desktop entry, or null when
  // none matches. A Map, because window classes are arbitrary strings and
  // "__proto__" is not a safe plain-object key. Emptied whenever the
  // installed entries change, so a lookup made before they finished loading
  // is not remembered as a miss.
  property var appByClass: new Map()
  // Desktop entry id -> window addresses, most recent first. Replaced rather
  // than mutated, so the running markers bound to it re-evaluate.
  property var windowsByAppId: new Map()

  // Hyprland events that change what the list shows. Several can arrive for
  // one change (openwindow, then the title), so they restart a short timer
  // rather than each reading the list.
  readonly property var refreshEvents: [
    "openwindow", "closewindow",
    "movewindow", "movewindowv2",
    "windowtitle", "windowtitlev2",
    "changefloatingmode"
  ]

  // Something on screen uses the window list: the Windows tab, All's
  // search (its Windows section, and the running marker on its app rows),
  // or Apps (the running marker). The default open -- All, empty until
  // something is typed -- uses none of it, so the list is read the first
  // time it is needed in an open rather than on every open.
  readonly property bool windowsNeeded: tracker.menu.opened && !tracker.menu.dmenuActive
    && (tracker.menu.activeTab === "windows" || tracker.menu.activeTab === "apps"
        || (tracker.menu.activeTab === "all" && tracker.menu.filterText.trim() !== ""))
  property bool readThisOpen: false
  onWindowsNeededChanged: {
    if (!tracker.windowsNeeded || tracker.readThisOpen) return
    tracker.readThisOpen = true
    tracker.refresh()
  }

  readonly property bool windowRowsOnScreen: tracker.menu.opened && !tracker.menu.dmenuActive
    && (tracker.menu.activeTab === "windows"
        || (tracker.menu.activeTab === "all" && tracker.menu.inAll("windows")))

  function refresh() {
    if (clientsProc.running) {
      refreshTimer.restart()
      return
    }
    clientsProc.command = tracker.menu.boundedCommand("hyprctl -j clients", 3, 1048576)
    clientsProc.running = true
  }

  function appForClass(windowClass) {
    const key = String(windowClass || "")
    if (!key) return null
    if (tracker.appByClass.has(key)) return tracker.appByClass.get(key)

    let app = null
    try {
      const entry = DesktopEntries.heuristicLookup(key) || tracker.findWebappEntry(key)
      if (entry) app = { id: String(entry.id || ""), name: String(entry.name || ""), icon: String(entry.icon || "") }
    } catch (error) {
      app = null
    }
    tracker.appByClass.set(key, app)
    return app
  }

  // A web app whose class names only its URL: its host against the
  // installed entries' names (Windows.webappNameKeys has the rules).
  function findWebappEntry(windowClass) {
    const nameKeys = Windows.webappNameKeys(windowClass)
    if (nameKeys.length === 0) return null
    const entries = Array.from((DesktopEntries.applications && DesktopEntries.applications.values) || [])
    for (const nameKey of nameKeys) {
      const entry = entries.find(candidate => candidate && Windows.normalizeName(candidate.name) === nameKey)
      if (entry) return entry
    }
    return null
  }

  function updateWindowsByAppId() {
    tracker.windowsByAppId = Windows.windowsByAppId(tracker.openWindows, windowClass => {
      const app = tracker.appForClass(windowClass)
      return app ? app.id : ""
    })
  }

  function windowCountOf(appId) {
    const addresses = tracker.windowsByAppId.get(String(appId || ""))
    return addresses ? addresses.length : 0
  }

  // The address of an application's most recently focused window, or ""
  // when it has none open.
  function latestWindowOf(appId) {
    const addresses = tracker.windowsByAppId.get(String(appId || ""))
    return addresses && addresses.length > 0 ? addresses[0] : ""
  }

  function windowRows(query) {
    return Windows.windowRows(tracker.openWindows, query, tracker.appForClass)
  }

  // Not named `focus`: every Item already has a `focus` property, and the
  // property wins over a method of the same name.
  function focusWindow(address) {
    const command = Windows.focusCommand(address)
    if (command) Quickshell.execDetached(command)
  }

  // Closed, the list is no longer followed, so it is dropped rather than
  // kept stale: until the next open has read it again, Enter on an app
  // launches it (as before the running markers) instead of focusing a window
  // that may be gone, or launching a second copy of one that opened since.
  Connections {
    target: tracker.menu
    function onOpenedChanged() {
      if (tracker.menu.opened) return
      tracker.readThisOpen = false
      refreshTimer.stop()
      tracker.openWindows = []
      tracker.windowsByAppId = new Map()
    }
  }

  Timer {
    id: refreshTimer
    interval: 120
    onTriggered: tracker.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!tracker.readThisOpen) return
      const eventName = String((event && event.name) || "")
      if (tracker.refreshEvents.includes(eventName)) refreshTimer.restart()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      tracker.appByClass = new Map()
      tracker.updateWindowsByAppId()
    }
  }

  Process {
    id: clientsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!tracker.menu.opened) return
        tracker.openWindows = Windows.parseClients(text)
        tracker.updateWindowsByAppId()
        if (tracker.windowRowsOnScreen) tracker.menu.rebuildDisplay(true)
      }
    }
  }
}
