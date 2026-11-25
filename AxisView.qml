import QtQuick
import qs.Commons
import "Tabs.js" as Tabs
import "KeySheet.js" as KeySheet

// The Axis look: no card. Two hairlines cross the screen: the horizontal one
// carries what you typed, the vertical one what exists, and the row at the
// crossing is what Enter does. The list moves through the crossing; the
// crossing stays put, so the eye does not travel. The card keeps the keyboard
// (it stays alive, invisible), so every key works exactly as in the other
// looks; this only draws. The 3x3 position picks which rule-of-thirds point
// the lines cross at.
Item {
  id: axis
  required property var menu
  required property var model
  // A backdrop shader (none yet) would draw the ember's light; the disc
  // then steps aside.
  property bool hasBackdrop: false
  // The app tiles: All's strips are as wide as the list, and the Apps grid
  // has as many columns as fit there (Menu.qml reads both).
  readonly property real tileAreaWidth: list.width
  readonly property int gridColumns: grid.columns
  readonly property bool gridShown: axis.menu.gridActive
  // Where in a tile the horizontal line crosses: under the icon (AxisTile).
  readonly property real tileLine: Style.space(12) + Math.round(Style.space(36) * axis.menu.menuFontScale) + Style.space(5)

  // Where the lines cross, from the card position: left/centre/right and
  // top/middle/bottom map to thirds and the middle.
  readonly property real crossX: Math.round(width * ({ left: 0.36, center: 0.46, right: 0.58 })[axis.menu.launcherPosition.anchorX])
  readonly property real crossY: Math.round(height * ({ top: 0.4, middle: 0.5, bottom: 0.6 })[axis.menu.launcherPosition.anchorY])
  readonly property color ink: axis.menu.foreground
  // System: categories on the left of the vertical line, their items on the
  // right, meeting at the crossing. Where you are stands on the line in the
  // query's place, the tabs under it, as in every other tab.
  readonly property bool sys: axis.menu.systemTwoPane
  readonly property bool leftPane: axis.sys && axis.menu.systemPane === "left"
  readonly property int hair: Math.max(1, Style.spacing.hairline)
  // The "?" key sheet (Ctrl+?): "Every key" stands on the line in the
  // query's place, the keys hang off the vertical line as the results do.
  readonly property bool sheet: axis.menu.cheatOpen

  // The lines, drawn in from the edges each time the view appears.
  property real reach: 0
  // Also when the view is made already visible (Alt+L to Axis with the
  // menu open): no visibleChanged comes then, and the lines would stay unset.
  function drawLines() { axis.reach = 0; drawIn.restart() }
  onVisibleChanged: if (visible) axis.drawLines()
  Component.onCompleted: if (visible) axis.drawLines()
  NumberAnimation { id: drawIn; target: axis; property: "reach"; from: 0; to: 1; duration: 160; easing.type: Easing.OutExpo }

  Rectangle {
    y: axis.crossY
    x: axis.crossX * (1 - axis.reach)
    width: axis.width * axis.reach
    height: axis.hair
    color: Util.alpha(axis.ink, 0.28)
  }

  Rectangle {
    x: axis.crossX
    y: axis.crossY * (1 - axis.reach)
    height: axis.height * axis.reach
    width: axis.hair
    color: Util.alpha(axis.ink, 0.28)
  }

  // Ticks along the query line, like a ruler.
  Repeater {
    model: Math.max(0, Math.floor(axis.crossX / Style.space(40)))
    Rectangle {
      required property int index
      x: axis.crossX - (index + 1) * Style.space(40)
      y: axis.crossY - (index % 5 === 4 ? Style.space(5) : Style.space(3))
      width: axis.hair
      height: index % 5 === 4 ? Style.space(10) : Style.space(6)
      color: Util.alpha(axis.ink, 0.22)
    }
  }

  // The query, standing on the line; its faint reflection below it.
  Text {
    id: queryText
    visible: !axis.sys || axis.sheet
    readonly property bool empty: !axis.menu.filterText && !axis.sheet
    x: Math.round(axis.crossX * 0.14)
    width: axis.crossX - x - Style.space(40)
    y: axis.crossY - height + Math.round(font.pixelSize * 0.22)
    textFormat: Text.PlainText
    text: axis.sheet ? "Every key" : (empty ? axis.menu.promptText() : axis.menu.filterText)
    color: axis.ink
    opacity: empty ? 0.35 : 1
    elide: Text.ElideLeft
    font.family: "Noto Serif"
    font.weight: Font.Light
    font.pixelSize: Math.round(axis.menu.scaledFont(Style.font.heading) * (empty ? 1.6 : 3.2))
  }

  Rectangle {
    visible: !axis.sys && !axis.sheet && !queryText.empty && axis.menu.opened
    x: queryText.x + Math.min(queryText.contentWidth, queryText.width) + Style.space(6)
    width: Math.max(2, Math.round(queryText.font.pixelSize / 28))
    height: Math.round(queryText.font.pixelSize * 0.8)
    y: axis.crossY - height - Style.space(4)
    color: Color.accent
  }

  Text {
    visible: queryText.visible && !queryText.empty
    x: queryText.x
    width: queryText.width
    y: axis.crossY + Style.space(2)
    textFormat: Text.PlainText
    text: queryText.text
    elide: Text.ElideLeft
    color: axis.ink
    opacity: 0.07
    font: queryText.font
    transform: Scale { yScale: -0.6; origin.y: 0 }
  }

  Text {
    x: queryText.x
    y: axis.crossY - queryText.height - Style.space(28)
    textFormat: Text.PlainText
    visible: !axis.sys || axis.sheet
    text: axis.menu.positionHint || (axis.sheet ? "KEYS" : "QUERY")
    color: axis.ink
    opacity: 0.4
    font.family: axis.menu.fontFamily
    font.pixelSize: axis.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 2
  }

  // System's header: where you are and what you typed, standing on the line
  // where the query stands in the other tabs. It ends well short of the
  // crossing, where the chosen category sits on the same line.
  Text {
    id: sysCrumb
    visible: axis.sys && !axis.sheet
    x: queryText.x
    width: Math.max(0, axis.crossX - x - Style.space(200))
    y: axis.crossY - height + Math.round(font.pixelSize * 0.22)
    textFormat: Text.PlainText
    readonly property string path: axis.menu.activeMenu === "root" ? "" : axis.menu.pathFor(axis.menu.activeMenu)
    text: "System" + (path ? "  ›  " + path : "") + (axis.menu.filterText ? "  ·  " + axis.menu.filterText : "")
    color: axis.ink
    elide: Text.ElideRight
    font.family: "Noto Serif"
    font.weight: Font.Light
    font.pixelSize: Math.round(axis.menu.scaledFont(Style.font.heading) * 1.6)
  }

  TabBar {
    id: tabs
    x: queryText.x
    // In System, short of the category labels right-aligned below the line.
    width: axis.sys ? Math.max(0, axis.crossX - x - Style.space(150)) : queryText.width
    y: axis.crossY + Style.space(56)
    // Over System's category rows, which span the left side for their clicks.
    z: 1
    tabs: axis.menu.orderedTabs
    numbered: axis.menu.ctrlHeld
    activeTab: axis.menu.activeTab
    fontFamily: axis.menu.fontFamily
    foreground: axis.ink
    accent: Color.accent
    fontSize: axis.menu.scaledFont(Style.font.caption)
    anim: axis.menu.tabAnim
    tabStyle: "word"
    tabCase: "upper"
    background: axis.menu.background
    onTabClicked: function(id) { axis.menu.setTab(id) }
  }

  // Files and Folders: the type, where to look and the sort, in the tabs' type.
  FileBar {
    visible: !axis.sheet && (axis.menu.fileBarShown || axis.menu.clipboardBarShown)
    menu: axis.menu
    x: queryText.x
    width: queryText.width
    y: tabs.y + tabs.height + Style.space(14)
    ink: axis.ink
    chipStyle: "word"
    chipCase: "upper"
    scopeStyle: "word"
    scopeCase: "upper"
  }

  // Nothing found: said on the line, where the first result would cross.
  Text {
    visible: !axis.sys && !axis.sheet && list.count === 0 && text !== ""
    x: list.x + Style.space(12)
    width: list.width - Style.space(12)
    y: axis.crossY - height - Style.space(6)
    textFormat: Text.PlainText
    text: axis.menu.emptyText
    elide: Text.ElideRight
    color: axis.ink
    opacity: 0.6
    font.family: "Noto Serif"
    font.weight: Font.Light
    font.pixelSize: axis.menu.scaledFont(Style.font.heading)
  }

  // What exists: the results hanging off the vertical line. The selected row
  // is held at the crossing by moving the list itself. Not with the view's
  // own highlight range (StrictlyEnforceRange): re-binding its range while the
  // model is updated in place crashed the shell (QQuickItemView::
  // setPreferredHighlightBegin), so the pinning is done here, only while shown.
  ListView {
    id: list
    visible: !axis.gridShown && !axis.sheet
    opacity: axis.leftPane ? 0.55 : 1
    x: axis.crossX + Style.space(20)
    width: Math.min(Style.space(760), axis.width - x - Style.space(48))
    y: 0
    height: axis.height
    model: axis.model
    spacing: axis.menu.rowSpacing
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // Room above the first row and below the last, so either can sit on the line.
    topMargin: axis.crossY
    bottomMargin: axis.height - axis.crossY

    Behavior on contentY { enabled: list.gliding; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    property bool gliding: false

    function pin(glide) {
      if (!axis.visible || list.count === 0 || axis.gridShown) return
      var index = Math.max(0, Math.min(axis.menu.selectedIndex, list.count - 1))
      // An app tile of All's strips: the strip (its first row) is what crosses.
      var tile = axis.menu.allTileAt(index, axis.menu.layoutSerial)
      if (tile) index = tile.lead
      var item = list.itemAtIndex(index)
      if (!item) {
        list.positionViewAtIndex(index, ListView.Center)
        item = list.itemAtIndex(index)
      }
      if (!item) return
      list.gliding = glide
      list.contentY = item.y + (tile ? axis.tileLine : item.height / 2) - axis.crossY
      list.gliding = false
    }

    Connections {
      target: axis.menu
      function onSelectedIndexChanged() { Qt.callLater(list.pin, true) }
    }
    onCountChanged: Qt.callLater(list.pin, false)
    onHeightChanged: Qt.callLater(list.pin, false)
    Connections {
      target: axis
      function onVisibleChanged() { if (axis.visible) Qt.callLater(list.pin, false) }
      function onCrossYChanged() { Qt.callLater(list.pin, false) }
    }

    section.property: "section"
    section.criteria: ViewSection.FullString
    section.delegate: Item {
      required property string section
      width: ListView.view.width
      height: String(section).indexOf("hdr:") === 0 ? axis.menu.sectionHeaderHeight : 0
      visible: height > 0
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        textFormat: Text.PlainText
        text: Tabs.headerTitle(parent.section).toUpperCase()
        color: axis.ink
        opacity: 0.42
        font.family: axis.menu.fontFamily
        font.pixelSize: axis.menu.scaledFont(Style.font.caption)
        font.letterSpacing: 2
      }
      // "+4 IN FILES ⇥": what All's cap left out.
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        visible: parent.visible && text !== ""
        textFormat: Text.PlainText
        text: axis.menu.sectionMore(parent.section).toUpperCase()
        color: axis.ink
        opacity: 0.42
        font.family: axis.menu.fontFamily
        font.pixelSize: axis.menu.scaledFont(Style.font.caption)
        font.letterSpacing: 2
      }
    }

    delegate: ResultRow { menu: axis.menu }
  }

  // The Apps grid: rows of tiles hanging off the vertical line, the selected
  // one's row held on the horizontal line, as the list's selected row is. The
  // grid moves, the crossing stays.
  GridView {
    id: grid
    visible: axis.gridShown && !axis.sheet
    readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
    x: list.x
    width: Math.max(cellWidth, Math.floor(list.width / cellWidth) * cellWidth)
    y: 0
    height: axis.height
    cellWidth: axis.menu.tileWidth
    cellHeight: axis.menu.tileHeight
    model: axis.gridShown ? axis.model : null
    clip: true
    interactive: false
    topMargin: axis.crossY
    bottomMargin: axis.height - axis.crossY
    property bool gliding: false
    Behavior on contentY { enabled: grid.gliding; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    function pin(glide) {
      if (!axis.visible || !axis.gridShown || grid.count === 0) return
      var row = Math.floor(Math.max(0, Math.min(axis.menu.selectedIndex, grid.count - 1)) / grid.columns)
      grid.gliding = glide
      // The line runs just under the icons; the names hang below it.
      grid.contentY = row * grid.cellHeight + axis.tileLine - axis.crossY
      grid.gliding = false
    }
    Connections {
      target: axis.menu
      function onSelectedIndexChanged() { Qt.callLater(grid.pin, true) }
    }
    onCountChanged: Qt.callLater(grid.pin, false)
    onColumnsChanged: Qt.callLater(grid.pin, false)
    onVisibleChanged: if (visible) Qt.callLater(grid.pin, false)
    Connections {
      target: axis
      function onCrossYChanged() { Qt.callLater(grid.pin, false) }
    }

    // The pinned apps (the model's first rows), framed as on the card.
    PinnedFrame {
      parent: grid.contentItem
      z: -1
      menu: axis.menu
      visible: axis.menu.pinnedCount > 0
      width: grid.columns * grid.cellWidth
      height: Math.ceil(axis.menu.pinnedCount / grid.columns) * grid.cellHeight
    }

    delegate: LookTile {
      required property int index
      required property string label
      required property string appIcon
      required property string kind
      required property string appId
      required property string section
      // The pinned strip's padding cells draw nothing.
      visible: kind !== "pinpad"
      inPinnedStrip: section === axis.menu.pinnedSection
      menu: axis.menu
      tileIndex: index
      tileLabel: label
      tileIcon: appIcon
      tileKind: kind
      tileAppId: appId
      tileCol: index % grid.columns
      tileRow: Math.floor(index / grid.columns)
      width: grid.cellWidth - Style.space(6)
      height: grid.cellHeight - Style.space(6)
    }
  }

  // System's categories, right-aligned to the vertical line, the chosen one
  // held on the horizontal line like the selected item across from it.
  ListView {
    id: cats
    visible: axis.sys && !axis.sheet
    readonly property int rowH: axis.menu.baseRowHeight
    x: Style.space(48)
    width: axis.crossX - x - Style.space(24)
    y: 0
    height: axis.height
    model: axis.sys ? axis.menu.systemCategories : []
    clip: true
    interactive: false
    topMargin: axis.crossY
    bottomMargin: axis.height - axis.crossY
    property bool gliding: false
    Behavior on contentY { enabled: cats.gliding; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    function pin(glide) {
      if (!axis.visible || !axis.sys || cats.count === 0) return
      var index = Math.max(0, Math.min(axis.menu.systemCategoryIndex, cats.count - 1))
      var item = cats.itemAtIndex(index)
      if (!item) { cats.positionViewAtIndex(index, ListView.Center); item = cats.itemAtIndex(index) }
      if (!item) return
      cats.gliding = glide
      cats.contentY = item.y + item.height / 2 - axis.crossY
      cats.gliding = false
    }
    Connections {
      target: axis.menu
      function onSystemCategoryIndexChanged() { Qt.callLater(cats.pin, true) }
    }
    onCountChanged: Qt.callLater(cats.pin, false)
    Connections {
      target: axis
      function onSysChanged() { if (axis.sys) Qt.callLater(cats.pin, false) }
      function onVisibleChanged() { if (axis.visible) Qt.callLater(cats.pin, false) }
      // The window is one pixel while closed and grows on open: pin again
      // once the crossing has its real place.
      function onCrossYChanged() { Qt.callLater(cats.pin, false) }
    }

    delegate: Item {
      id: cat
      required property var modelData
      required property int index
      readonly property bool picked: cat.index === axis.menu.systemCategoryIndex
      width: ListView.view.width
      height: cats.rowH
      opacity: Math.max(0.2, 1 - Math.abs(cat.index - axis.menu.systemCategoryIndex) * 0.14) * (axis.leftPane || cat.picked ? 1 : 0.7)

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)
        layoutDirection: Qt.RightToLeft
        Text {
          textFormat: Text.PlainText
          text: cat.modelData.icon
          color: cat.picked ? Color.accent : axis.ink
          font.family: cat.modelData.iconFont || axis.menu.fontFamily
          font.pixelSize: axis.menu.scaledFont(Style.font.iconLarge)
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: cat.modelData.label
          color: axis.ink
          font.family: axis.menu.fontFamily
          font.pixelSize: axis.menu.scaledFont(cat.picked ? Style.font.title : Style.font.heading)
          font.weight: cat.picked ? Font.DemiBold : Font.Normal
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: cat.picked ? axis.menu.activateSystemCategory() : axis.menu.selectSystemCategory(cat.index)
      }
    }
  }

  // The key sheet: one column off the vertical line, every group's title in
  // the labels' spaced capitals with a tick on the line, each key in spaced
  // capitals and what it does in the query's serif. Centred on the crossing,
  // kept on screen; the lines tighten when the screen is short.
  Loader {
    id: sheetLoader
    active: axis.sheet
    x: axis.crossX + Style.space(20)
    y: sheetLoader.item ? Math.round(Math.max(axis.height * 0.07, Math.min(axis.crossY - sheetLoader.item.height / 2,
                                                                         axis.height * 0.93 - sheetLoader.item.height))) : 0
    width: Math.max(0, axis.width - x - Style.space(48))
    sourceComponent: Item {
      id: keys
      readonly property var lines: KeySheet.sheetLines()
      readonly property int lineH: Math.max(Style.space(14), Math.min(Math.round(axis.menu.scaledFont(Style.font.body) * 1.75),
                                                                    Math.floor(axis.height * 0.86 / Math.max(1, keys.lines.length))))
      readonly property int keyW: Style.space(190)
      width: parent ? parent.width : 0
      height: keys.lines.length * keys.lineH

      Column {
        Repeater {
          model: keys.lines
          Item {
            id: line
            required property var modelData
            readonly property bool title: line.modelData.title !== undefined
            width: keys.width
            height: keys.lineH

            Rectangle {
              visible: line.title
              x: -Style.space(26)
              width: Style.space(12)
              height: axis.hair
              anchors.verticalCenter: parent.verticalCenter
              color: Util.alpha(axis.ink, 0.5)
            }
            Text {
              visible: line.title
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Math.round(keys.lineH * 0.2)
              textFormat: Text.PlainText
              text: line.title ? line.modelData.title.toUpperCase() : ""
              color: axis.ink
              opacity: 0.42
              font.family: axis.menu.fontFamily
              font.pixelSize: axis.menu.scaledFont(Style.font.caption)
              font.letterSpacing: 2
            }
            Text {
              visible: !line.title
              width: keys.keyW
              anchors.baseline: does.baseline
              textFormat: Text.PlainText
              text: line.title ? "" : line.modelData.key.toUpperCase()
              elide: Text.ElideRight
              color: axis.ink
              opacity: 0.7
              font.family: axis.menu.fontFamily
              font.pixelSize: axis.menu.scaledFont(Style.font.caption)
              font.letterSpacing: 2
            }
            Text {
              id: does
              visible: !line.title
              x: keys.keyW + Style.space(12)
              width: Math.max(0, keys.width - x)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: line.title ? "" : line.modelData.does
              elide: Text.ElideRight
              color: axis.ink
              font.family: "Noto Serif"
              font.weight: Font.Light
              font.pixelSize: Math.min(axis.menu.scaledFont(Style.font.body), Math.round(keys.lineH * 0.62))
            }
          }
        }
      }
    }
  }

  // The crossing: an ember where the selected row meets the line.
  Rectangle {
    visible: !axis.hasBackdrop
    readonly property int size: Style.space(90)
    x: axis.crossX - size / 2
    y: axis.crossY - size / 2
    width: size
    height: size
    radius: size / 2
    color: Util.alpha(Color.accent, 0.08)
  }

  Rectangle {
    x: axis.crossX - width / 2
    y: axis.crossY - height / 2
    width: Style.space(9)
    height: width
    radius: width / 2
    color: Color.accent
  }

  Text {
    x: queryText.x
    // Wraps short of the vertical line, its last line where one line stood.
    width: Math.max(Style.space(200), axis.crossX - x - Style.space(24))
    y: axis.height - Style.space(32) - height
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    // Every key of the tab (Menu.tabKeys), as in every look.
    text: axis.menu.viewFooterHints()
    color: axis.ink
    opacity: 0.45
    font.family: axis.menu.fontFamily
    font.pixelSize: axis.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 1
  }
}
