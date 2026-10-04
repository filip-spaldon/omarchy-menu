import QtQuick
import qs.Commons
import "Tabs.js" as Tabs

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
    visible: !axis.sys
    readonly property bool empty: !axis.menu.filterText
    x: Math.round(axis.crossX * 0.14)
    width: axis.crossX - x - Style.space(40)
    y: axis.crossY - height + Math.round(font.pixelSize * 0.22)
    textFormat: Text.PlainText
    text: empty ? axis.menu.promptText() : axis.menu.filterText
    color: axis.ink
    opacity: empty ? 0.35 : 1
    elide: Text.ElideLeft
    font.family: "Noto Serif"
    font.weight: Font.Light
    font.pixelSize: Math.round(axis.menu.scaledFont(Style.font.heading) * (empty ? 1.6 : 3.2))
  }

  Rectangle {
    visible: !axis.sys && !queryText.empty && axis.menu.opened
    x: queryText.x + Math.min(queryText.contentWidth, queryText.width) + Style.space(6)
    width: Math.max(2, Math.round(queryText.font.pixelSize / 28))
    height: Math.round(queryText.font.pixelSize * 0.8)
    y: axis.crossY - height - Style.space(4)
    color: Color.accent
  }

  Text {
    visible: !axis.sys && !queryText.empty
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
    visible: !axis.sys
    text: axis.menu.positionHint || "QUERY"
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
    visible: axis.sys
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
    x: queryText.x
    // In System, short of the category labels right-aligned below the line.
    width: axis.sys ? Math.max(0, axis.crossX - x - Style.space(150)) : queryText.width
    y: axis.crossY + Style.space(56)
    // Over System's category rows, which span the left side for their clicks.
    z: 1
    tabs: axis.menu.orderedTabs
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

  // What exists: the results hanging off the vertical line. The selected row
  // is held at the crossing by moving the list itself. Not with the view's
  // own highlight range (StrictlyEnforceRange): re-binding its range while the
  // model is updated in place crashed the shell (QQuickItemView::
  // setPreferredHighlightBegin), so the pinning is done here, only while shown.
  ListView {
    id: list
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
      if (!axis.visible || list.count === 0) return
      var index = Math.max(0, Math.min(axis.menu.selectedIndex, list.count - 1))
      var item = list.itemAtIndex(index)
      if (!item) {
        list.positionViewAtIndex(index, ListView.Center)
        item = list.itemAtIndex(index)
      }
      if (!item) return
      list.gliding = glide
      list.contentY = item.y + item.height / 2 - axis.crossY
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
    }

    delegate: ResultRow { menu: axis.menu }
  }

  // System's categories, right-aligned to the vertical line, the chosen one
  // held on the horizontal line like the selected item across from it.
  ListView {
    id: cats
    visible: axis.sys
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
    y: axis.height - Style.space(48)
    textFormat: Text.PlainText
    text: "↑↓ the list moves, the cross stays   ⇥ scope   ↵ open   esc let go"
    color: axis.ink
    opacity: 0.45
    font.family: axis.menu.fontFamily
    font.pixelSize: axis.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 1
  }
}
