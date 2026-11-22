import QtQuick
import qs.Commons
import "FileSearch.js" as FileSearch

// Files and Folders: the type chips (Ctrl+F), where to look when there are
// search roots (Ctrl+R) and the sort with its count (Ctrl+S, Ctrl+L). The
// card draws it under the tabs; the full-screen looks draw it in their own
// type and case, so every look shows which filter, scope and sort is on.
Item {
  id: bar
  required property var menu
  property color ink: bar.menu.foreground
  property string chipStyle: bar.menu.filterTabStyle
  property string chipCase: bar.menu.tabCase
  property int fontSize: bar.menu.scaledFont(Style.font.caption)
  property bool quiet: bar.menu.quietMeta
  // The scope row keeps plain chips on the card; a view can match its chips.
  property string scopeStyle: "chip"
  property string scopeCase: "title"
  readonly property var files: bar.menu.fileSearch

  visible: bar.menu.fileBarShown
  height: visible ? chips.implicitHeight + (scope.visible ? Style.space(6) + scope.implicitHeight : 0) : 0

  TabBar {
    id: chips
    anchors.left: parent.left
    width: parent.width - sortLabel.implicitWidth - Style.space(12)
    tabs: FileSearch.filtersFor(bar.menu.activeTab).map(function(f) { return { id: f.id, label: f.label, icon: "" } })
    activeTab: bar.files.fileFilterFor(bar.menu.activeTab).id
    fontFamily: bar.menu.fontFamily
    foreground: bar.ink
    accent: Color.accent
    fontSize: bar.fontSize
    anim: bar.menu.tabAnim
    tabStyle: bar.chipStyle
    tabCase: bar.chipCase
    background: bar.menu.background
    onTabClicked: function(id) {
      bar.files.setFileFilter(id)
      bar.menu.refocus()
    }
  }

  // Where to look: everywhere, $HOME only, or one search root (Ctrl+R).
  // Only there when a root is.
  TabBar {
    id: scope
    visible: bar.files.hasRoots
    anchors.left: parent.left
    anchors.top: chips.bottom
    anchors.topMargin: Style.space(6)
    width: parent.width
    tabs: bar.files.scopeChoices
    activeTab: bar.files.currentScope()
    fontFamily: bar.menu.fontFamily
    foreground: bar.ink
    accent: Color.accent
    fontSize: bar.fontSize
    tabStyle: bar.scopeStyle
    tabCase: bar.scopeCase
    background: bar.menu.background
    onTabClicked: function(id) {
      bar.files.setRootScope(id)
      bar.menu.refocus()
    }
  }

  Text {
    id: sortLabel
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.top: parent.top
    // A quiet look keeps only the sort, without icon or counter.
    readonly property var sort: FileSearch.sortMode(bar.files.fileSortMode)
    text: bar.quiet
      ? (bar.files.fileSearching ? "searching…" : sort.label.toLowerCase())
      : (bar.files.fileSearching ? "searching… · " : "") + sort.icon + " " + sort.label
        + " · " + bar.menu.resultCount + "/" + bar.files.fileDisplayLimit
    color: bar.ink
    opacity: 0.5
    font.family: bar.menu.fontFamily
    font.pixelSize: bar.fontSize
  }
}
