import QtQuick
import Quickshell
import Quickshell.Io

// The whole menu offscreen: the real Menu.qml, with Quickshell stood in for
// by the modules under imports/. Processes are answered from the fixtures
// (typing_cost.py); nothing is ever run.
Item {
  id: h
  property var fx: JSON.parse(harnessFixtures)
  property Item menu: menuObj

  function words() {
    return String(menuObj.filterText || "").toLowerCase().trim().split(/\s+/).filter(function(w) { return w.length > 0 })
  }
  // fd: the fixture paths whose name holds every word typed.
  function fd(argv) {
    var dirs = false
    for (var i = 0; i < argv.length - 1; i++) if (argv[i] === "--type" && argv[i + 1] === "d") dirs = true
    var list = dirs ? h.fx.folders : h.fx.files
    var ws = h.words()
    var out = []
    for (var k = 0; k < list.length && out.length < 50; k++) {
      var name = list[k].toLowerCase().split("/").pop()
      var ok = ws.length > 0
      for (var w = 0; w < ws.length; w++) if (name.indexOf(ws[w]) < 0) ok = false
      if (ok) out.push(h.fx.home + "/" + list[k] + (dirs ? "/" : ""))
    }
    return out.join("\0") + (out.length ? "\0" : "")
  }
  // stat: a fixed modification time per path.
  function stat(argv) {
    var at = argv.indexOf("--")
    var out = ""
    for (var i = at + 1; i < argv.length; i++) {
      var hash = 0
      for (var c = 0; c < argv[i].length; c++) hash = (hash * 31 + argv[i].charCodeAt(c)) % 100003
      out += (1759000000 - (hash % 400) * 86400) + "\t" + argv[i] + "\0"
    }
    return out
  }
  function respond(argv) {
    var s = (argv || []).join(" ")
    if (argv.indexOf("fd") >= 0) return { out: h.fd(argv), code: 0 }
    if (argv.indexOf("stat") >= 0) return { out: h.stat(argv), code: 0 }
    if (s.indexOf("hyprctl -j clients") >= 0) return { out: JSON.stringify(h.fx.clients), code: 0 }
    var rules = h.fx.rules || []
    for (var i = 0; i < rules.length; i++)
      if (s.indexOf(rules[i].match) >= 0) return { out: rules[i].out, code: rules[i].code || 0 }
    return { out: "", code: 0 }
  }

  Component.onCompleted: ProcStub.handler = h.respond
  // qmlprofiler records between these (--record off).
  function profileStart() { console.profile() }
  function profileStop() { console.profileEnd() }

  Menu { id: menuObj }
}
