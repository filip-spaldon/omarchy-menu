import QtQuick
QtObject {
  property string path: ""
  property bool preload: false
  property bool watchChanges: false
  property bool printErrors: true
  property bool blockLoading: false
  property bool blockAllReads: false
  signal fileChanged()
  signal loaded()
  signal loadFailed(int error)
  function text() { return "" }
  function reload() {}
  function setText(t) {}
}
