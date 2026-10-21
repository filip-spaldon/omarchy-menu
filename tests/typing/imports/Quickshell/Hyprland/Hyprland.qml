pragma Singleton
import QtQuick
QtObject {
  signal rawEvent(var event)
  property var toplevels: ({ values: [] })
  property var workspaces: ({ values: [] })
  property var focusedMonitor: null
  function dispatch(s) {}
  function refreshToplevels() {}
  function refreshWorkspaces() {}
}
