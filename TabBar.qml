import QtQuick
import qs.Commons

// The row of tab chips under the search field. Purely presentational: the
// menu owns which tab is active and what switching means; this only draws
// the chips and reports clicks. A Flow, so a narrow card (style.json
// "cardWidth") wraps the chips onto a second line instead of spilling out.
//
// The active highlight is one pill drawn under the Flow rather than a fill
// on each chip, so a tab switch slides it from the old chip to the new one.
Item {
  id: bar

  required property var tabs
  required property string activeTab
  required property string fontFamily
  required property color foreground
  required property color accent
  required property int fontSize

  // The look's tab treatment (Menu.qml tabStyle, tabCase): "chip" pills
  // with a sliding highlight, in title case, unless a style's State in
  // styleStates below sets the properties that follow.
  property string tabStyle: "chip"
  property string tabCase: "title"
  // The card colour, for a look whose active tab is filled solid.
  property color background: "black"
  property color litColor: bar.accent        // the active tab's label
  property bool dot: false                   // a dot under the active tab instead of a pill
  property color highlightColor: Util.alpha(bar.accent, 0.22 + 0.24 * bar.popStrength * bar.glow)
  property bool icons: true                  // the tab icons
  property real labelDim: 0.8                // inactive labels
  property real pad: Style.space(bar.hasCounts ? 13 : 20)
  property color chipIdle: Util.alpha(bar.foreground, 0.07)
  property color chipHover: Util.alpha(bar.accent, 0.10)
  // The accent colour travels with the highlight (the lit copy of a label,
  // clipped to it) rather than switching tab by tab.
  property bool sweepLabels: true

  // One State per tab style, in one group (see Menu.qml lookStates).
  StateGroup {
    id: styleStates
    states: [
      // Mala: bare words with a sliding dot.
      State {
        when: bar.tabStyle === "word"
        PropertyChanges {
          bar.litColor: bar.foreground
          bar.dot: true
          bar.highlightColor: Util.alpha(bar.foreground, 0.85)
          bar.icons: false
          bar.labelDim: 0.5
          bar.pad: Style.space(12)
          bar.chipIdle: "transparent"
          bar.chipHover: "transparent"
          bar.sweepLabels: false
        }
      },
    ]
  }


  function caseLabel(text) {
    return bar.tabCase === "lower" ? String(text).toLowerCase()
      : (bar.tabCase === "upper" ? String(text).toUpperCase() : String(text))
  }
  // Match counts per tab id, shown small after the label when present.
  property var counts: ({})
  readonly property bool hasCounts: Object.keys(bar.counts).length > 0
  // The count slot: room for as many digits as the widest count on show
  // ("99+" above 99), tabular, so chips keep their size while typing.
  readonly property string countPattern: {
    var digits = 1
    for (var id in bar.counts) {
      var n = Number(bar.counts[id])
      digits = Math.max(digits, n > 99 ? 3 : String(n).length)
    }
    return digits >= 3 ? "99+" : (digits === 2 ? "00" : "0")
  }
  TextMetrics { id: countSlot; font.family: bar.fontFamily; font.pixelSize: Math.round(bar.fontSize * 0.85); text: bar.countPattern }
  readonly property real countSlotWidth: countSlot.advanceWidth
  // Whether every tab's count fits on one line. Measured from the labels
  // alone (chip.fullWidth does not depend on which counts show), so hiding
  // counts can never feed back into this. When they do not fit, only the
  // active tab keeps its count.
  readonly property real naturalWidth: {
    var w = 0
    var n = bar.chipsVersion >= 0 ? repeater.count : 0
    for (var i = 0; i < n; i++) {
      var c = repeater.itemAt(i)
      if (c) w += c.fullWidth
    }
    return w + Math.max(0, n - 1) * Style.space(6)
  }
  readonly property bool showAllCounts: bar.naturalWidth <= bar.width

  signal tabClicked(string id)

  // The menu passes style.json's tab animation keys (Settings.tabAnim).
  // The defaults are short enough not to hold up the switch but long enough
  // to read as motion; the landing pulse is there to try, off by default.
  property var anim: ({ tabSlideMs: 120, tabEasing: "OutCubic", tabOvershoot: 1.70158, tabPop: 0, tabBezier: null, tabSweep: true })
  readonly property int slideDuration: bar.anim.tabSlideMs
  // A tabBezier curve wins over the named one. Qt wants the end point
  // spelled out after CSS's two control points.
  readonly property var slideBezier: bar.anim.tabBezier ? bar.anim.tabBezier.concat([1, 1]) : []
  readonly property int slideEasing: bar.anim.tabBezier ? Easing.BezierSpline : ({
    Linear: Easing.Linear, OutQuad: Easing.OutQuad, OutCubic: Easing.OutCubic,
    OutQuart: Easing.OutQuart, OutQuint: Easing.OutQuint, OutExpo: Easing.OutExpo,
    OutCirc: Easing.OutCirc, OutSine: Easing.OutSine, InOutQuad: Easing.InOutQuad,
    InOutCubic: Easing.InOutCubic, InOutQuart: Easing.InOutQuart, InOutExpo: Easing.InOutExpo,
    InOutSine: Easing.InOutSine, OutBack: Easing.OutBack, InOutBack: Easing.InOutBack,
    OutElastic: Easing.OutElastic, OutBounce: Easing.OutBounce
  })[bar.anim.tabEasing] ?? Easing.OutCubic
  readonly property real popStrength: bar.anim.tabPop
  // true: the accent text is painted wherever the pill is, so it sweeps
  // across the labels; false: each label fades between its two colours.
  readonly property bool sweep: bar.anim.tabSweep !== false

  // 0..1 while the pop runs: brightens the pill and swells it a little.
  property real glow: 0

  // Animate only for a tab switch. Everything else that moves the chips
  // (the tab list swapping for AI agents, the card resizing, the Flow
  // re-wrapping) snaps, so the pill never drifts in from a stale spot.
  property bool sliding: false

  readonly property int activeIndex: {
    const list = bar.tabs || []
    for (let i = 0; i < list.length; i++)
      if (list[i].id === bar.activeTab) return i
    return -1
  }
  // Repeater.itemAt() is not something a binding can depend on, and
  // repeater.count alone misses chips being replaced at the same count (a
  // new tab list of the same length). chipsVersion changes with every chip
  // created or destroyed, so the pill always finds the live chip; without
  // it, the highlight went missing on 7 of 8 first opens after a restart.
  property int chipsVersion: 0
  readonly property Item activeChip: bar.chipsVersion >= 0 && repeater.count > 0 && bar.activeIndex >= 0
    ? repeater.itemAt(bar.activeIndex) : null

  onActiveTabChanged: {
    bar.sliding = bar.visible
    slideEnd.restart()
    if (bar.sliding && bar.popStrength > 0) pop.restart()
  }

  // Waits until the slide is mostly done, so the pulse marks the arrival.
  SequentialAnimation {
    id: pop
    PauseAnimation { duration: Math.round(bar.slideDuration * 0.6) }
    NumberAnimation { target: bar; property: "glow"; to: 1; duration: 70; easing.type: Easing.OutQuad }
    NumberAnimation { target: bar; property: "glow"; to: 0; duration: 220; easing.type: Easing.InOutQuad }
  }

  Timer {
    id: slideEnd
    interval: bar.slideDuration + 40
    onTriggered: bar.sliding = false
  }

  width: parent ? parent.width : implicitWidth
  implicitWidth: flow.implicitWidth
  implicitHeight: flow.implicitHeight

  // A dot (dot: true) sits under the active tab; a pill covers it.
  readonly property int dotSize: Math.max(3, Math.round(bar.fontSize / 4))

  Rectangle {
    id: highlight
    visible: bar.activeChip !== null
    x: bar.activeChip ? (bar.dot ? bar.activeChip.x + (bar.activeChip.width - bar.dotSize) / 2 : bar.activeChip.x) : 0
    y: bar.activeChip ? (bar.dot ? bar.activeChip.y + bar.activeChip.height - bar.dotSize : bar.activeChip.y) : 0
    width: bar.activeChip ? (bar.dot ? bar.dotSize : bar.activeChip.width) : 0
    height: bar.activeChip ? (bar.dot ? bar.dotSize : bar.activeChip.height) : 0
    radius: height / 2
    color: bar.highlightColor
    scale: 1 + 0.10 * bar.popStrength * bar.glow

    Behavior on x { enabled: bar.sliding; NumberAnimation { duration: bar.slideDuration; easing.type: bar.slideEasing; easing.overshoot: bar.anim.tabOvershoot; easing.bezierCurve: bar.slideBezier } }
    Behavior on y { enabled: bar.sliding; NumberAnimation { duration: bar.slideDuration; easing.type: bar.slideEasing; easing.overshoot: bar.anim.tabOvershoot; easing.bezierCurve: bar.slideBezier } }
    Behavior on width { enabled: bar.sliding; NumberAnimation { duration: bar.slideDuration; easing.type: bar.slideEasing; easing.overshoot: bar.anim.tabOvershoot; easing.bezierCurve: bar.slideBezier } }
  }

  // A chip's icon and label, dimmed or lit in the accent colour.
  component ChipLabel: Row {
    id: label
    // Inline components do not see this file's ids, so the bar is passed in.
    required property Item owner
    required property var chipData
    required property bool bold
    required property bool lit
    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      visible: label.owner.icons
      text: label.chipData.icon
      color: label.lit ? label.owner.litColor : label.owner.foreground
      opacity: label.lit ? 1 : 0.7
      font.family: label.owner.fontFamily
      font.pixelSize: label.owner.fontSize
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { enabled: label.owner.sliding; ColorAnimation { duration: label.owner.slideDuration } }
    }

    Text {
      textFormat: Text.PlainText
      text: label.owner.caseLabel(label.chipData.label)
      color: label.lit ? label.owner.litColor : label.owner.foreground
      opacity: label.lit ? 1 : label.owner.labelDim
      font.family: label.owner.fontFamily
      font.pixelSize: label.owner.fontSize
      font.weight: label.bold ? Font.DemiBold : Font.Normal
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { enabled: label.owner.sliding; ColorAnimation { duration: label.owner.slideDuration } }
    }

    // The count: the bar's slot width, tabular digits.
    Text {
      readonly property var count: label.owner.counts[label.chipData.id]
      visible: count !== undefined && (label.owner.showAllCounts || label.bold)
      width: label.owner.countSlotWidth
      horizontalAlignment: Text.AlignLeft
      font.features: ({ "tnum": 1 })
      textFormat: Text.PlainText
      text: count !== undefined ? (count > 99 ? "99+" : String(count)) : ""
      color: label.lit ? label.owner.litColor : label.owner.foreground
      opacity: label.lit ? 0.8 : 0.5
      font.family: label.owner.fontFamily
      font.pixelSize: Math.round(label.owner.fontSize * 0.85)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Flow {
    id: flow
    width: bar.width
    spacing: Style.space(6)

    Repeater {
      id: repeater
      model: bar.tabs
      onItemAdded: bar.chipsVersion++
      onItemRemoved: bar.chipsVersion++

      Rectangle {
        id: chip

        required property var modelData
        readonly property bool active: chip.modelData.id === bar.activeTab

        // Counts widen the chips; tighter padding keeps six on one line.
        readonly property real pad: bar.pad
        width: chipRow.implicitWidth + chip.pad
        // The chip's width with its count showing, measured from the label
        // (bold, the widest it gets), for the bar's fit check.
        TextMetrics { id: labelSize; font.family: bar.fontFamily; font.pixelSize: bar.fontSize; font.weight: Font.DemiBold; text: bar.caseLabel(chip.modelData.label) }
        TextMetrics { id: iconSize; font.family: bar.fontFamily; font.pixelSize: bar.fontSize; text: bar.icons ? (chip.modelData.icon || "") : "" }
        readonly property real fullWidth: labelSize.advanceWidth + chip.pad
          + (iconSize.text ? iconSize.advanceWidth + Style.space(6) : 0)
          + (bar.counts[chip.modelData.id] !== undefined ? bar.countSlotWidth + Style.space(6) : 0)
        height: chipRow.implicitHeight + Style.space(10)
        radius: height / 2
        // The active fill is the sliding highlight underneath.
        color: chip.active ? "transparent" : (chipMouse.containsMouse ? bar.chipHover : bar.chipIdle)

        ChipLabel {
          id: chipRow
          anchors.centerIn: parent
          owner: bar
          chipData: chip.modelData
          bold: chip.active
          // Sweeping, the lit copy below does the colouring; this stays the
          // plain label underneath it.
          lit: chip.active && (!bar.sweep || !bar.sweepLabels)
        }

        // The label again in the accent colour, clipped to the part of the
        // chip the highlight covers, so the colour travels with the pill
        // instead of switching chip by chip.
        Item {
          id: litClip
          visible: bar.sweep && bar.sweepLabels && width > 0 && height > 0
          clip: true
          readonly property real fromX: Math.max(0, highlight.x - chip.x)
          readonly property real fromY: Math.max(0, highlight.y - chip.y)
          x: litClip.fromX
          y: litClip.fromY
          width: Math.max(0, Math.min(chip.width, highlight.x + highlight.width - chip.x) - litClip.fromX)
          height: Math.max(0, Math.min(chip.height, highlight.y + highlight.height - chip.y) - litClip.fromY)

          ChipLabel {
            x: chipRow.x - litClip.x
            y: chipRow.y - litClip.y
            owner: bar
          chipData: chip.modelData
            bold: chip.active
            lit: true
          }
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: bar.tabClicked(chip.modelData.id)
        }
      }
    }
  }
}
