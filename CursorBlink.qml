import QtQuick

Timer {
  id: blink
  property bool active: false
  property bool on: true
  interval: 530
  repeat: true
  running: active
  onTriggered: on = !on
  onActiveChanged: pulse()

  function pulse() {
    on = true
    if (active) restart()
    else stop()
  }
}
