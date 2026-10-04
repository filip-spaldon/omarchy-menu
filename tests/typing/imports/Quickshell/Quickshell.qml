pragma Singleton
import QtQuick
// Stub: environment from the harness, nothing is ever launched.
QtObject {
  property var envMap: typeof harnessFixtures === "string" ? JSON.parse(harnessFixtures).env : ({})
  property var launched: []
  function env(name) { return envMap[name] !== undefined ? envMap[name] : "" }
  function execDetached(argv) { launched.push(argv) }
  function iconPath(name, check) { return "" }
}
