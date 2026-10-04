import QtQuick
import Quickshell.Io
// Stub: asks ProcStub.handler for the output, a turn later, like a process.
QtObject {
  id: proc
  property var command: []
  property var environment: ({})
  property bool clearEnvironment: false
  property string workingDirectory: ""
  property bool stdinEnabled: false
  property bool running: false
  property int processId: 0
  property QtObject stdout: null
  property QtObject stderr: null
  property string sent: ""
  signal started()
  signal exited(int exitCode, int exitStatus)
  function write(data) { proc.sent += data }
  function startDetached() {}
  property int serial: 0
  onRunningChanged: if (running) { proc.serial += 1; var s = proc.serial; Qt.callLater(function() { proc.finish(s) }) }
  function finish(s) {
    if (!proc.running || s !== proc.serial) return
    ProcStub.runs += 1
    proc.started()
    var r = ProcStub.handler ? ProcStub.handler(proc.command) : null
    var out = r && r.out ? String(r.out) : ""
    var code = r && r.code !== undefined ? r.code : 0
    if (proc.stdout) {
      if (proc.stdout.read !== undefined && proc.stdout.splitMarker !== undefined) {
        var lines = out.split("\n")
        for (var i = 0; i < lines.length; i++) if (lines[i] !== "" || i < lines.length - 1) proc.stdout.read(lines[i])
      } else {
        proc.stdout.text = out
        proc.stdout.streamFinished()
      }
    }
    if (proc.stderr && proc.stderr.text !== undefined) { proc.stderr.text = ""; proc.stderr.streamFinished() }
    proc.running = false
    proc.exited(code, 0)
  }
}
