import QtQuick
import Quickshell
import Quickshell.Io
import "Clipboard.js" as Clipboard
import "Settings.js" as Settings

// Clipboard history for the Clipboard tab. The launcher never reads the
// clipboard: it reads the history Omarchy's own clipboard service keeps
// (Omarchy 4.5+), read-only through the guarded file reader, once per open
// and only when the tab is shown. Actions use the selected snapshot entry
// so another copy cannot change what they act on. Parsing, rows and argv are
// Clipboard.js; this file does the I/O. Never part of All: whatever was
// copied stays out of a search that was not asked of the clipboard.
Item {
  id: clip

  required property var menu

  // Parsed by Clipboard.parseHistory; emptied when the menu closes.
  property var entries: []
  // Image files a thumbnail may be drawn from, { path: true }
  // (Clipboard.previewablePaths): filled by one stat after the history is
  // read, so a row shows its picture only once its file has passed.
  property var previewable: ({})
  // "idle" until read this open, then "loading", "ready", "missing" (no
  // history file, or Omarchy's helpers are not installed) or "error".
  property string status: "idle"
  property bool historyRead: false
  property bool helpersChecked: false
  property bool helpersPresent: false
  property string historyStatus: ""
  // The type filter (Clipboard.FILTERS), cycled with Ctrl+F or picked from
  // the chips; back to All Types on every open, like the Files filter.
  property int filterIndex: 0
  readonly property var filter: Clipboard.filterAt(clip.filterIndex)
  // How a paste reaches the window under the launcher: "terminal"
  // (Ctrl+Shift+V) or "app" (Shift+Insert), from Clipboard.pasteModeFor. Read
  // with the history; "app" until it answers.
  property string pasteMode: "app"

  readonly property string binDir: clip.menu.omarchyPath ? clip.menu.omarchyPath + "/bin" : ""
  readonly property string homeDir: Quickshell.env("HOME") || ""
  // Where Omarchy's Clipboard.qml keeps the history and its helpers look
  // entries up -- under $HOME, whatever XDG_STATE_HOME says.
  readonly property string historyPath: clip.homeDir + "/.local/state/omarchy/clipboard-history.json"
  // Where Omarchy's capture script saves copied images.
  readonly property string imageDir: (Quickshell.env("XDG_STATE_HOME") || clip.homeDir + "/.local/state")
    + "/omarchy/clipboard-images/"

  readonly property bool clipboardNeeded: clip.menu.opened && !clip.menu.dmenuActive
    && clip.menu.activeTab === "clipboard"
  property bool readThisOpen: false
  onClipboardNeededChanged: {
    if (!clip.clipboardNeeded || clip.readThisOpen) return
    clip.readThisOpen = true
    clip.refresh()
  }

  // A read still running from the previous open is let finish, then the
  // history is read again for this one.
  property bool rereadPending: false

  function refresh() {
    if (!clip.homeDir || !clip.binDir) {
      clip.status = "missing"
      return
    }
    if (historyProc.running || helperProc.running) {
      clip.rereadPending = true
      return
    }
    clip.status = "loading"
    if (!activeWindowProc.running) {
      clip.pasteMode = "app"
      activeWindowProc.command = Clipboard.activeWindowCommand()
      activeWindowProc.running = true
    }
    clip.previewable = ({})
    clip.historyRead = false
    clip.helpersChecked = false
    helperProc.command = Clipboard.helpersCheckCommand(clip.binDir)
    helperProc.running = true
    historyProc.command = Settings.readFileCommand(clip.historyPath, Clipboard.MAX_HISTORY_BYTES, 5)
    historyProc.running = true
  }

  function settle() {
    if (!clip.historyRead || !clip.helpersChecked) return
    if (clip.rereadPending) {
      clip.rereadPending = false
      if (clip.clipboardNeeded) clip.refresh()
      return
    }
    if (!clip.menu.opened) return
    clip.status = !clip.helpersPresent ? "missing" : clip.historyStatus
    if (clip.menu.activeTab === "clipboard") clip.menu.rebuildDisplay(true)
    if (clip.status === "ready") clip.checkImages()
  }

  // The image files are looked at once per read, after the list is on
  // screen: one stat, bounded in time, NUL-separated. Until it answers (or
  // if it fails) image rows keep their icon.
  function checkImages() {
    const command = Clipboard.imageStatCommand(clip.entries)
    if (!command || imageStatProc.running) return
    imageStatProc.entries = clip.entries
    imageStatProc.command = command
    imageStatProc.running = true
  }

  function rows(query) {
    return clip.status === "ready" ? Clipboard.clipboardRows(clip.entries, query, clip.previewable, clip.filter.id) : []
  }

  function cycleFilter() {
    clip.filterIndex = (clip.filterIndex + 1) % Clipboard.FILTERS.length
    clip.applyFilter()
  }

  function setFilter(id) {
    const i = Clipboard.filterIndex(id)
    if (i < 0) return
    clip.filterIndex = i
    clip.applyFilter()
  }

  function applyFilter() {
    if (clip.menu.activeTab !== "clipboard") return
    clip.menu.selectedIndex = 0
    clip.menu.rebuildDisplay()
  }

  // What the empty list says when there is nothing to show.
  function emptyText() {
    if (clip.status === "idle" || clip.status === "loading") return "Reading clipboard history…"
    if (clip.status === "missing") return "No clipboard history: it comes from Omarchy's clipboard service (Omarchy 4.5+), which is off or has not saved anything yet"
    if (clip.status === "error") return "Could not read Omarchy's clipboard history"
    if (clip.entries.length === 0) return "Clipboard history is empty"
    return Clipboard.emptyFilterText(clip.entries, clip.filter.id)
  }

  // Closes the menu first, so the paste lands in the window that had focus.
  function paste(index, copyOnly) {
    clip.runAction(index, copyOnly ? "copy" : "paste")
  }

  function open(index) {
    clip.runAction(index, "open")
  }

  function runAction(index, operation) {
    if (actionProc.running) return
    const action = Clipboard.actionFor(Clipboard.entryAt(clip.entries, index), clip.binDir, operation,
                                          clip.previewable, clip.pasteMode)
    if (!action) return
    clip.menu.closeLauncher()
    if (action.input === undefined) {
      Quickshell.execDetached(action.command)
      return
    }
    actionProc.command = action.command
    actionProc.input = action.input
    actionProc.edit = action.edit === true
    actionProc.stdinEnabled = true
    actionProc.running = true
  }

  Process {
    id: actionProc
    property string input: ""
    property bool edit: false
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onStarted: {
      actionProc.write(actionProc.input)
      actionProc.input = ""
      actionProc.stdinEnabled = false
    }
    onExited: function(exitCode, exitStatus) {
      actionProc.input = ""
      if (!actionProc.edit || exitCode !== 0 || exitStatus) return
      const path = actionOut.text
      if (path && path.charAt(0) === "/" && path.length <= 4096)
        Quickshell.execDetached([clip.binDir + "/omarchy-launch-editor", path])
    }
  }

  // Closed, the history is dropped rather than kept in memory: the next
  // open reads it again.
  Connections {
    target: clip.menu
    function onOpenedChanged() {
      if (clip.menu.opened) return
      clip.readThisOpen = false
      clip.entries = []
      clip.previewable = ({})
      clip.status = "idle"
      clip.pasteMode = "app"
    }
  }

  Process {
    id: activeWindowProc
    stdout: StdioCollector {
      id: activeWindowOut
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      if (!clip.menu.opened) return
      clip.pasteMode = exitCode === 0 && !exitStatus ? Clipboard.pasteModeFor(activeWindowOut.text || "") : "app"
    }
  }

  Process {
    id: helperProc
    onExited: function(exitCode, exitStatus) {
      clip.helpersPresent = exitCode === 0 && !exitStatus
      clip.helpersChecked = true
      clip.settle()
    }
  }

  Process {
    id: imageStatProc
    // The entries the stat was started for: an answer for an older read is
    // dropped rather than applied to a newer one.
    property var entries: []
    stdout: StdioCollector {
      id: imageStatOut
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      // stat exits 1 when one file is gone; the records it did print stand.
      if (!clip.menu.opened) return
      // Started for a read that has since been replaced: look again for this one.
      if (imageStatProc.entries !== clip.entries) {
        if (clip.status === "ready") Qt.callLater(clip.checkImages)
        return
      }
      if (exitStatus) return
      clip.previewable = Clipboard.previewablePaths(imageStatOut.text || "", clip.entries, Clipboard.MAX_IMAGE_BYTES)
      if (clip.menu.activeTab === "clipboard") clip.menu.rebuildDisplay(true)
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector {
      id: historyOut
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      // The reader exits 2 for a missing file, anything else non-zero for a
      // refused (symlink, not ours, too large) or failed read.
      const text = historyOut.text
      if (exitStatus || (exitCode !== 0 && exitCode !== 2)) {
        clip.entries = []
        clip.historyStatus = "error"
      } else if (exitCode === 2) {
        clip.entries = []
        clip.historyStatus = "missing"
      } else {
        clip.entries = clip.menu.opened ? Clipboard.parseHistory(text, clip.imageDir) : []
        clip.historyStatus = "ready"
      }
      clip.historyRead = true
      clip.settle()
    }
  }
}
