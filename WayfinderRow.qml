import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Windows.js" as Windows

// One row in the Wayfinder look: a stop on the trunk line, the icon, label
// and detail, and a map reference (A1, F5…) as a keycap for Alt+n. The
// selected row is filled and its stop is an interchange ring. Same roles
// and pointer handling as ResultRow; a row of its own so that classic rows
// carry none of this.
BorderSurface {
  id: row
  // Made by the list from Menu.lookRows, so the menu comes through it.
  readonly property var menu: ListView.view.lookMenu

  required property int index
  required property string itemId
  required property string kind
  required property string icon
  required property string iconFont
  required property string appIcon
  required property string appId
  required property string label
  required property string target
  required property string detail
  required property string path
  required property string action
  required property int childCount
  required property string trailText

  readonly property bool hasCursor: row.menu.cursorActive && row.index === row.menu.selectedIndex && row.kind !== "example"
    && (!row.menu.systemTwoPane || row.menu.systemPane === "right")
  // Window rows borrow their application's icon when a desktop entry
  // matches the window class, and fall back to a glyph when none does.
  readonly property bool isApp: row.kind === "app" || (row.kind === "window" && row.appIcon.length > 0)
  readonly property bool hasIcon: row.icon.length > 0 || row.isApp
  // Open windows of an application row, for the running marker.
  readonly property int windowCount: row.kind === "app" ? row.menu.appWindowCount(row.appId) : 0
  readonly property string trailShown: row.trailText.length > 0 ? row.trailText : Windows.runningLabel(row.windowCount)

  // The row's place among those on screen, 1-9, shown in its map
  // reference; Alt+n opens the row.
  readonly property int ordinal: row.index - row.menu.firstVisibleRow + 1
  readonly property bool numbered: row.kind !== "example" && row.ordinal >= 1 && row.ordinal <= 9
  // A letter for the row's kind and its number on screen ("file", 5 ->
  // "F5"): A apps, W windows, F files, D folders (apart from files), S
  // everything from the System menu.
  readonly property string mapRef: (({ app: "A", window: "W", file: "F", folder: "D" })[row.kind] || "S") + row.ordinal
  // The trunk line's gutter, left of the icons.
  readonly property int gutter: Style.space(26)
  // Where the label's middle sits, for the number and the actions.
  readonly property real labelCenterY: contentColumn.y + labelText.y + labelText.height / 2
  // The label with the query's match underlined, or "" to keep plain text
  // (Menu.qml, markRow).
  required property string marked

  // The route follows the row with the cursor (Menu.qml).
  onHasCursorChanged: if (row.hasCursor) row.menu.cursorRow = row
  Component.onCompleted: if (row.hasCursor) row.menu.cursorRow = row

  // Command examples are a read-only hint.
  opacity: row.kind === "example" ? 0.7 : 1
  width: ListView.view.width
  height: row.menu.rowHeightForDetail(row.detail, row.kind)
  radius: row.menu.rowRadius
  // The selected row is filled with the theme's selection colours.
  color: row.hasCursor ? row.menu.selectedBackground : "transparent"
  borderSpec: row.hasCursor ? row.menu.selectedBorderSpec : Border.none()

  // This row's stop on the trunk line (the line itself and the route are in
  // Menu.qml). Stops above the selection are lit, as the route has passed
  // them; the selected stop is an interchange ring that opens with a small
  // overshoot as the route pulls in.
  Rectangle {
    id: stopRing
    readonly property int size: row.hasCursor ? Style.space(14) : Style.space(8)
    width: size
    height: size
    radius: size / 2
    x: Math.round((row.gutter - size) / 2)
    y: Math.round(row.labelCenterY - size / 2)
    color: row.menu.background
    border.width: row.hasCursor ? Style.space(3) : Math.max(1, Style.space(2))
    border.color: row.hasCursor || (row.menu.cursorActive && row.index < row.menu.selectedIndex)
      ? Color.accent : Util.alpha(row.menu.foreground, 0.45)

    // A little under the ring's size, up past it and settling. Never below
    // a plain stop or the train's width (from 0.45 the new ring was a dot
    // inside the train's end for frames). Leaving is instant.
    NumberAnimation {
      id: ringPop
      target: stopRing
      property: "scale"
      from: 0.8
      to: 1
      duration: 260
      easing.type: Easing.OutBack
      easing.overshoot: 3
    }
    readonly property bool selected: row.hasCursor
    onSelectedChanged: {
      ringPop.stop()
      stopRing.scale = 1
      if (stopRing.selected) ringPop.start()
    }

    Rectangle {
      visible: row.hasCursor
      anchors.centerIn: parent
      width: Style.space(4)
      height: width
      radius: width / 2
      color: Color.accent
    }
  }

  Text {
    id: iconText
    textFormat: Text.PlainText
    visible: row.hasIcon && !row.isApp
    text: row.icon
    color: row.menu.foreground
    font.family: row.iconFont.length > 0 ? row.iconFont : row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(row.kind === "example" ? Style.font.icon : Style.font.iconLarge)
    width: row.menu.iconSlotWidth
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    anchors.left: parent.left
    anchors.leftMargin: row.gutter + Style.space(4)
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
  }

  Image {
    id: appIconImage
    visible: row.isApp
    width: row.menu.scaledFont(Style.font.iconLarge)
    height: row.menu.scaledFont(Style.font.iconLarge)
    fillMode: Image.PreserveAspectFit
    // Decode at physical pixels — a logical-size decode leaves
    // PNG icons upscaled and blurry on HiDPI displays.
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: row.isApp ? row.menu.appIconSource(row.appIcon) : ""
    asynchronous: true
    anchors.left: parent.left
    anchors.leftMargin: row.gutter + Style.space(4) + (row.menu.iconSlotWidth - width) / 2
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
  }

  RunningBadge {
    count: row.windowCount
    sizeScale: row.menu.menuFontScale
    ring: row.hasCursor ? row.menu.selectedBackground : row.menu.background
    x: appIconImage.x + appIconImage.width - width * 0.6
    y: appIconImage.y + appIconImage.height - height * 0.6
  }

  Column {
    id: contentColumn
    anchors.left: row.hasIcon ? iconText.right : parent.left
    anchors.leftMargin: row.hasIcon ? Style.space(6) : row.gutter + Style.space(8)
    anchors.right: trailLabel.visible ? trailLabel.left : refCap.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      id: labelText
      textFormat: row.marked ? Text.StyledText : Text.PlainText
      width: parent.width
      text: row.marked || row.label
      color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(row.kind === "example" ? Style.font.body : Style.font.heading)
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: row.detail
      visible: row.menu.showsDetail(row.kind, row.detail)
      color: row.menu.foreground
      opacity: 0.52
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(row.kind === "example" ? Style.font.caption : Style.font.bodySmall)
      elide: Text.ElideRight
    }
  }

  Text {
    id: trailLabel
    textFormat: Text.PlainText
    visible: row.trailShown.length > 0
    text: row.trailShown
    color: row.menu.foreground
    opacity: 0.45
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
    anchors.right: refCap.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
  }

  // The map reference, a keycap for Alt+n; filled on the selection.
  Rectangle {
    id: refCap
    visible: row.numbered
    width: visible ? refText.implicitWidth + Style.space(10) : 0
    height: refText.implicitHeight + Style.space(4)
    radius: Style.space(3)
    color: row.hasCursor ? Color.accent : "transparent"
    border.width: row.hasCursor ? 0 : 1
    border.color: Util.alpha(row.menu.foreground, 0.35)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    y: Math.round(row.labelCenterY - height / 2)

    Text {
      id: refText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: row.mapRef
      color: row.hasCursor ? row.menu.background : row.menu.foreground
      opacity: row.hasCursor ? 1 : 0.7
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.caption)
      font.weight: Font.DemiBold
    }
  }

  Row {
    id: trail
    width: Style.space(14)
    anchors.right: parent.right
    anchors.rightMargin: row.menu.rowReservedBorderRight + Style.space(8)
    y: contentColumn.y + labelText.y + (labelText.height - height) / 2
    spacing: 0

    Text {
      textFormat: Text.PlainText
      visible: false
      text: row.childCount
      color: row.menu.foreground
      opacity: 0.45
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.body)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: row.kind === "menu" || row.kind === "link" ? "›" : ""
      color: row.menu.foreground
      opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.heading)
      font.weight: Font.Normal
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.menu.selectFromPointer(row.index, row, {
      x: mouseArea.mouseX,
      y: mouseArea.mouseY
    })
    onPositionChanged: function(mouse) {
      row.menu.selectFromPointer(row.index, row, mouse)
    }
    onClicked: {
      row.menu.cursorActive = true
      row.menu.selectedIndex = row.index
      row.menu.activateIndex(row.index, true)
    }
  }
}
