import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Konstrukt.js" as Konstrukt
import "Tabs.js" as Tabs

// The Konstrukt look: every result appears twice, as a row in the list on the
// left and as a flat Suprematist shape in the field on the right. It looks
// like chaos; every property is data. Shape and colour = kind, size = how
// much of the name the query covers, tilt = age, place = rank on a sunflower
// spiral with the best in the middle. The list is grouped by section while the
// field interleaves the sections, so the connectors cross: that crossing is
// the chaos, the rules are the order. The card keeps the keyboard; this draws.
Item {
  id: kon
  required property var menu
  required property var model
  // Set when a backdrop shader draws the seeded ground (none yet); the
  // Canvas one then steps aside.
  property bool hasBackdrop: false

  // A colour per kind, from the theme's accent turned around the colour
  // wheel, so every theme gets its own set. Shape carries the kind too, so
  // colour is never the only difference.
  function kindColor(kind) {
    var a = Color.accent
    function turn(deg, light) {
      return Qt.hsla((a.hslHue + deg / 360 + 1) % 1, Math.min(1, a.hslSaturation * 0.9), light, 1)
    }
    if (kind === "app") return a
    if (kind === "file") return turn(-40, 0.72)
    if (kind === "folder") return Qt.rgba(kon.menu.foreground.r, kon.menu.foreground.g, kon.menu.foreground.b, 0.85)
    if (kind === "window") return turn(-80, 0.6)
    return turn(25, 0.62)
  }

  readonly property color ink: kon.menu.foreground
  readonly property int maxShapes: 36
  readonly property real listX: Math.round(width * 0.06)
  readonly property real listW: Math.round(width * 0.34)
  readonly property rect area: Qt.rect(width * 0.46, height * 0.08, width * 0.5, height * 0.8)
  readonly property point centre: Qt.point(area.x + area.width / 2, area.y + area.height / 2)
  readonly property real step: Math.min(area.width, area.height) / 11

  // A fixed pool of shape slots that stay alive: each keeps its result while
  // that result is listed, so shapes glide to new places, grow in when a
  // result appears and shrink away where it was when it goes. (A Repeater
  // over a fresh array rebuilt every shape on every keystroke: slow, and
  // nothing to animate from.) slots[i]: { id, index, kind, x, y, size, tilt,
  // strength, rank, alive }.
  property var slots: []
  property var slotOf: ({})
  property int shownCount: 0
  property bool settled: false
  // System: the one place without chaos. Categories are crosses on a 3x3
  // grid, sized by how many entries they hold; the open category's entries sit
  // on a ring around it, and the list on the left shows them.
  readonly property bool sys: kon.menu.systemTwoPane
  readonly property bool leftPane: kon.sys && kon.menu.systemPane === "left"

  function rebuild() {
    var n = Math.min(kon.model.count, kon.maxShapes)
    var query = String(kon.menu.filterText || "").trim().toLowerCase()
    var sectionIndex = ({})
    var sections = 0
    var perSection = ({})
    var rows = []
    for (var i = 0; i < n; i++) {
      var r = kon.model.get(i)
      if (!r || r.kind === "example") continue
      var title = Tabs.headerTitle(r.section) || "·"
      if (sectionIndex[title] === undefined) sectionIndex[title] = sections++
      var within = perSection[title] || 0
      perSection[title] = within + 1
      var label = String(r.label || "").toLowerCase()
      var strength = query ? Math.min(1, query.length / Math.max(1, label.length)) : 0.4
      if (query && label.indexOf(query) < 0) strength *= 0.6
      rows.push({ id: String(r.itemId || r.label) + "#" + r.kind, index: i, kind: r.kind, trail: r.trailText || "",
                  order: within * 16 + sectionIndex[title], strength: strength })
    }
    // Rank interleaves the sections: first of each, then second of each...
    rows.sort(function(a, b) { return a.order - b.order })

    // Keep each result in the slot it had; new ones take free slots.
    var old = kon.slots
    var used = ({})
    var place = ({})
    for (var k = 0; k < rows.length; k++) {
      var had = kon.slotOf[rows[k].id]
      if (had !== undefined && !used[had]) { place[rows[k].id] = had; used[had] = true }
    }
    var free = 0
    var now = Date.now()
    var next = []
    for (var z = 0; z < kon.maxShapes; z++) next.push(null)
    var slotOf = ({})
    for (var m = 0; m < rows.length; m++) {
      var row = rows[m]
      var slot = place[row.id]
      if (slot === undefined) { while (used[free]) free++; slot = free; used[slot] = true }
      var p = Konstrukt.spiral(m, kon.step)
      var days = row.kind === "file" || row.kind === "folder" ? Konstrukt.ageDays(row.trail, now) : 0
      next[slot] = { id: row.id, index: row.index, kind: row.kind, x: kon.centre.x + p.x, y: kon.centre.y + p.y,
                     size: kon.step * (0.45 + 1.1 * row.strength), tilt: Konstrukt.tiltFor(days),
                     strength: row.strength, rank: m, alive: true }
      slotOf[row.id] = slot
    }
    // Slots whose result went keep their last look and fade out in place.
    for (var d = 0; d < kon.maxShapes; d++) {
      if (next[d] === null) {
        var prev = old[d]
        next[d] = prev ? Object.assign({}, prev, { alive: false, index: -1 }) : null
      }
    }
    kon.slotOf = slotOf
    kon.slots = next
    kon.shownCount = rows.length
    for (var u = 0; u < kon.maxShapes; u++) {
      var item = pool.itemAt(u)
      if (item) item.show(next[u])
    }
  }

  // Row middles in view coordinates, by model index, for the connectors.
  // Refreshed when the list scrolls or changes, not per frame.
  property var rowY: ({})
  function measureRows() {
    var out = ({})
    for (var i = 0; i < kon.slots.length; i++) {
      var s = kon.slots[i]
      if (!s || !s.alive) continue
      var row = list.itemAtIndex(s.index)
      if (!row) continue
      var y = list.y + row.y - list.contentY + (row.labelCenterY !== undefined ? row.labelCenterY : row.height / 2)
      if (y >= list.y && y <= list.y + list.height) out[s.index] = y
    }
    // Scrolling and each row the list lays out call this: when no row moved,
    // leave the connectors alone.
    if (Konstrukt.sameMap(out, kon.rowY)) return
    kon.rowY = out
    for (var k = 0; k < kon.maxShapes; k++) {
      var item = pool.itemAt(k)
      if (item) item.place()
    }
  }
  // The list lays out its new rows after the model changes: measure now and
  // once more when it has settled.
  onSlotsChanged: { Qt.callLater(kon.measureRows); remeasure.restart() }
  Timer { id: remeasure; interval: 90; onTriggered: kon.measureRows() }

  function selectedSlot() {
    for (var i = 0; i < kon.slots.length; i++) {
      var s = kon.slots[i]
      if (s && s.alive && s.index === kon.menu.selectedIndex) return s
    }
    return null
  }

  Connections {
    target: kon.model
    function onCountChanged() { Qt.callLater(kon.rebuild) }
    function onDataChanged() { Qt.callLater(kon.rebuild) }
  }
  Connections {
    target: kon.menu
    function onFilterTextChanged() { Qt.callLater(kon.rebuild) }
    function onSelectedIndexChanged() {
      list.positionViewAtIndex(kon.menu.selectedIndex, ListView.Contain)
    }
  }
  // Also when the view is made already visible (Alt+L to Konstrukt with the
  // menu open): no visibleChanged comes then.
  function appear() { kon.settled = false; Qt.callLater(kon.rebuild); settle.restart() }
  onVisibleChanged: if (visible) kon.appear()
  Component.onCompleted: if (visible) kon.appear()
  onWidthChanged: Qt.callLater(kon.rebuild)
  onHeightChanged: Qt.callLater(kon.rebuild)
  // Shapes spring to new places as you type, but appear in place on open.
  Timer { id: settle; interval: 250; onTriggered: kon.settled = true }

  // The ground: 12 x 12 Truchet tiles, one bit of the seed each, faint and still.
  Canvas {
    id: ground
    visible: !kon.hasBackdrop
    x: kon.area.x
    y: kon.area.y
    width: kon.area.width
    height: kon.area.height
    opacity: 0.07
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var seed = "lfnfRdjd0w39r0jla0jXBzZb"
      var alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
      var bits = []
      for (var i = 0; i < seed.length; i++) {
        var v = alphabet.indexOf(seed.charAt(i))
        for (var b = 0; b < 6; b++) bits.push((v >> b) & 1)
      }
      var tile = Math.min(width, height) / 12
      ctx.strokeStyle = kon.ink
      ctx.lineWidth = 1
      for (var ty = 0; ty * tile < height; ty++) {
        for (var tx = 0; tx * tile < width; tx++) {
          var bit = bits[(ty * 12 + tx) % bits.length]
          var x0 = tx * tile, y0 = ty * tile, h = tile / 2
          ctx.beginPath()
          if (bit) {
            ctx.arc(x0, y0, h, 0, Math.PI / 2)
            ctx.moveTo(x0 + tile, y0 + tile - h)
            ctx.arc(x0 + tile, y0 + tile, h, Math.PI * 1.5, Math.PI, true)
          } else {
            ctx.arc(x0 + tile, y0, h, Math.PI / 2, Math.PI)
            ctx.moveTo(x0 + h, y0 + tile)
            ctx.arc(x0, y0 + tile, h, 0, Math.PI * 1.5, true)
          }
          ctx.stroke()
        }
      }
    }
  }

  // The query, standing large above the list.
  Text {
    id: query
    x: kon.listX
    y: Math.round(kon.height * 0.08)
    width: kon.listW
    textFormat: Text.PlainText
    readonly property bool empty: !kon.menu.filterText && !kon.sys
    readonly property string crumb: kon.menu.activeMenu === "root" ? "System" : "System › " + kon.menu.pathFor(kon.menu.activeMenu)
    text: kon.sys ? crumb + (kon.menu.filterText ? " · " + kon.menu.filterText : "")
      : (empty ? kon.menu.promptText() : kon.menu.filterText)
    color: kon.ink
    opacity: empty ? 0.4 : 1
    elide: Text.ElideLeft
    font.family: kon.menu.fontFamily
    font.pixelSize: Math.round(kon.menu.scaledFont(Style.font.heading) * (empty ? 1.3 : 2))
  }

  Rectangle {
    visible: !query.empty && kon.menu.opened
    x: query.x + Math.min(query.contentWidth, query.width) + Style.space(4)
    y: query.y + Style.space(4)
    width: Math.max(2, Style.space(3))
    height: query.height - Style.space(8)
    color: Color.accent
  }

  Text {
    x: kon.area.x
    y: query.y + Style.space(8)
    textFormat: Text.PlainText
    text: kon.menu.positionHint || (kon.sys ? kon.menu.systemCategories.length + " categories" : kon.shownCount + " shapes")
    color: Color.accent
    opacity: 0.8
    font.family: kon.menu.fontFamily
    font.pixelSize: kon.menu.scaledFont(Style.font.caption)
    font.letterSpacing: 2
  }

  TabBar {
    id: tabs
    x: kon.listX
    width: kon.listW
    y: query.y + query.height + Style.space(14)
    tabs: kon.menu.orderedTabs
    activeTab: kon.menu.activeTab
    fontFamily: kon.menu.fontFamily
    foreground: kon.ink
    accent: Color.accent
    fontSize: kon.menu.scaledFont(Style.font.body)
    anim: kon.menu.tabAnim
    tabStyle: "word"
    tabCase: "title"
    background: kon.menu.background
    onTabClicked: function(id) { kon.menu.setTab(id) }
  }

  ListView {
    id: list
    x: kon.listX
    y: tabs.y + tabs.height + Style.space(16)
    width: kon.listW
    height: kon.height * 0.88 - y
    model: kon.model
    clip: true
    spacing: kon.menu.rowSpacing
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: Qt.callLater(kon.measureRows)
    onContentHeightChanged: Qt.callLater(kon.measureRows)

    section.property: "section"
    section.criteria: ViewSection.FullString
    section.delegate: Item {
      required property string section
      width: ListView.view.width
      height: String(section).indexOf("hdr:") === 0 ? kon.menu.sectionHeaderHeight : 0
      visible: height > 0
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        textFormat: Text.PlainText
        text: Tabs.headerTitle(parent.section).toLowerCase()
        color: kon.ink
        opacity: 0.45
        font.family: kon.menu.fontFamily
        font.pixelSize: kon.menu.scaledFont(Style.font.caption)
        font.letterSpacing: 2
      }
    }

    // The selection: a tint with an accent edge, gliding between rows.
    Rectangle {
      id: listMarker
      // Found explicitly, not by binding: itemAtIndex() is nothing a binding
      // can depend on, and the row may not exist yet when the selection moves.
      property Item stop: null
      function find() {
        listMarker.stop = kon.menu.cursorActive && list.count > 0 && !kon.leftPane ? list.itemAtIndex(kon.menu.selectedIndex) : null
      }
      Connections {
        target: kon.menu
        function onSelectedIndexChanged() { Qt.callLater(listMarker.find); markerLater.restart() }
        function onCursorActiveChanged() { Qt.callLater(listMarker.find) }
        function onSystemPaneChanged() { Qt.callLater(listMarker.find) }
      }
      Connections {
        target: list
        function onCountChanged() { Qt.callLater(listMarker.find); markerLater.restart() }
        function onContentHeightChanged() { Qt.callLater(listMarker.find) }
      }
      Timer { id: markerLater; interval: 90; onTriggered: listMarker.find() }
      visible: stop !== null
      z: -1
      width: list.width
      y: stop ? stop.y : 0
      height: stop ? stop.height : 0
      radius: kon.menu.rowRadius
      color: Util.alpha(Color.accent, 0.14)
      Behavior on y { enabled: kon.settled; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      Rectangle { width: Math.max(3, Style.space(3)); y: Style.space(9); height: Math.max(0, parent.height - Style.space(18)); radius: width / 2; color: Color.accent }
    }

    delegate: ResultRow { menu: kon.menu }
  }

  // The shape pool. Each slot draws its connector from the row to the shape,
  // bound to the shape's animated place, so lines follow smoothly; no Canvas.
  Repeater {
    id: pool
    model: kon.maxShapes
    Item {
      id: slot
      required property int index
      // What the slot shows (its entry in kon.slots), copied in field by
      // field by rebuild() through show(): a field that did not change
      // notifies nothing, so a keystroke re-runs only the bindings of what
      // moved. (Every slot bound to the one shared array re-ran all its
      // bindings, the long-faded ones too, on each keystroke.)
      property bool used: false
      property string ident: ""
      property int row: -1
      property string kind: ""
      property real cx: 0
      property real cy: 0
      property real size: 0
      property real tilt: 0
      property real strength: 0
      property int rank: 0
      property bool alive: false
      // The row's middle (kon.rowY), or -1 when the row is off the list.
      property real rowY: -1
      function show(s) {
        slot.used = s !== null
        if (!s) {
          slot.alive = false
          slot.row = -1
          slot.place()
          return
        }
        // The identity first: a new result jumps (below) rather than flies.
        slot.ident = s.id
        slot.kind = s.kind
        slot.row = s.index
        slot.cx = s.x
        slot.cy = s.y
        slot.size = s.size
        slot.tilt = s.tilt
        slot.strength = s.strength
        slot.rank = s.rank
        slot.alive = s.alive === true
        slot.place()
      }
      Component.onCompleted: slot.show(kon.slots[slot.index] || null)
      function place() {
        slot.rowY = slot.alive && kon.rowY[slot.row] !== undefined ? kon.rowY[slot.row] : -1
      }
      readonly property bool selected: slot.alive && slot.row === kon.menu.selectedIndex
      readonly property string form: slot.used ? Konstrukt.shapeFor(slot.kind) : "square"
      readonly property color fill: slot.selected ? kon.ink : kon.kindColor(slot.used ? slot.kind : "")
      // A slot that takes a new result jumps to its place instead of flying
      // across the field from the old one.
      property bool jump: true
      onIdentChanged: { slot.jump = true; unjump.restart() }
      Timer { id: unjump; interval: 30; onTriggered: slot.jump = false }
      readonly property bool glide: kon.settled && !slot.jump

      anchors.fill: parent
      visible: slot.used && !kon.sys

      // The connector.
      Rectangle {
        readonly property real x2: piece.x + piece.width / 2
        readonly property real y2: piece.y + piece.height / 2
        readonly property real x1: list.x + list.width + Style.space(6)
        visible: slot.rowY >= 0 && piece.scale > 0.05
        x: x1
        y: slot.rowY
        width: Math.hypot(x2 - x1, y2 - slot.rowY)
        height: slot.selected ? 2 : 1
        rotation: Math.atan2(y2 - slot.rowY, x2 - x1) * 180 / Math.PI
        transformOrigin: Item.Left
        antialiasing: true
        color: slot.selected ? Color.accent : Util.alpha(kon.ink, 0.16)
        opacity: piece.scale
      }

      Rectangle {
        visible: slot.rowY >= 0
        x: list.x + list.width + Style.space(4)
        y: slot.rowY - 2
        width: 4
        height: 4
        color: slot.selected ? Color.accent : Util.alpha(kon.ink, 0.3)
      }

      Item {
        id: piece
        width: slot.used ? slot.size : 0
        height: slot.form === "bar" ? width * 0.3 : width
        x: slot.used ? slot.cx - width / 2 : 0
        y: slot.used ? slot.cy - height / 2 : 0
        rotation: slot.used ? slot.tilt : 0
        // Grows in when its result appears, shrinks away where it was when
        // the result goes.
        scale: slot.alive ? 1 : 0
        opacity: slot.selected ? 1 : 0.88
        Behavior on x { enabled: slot.glide; NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on y { enabled: slot.glide; NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on width { enabled: slot.glide; NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on rotation { enabled: slot.glide; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: kon.settled; NumberAnimation { duration: slot.alive ? 200 : 140; easing.type: slot.alive ? Easing.OutBack : Easing.InCubic } }

        Rectangle {
          visible: slot.form === "circle" || slot.form === "square" || slot.form === "bar"
          anchors.fill: parent
          radius: slot.form === "circle" ? width / 2 : 0
          color: slot.fill
          antialiasing: true
        }

        Shape {
          visible: slot.form === "triangle"
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: slot.fill
            startX: piece.width / 2; startY: 0
            PathLine { x: piece.width; y: piece.height }
            PathLine { x: 0; y: piece.height }
            PathLine { x: piece.width / 2; y: 0 }
          }
        }

        Rectangle { visible: slot.form === "cross"; anchors.centerIn: parent; width: parent.width; height: parent.height * 0.3; color: slot.fill }
        Rectangle { visible: slot.form === "cross"; anchors.centerIn: parent; width: parent.width * 0.3; height: parent.height; color: slot.fill }

        Rectangle {
          visible: slot.selected
          anchors.centerIn: parent
          width: parent.width + Style.space(16)
          height: parent.height + Style.space(16)
          color: "transparent"
          border.width: Math.max(2, Style.space(2))
          border.color: Color.accent
        }
      }

      Text {
        visible: slot.selected
        x: piece.x + piece.width + Style.space(22)
        y: piece.y + piece.height / 2 - height / 2
        textFormat: Text.PlainText
        // Laid out only where it shows: on the selected shape.
        text: slot.selected ? "#" + String(slot.rank + 1).padStart(2, "0") + " · " + slot.kind + " · "
          + Math.round(slot.strength * 100) + "% · " + Math.round(slot.tilt) + "°" : ""
        color: kon.ink
        font.family: kon.menu.fontFamily
        font.pixelSize: kon.menu.scaledFont(Style.font.caption)
        font.letterSpacing: 1
      }
    }
  }

  // System's grid of categories.
  Repeater {
    model: kon.sys ? kon.menu.systemCategories : []
    Item {
      id: cat
      required property var modelData
      required property int index
      readonly property bool picked: cat.index === kon.menu.systemCategoryIndex
      readonly property real cell: Math.min(kon.area.width, kon.area.height) / 3.4
      readonly property real size: kon.step * (0.55 + 0.1 * Math.min(8, cat.modelData.childCount || 0))
      readonly property color fill: cat.picked && kon.leftPane ? kon.ink : kon.kindColor("menu")
      x: kon.centre.x + ((cat.index % 3) - 1) * cat.cell - width / 2
      y: kon.centre.y + (Math.floor(cat.index / 3) - 1) * cat.cell - height / 2
      width: cat.size
      height: cat.size
      opacity: cat.picked ? 1 : 0.55
      Behavior on opacity { NumberAnimation { duration: 140 } }

      Rectangle { anchors.centerIn: parent; width: parent.width; height: parent.height * 0.3; color: cat.fill }
      Rectangle { anchors.centerIn: parent; width: parent.width * 0.3; height: parent.height; color: cat.fill }
      Rectangle {
        visible: cat.picked
        anchors.centerIn: parent
        width: parent.width + Style.space(16)
        height: parent.height + Style.space(16)
        color: "transparent"
        border.width: Math.max(2, Style.space(2))
        border.color: kon.leftPane ? Color.accent : Util.alpha(Color.accent, 0.45)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + Style.space(14)
        textFormat: Text.PlainText
        text: cat.modelData.label
        color: kon.ink
        opacity: cat.picked ? 0.95 : 0.6
        font.family: kon.menu.fontFamily
        font.pixelSize: kon.menu.scaledFont(Style.font.caption)
        font.letterSpacing: 1
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(10)
        cursorShape: Qt.PointingHandCursor
        onClicked: cat.picked ? kon.menu.activateSystemCategory() : kon.menu.selectSystemCategory(cat.index)
      }
    }
  }

  // The open category's entries on a ring around its cross.
  Repeater {
    model: kon.sys ? Math.min(kon.model.count, 24) : 0
    Rectangle {
      id: entry
      required property int index
      readonly property int picked: kon.menu.systemCategoryIndex
      readonly property real cell: Math.min(kon.area.width, kon.area.height) / 3.4
      readonly property point hub: Qt.point(kon.centre.x + ((picked % 3) - 1) * cell, kon.centre.y + (Math.floor(picked / 3) - 1) * cell)
      readonly property real angle: -Math.PI / 2 + entry.index * 2 * Math.PI / Math.max(1, Math.min(kon.model.count, 24))
      readonly property real ringR: kon.step * 1.9
      readonly property bool current: !kon.leftPane && entry.index === kon.menu.selectedIndex
      width: entry.current ? Style.space(14) : Style.space(8)
      height: width
      radius: width / 2
      x: hub.x + ringR * Math.cos(angle) - width / 2
      y: hub.y + ringR * Math.sin(angle) - height / 2
      color: entry.current ? kon.ink : Util.alpha(kon.ink, 0.5)
      border.width: entry.current ? 2 : 0
      border.color: Color.accent
      Behavior on x { enabled: kon.settled; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: kon.settled; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
  }

  // The rules, in the corner, for whoever looks.
  Text {
    x: kon.area.x
    y: kon.height - Style.space(48)
    textFormat: Text.PlainText
    text: kon.sys ? "System has no chaos: categories on a grid, sized by their entries; the open one's entries on a ring"
      : "● app   ■ file   ▲ folder   ✚ system   ▬ window     size = match · tilt = age · spiral = rank"
    color: kon.ink
    opacity: 0.45
    font.family: kon.menu.fontFamily
    font.pixelSize: kon.menu.scaledFont(Style.font.caption)
  }

  Text {
    x: kon.listX
    y: kon.height - Style.space(48)
    textFormat: Text.PlainText
    text: "↑↓ move   ↵ open   ⇥ tab   ai ask   esc close"
    color: kon.ink
    opacity: 0.45
    font.family: kon.menu.fontFamily
    font.pixelSize: kon.menu.scaledFont(Style.font.caption)
  }
}
