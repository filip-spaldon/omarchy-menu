import QtQuick
import Quickshell.Io

// Whether a file may have changed since it was last read. The menu re-reads
// its sources on every open, so live edits land without a restart; each read
// is a guarded process (Settings.readFileCommand), and six of them ran on
// every open. A reader asks `stale` first and skips the read when nothing
// changed.
//
// Only watches. The FileView never loads the file (preload: false); content
// is still read through the guarded reader alone. Checked on Quickshell
// 0.3.1: change events arrive for writes in place and for atomic saves
// (write a temporary file, rename it over), and the watch survives a rename.
Item {
  id: watch

  property string path: ""

  // True until the first read, after every change, and after a read that
  // failed for a reason the file itself does not explain (a timeout).
  property bool stale: true

  // A read is starting. A change that lands while it runs sets `stale`
  // again, so the next open reads the newer content.
  function beginRead() {
    watch.stale = false
  }

  // Exit 2 means missing; exit 1 means a refused or unreadable file: a
  // symlink, the wrong owner, too large. That only changes when the file
  // does, and the watch reports it -- including a missing file being
  // created, since FileView watches the directory for it (checked on 0.3.1).
  // Anything else (124 is a timeout) is retried on the next open.
  function readFailed(exitCode) {
    if (exitCode !== 2) watch.stale = true
  }

  FileView {
    path: watch.path
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: watch.stale = true
  }
}
