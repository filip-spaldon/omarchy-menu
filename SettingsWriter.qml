import Quickshell.Io
import "Settings.js" as Settings

// One ordered queue per view; the helper's lock serializes different views.
Process {
  id: writer
  required property string directory
  required property string path
  property int maxBytes: Settings.STATE_MAX_BYTES
  property var pending: []
  signal saved(string text)
  signal failed(string message)

  function save(operations) {
    pending = pending.concat(operations)
    Qt.callLater(startNext)
  }

  function startNext() {
    if (running || pending.length === 0) return
    command = Settings.writeCommand(directory, path, pending, maxBytes)
    pending = []
    running = true
  }

  stdout: StdioCollector { id: output; waitForEnd: true }
  onExited: function(exitCode, exitStatus) {
    if (exitCode !== 0 || exitStatus !== 0) {
      pending = []
      writer.failed("Could not save " + path.slice(path.lastIndexOf("/") + 1) + "; reopen settings to retry")
      return
    }
    if (pending.length === 0) writer.saved(output.text)
    else Qt.callLater(startNext)
  }
}
