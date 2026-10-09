pragma Singleton
import QtQuick
// The harness sets `handler(argv) -> { out, code }`; nothing runs.
QtObject {
  property var handler: null
  property int runs: 0
}
