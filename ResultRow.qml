import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Windows.js" as Windows

// One row of the result list: icon or app icon, label, detail line,
// right-hand text (a file's mtime) and a chevron for submenus. Roles come
// from the menu's row model; pointer handling goes back to the menu.
BorderSurface {
  id: row
  required property var menu

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

  // The row's place among those on screen, 1-9: holding Alt shows it, and
  // Alt+n opens the row.
  readonly property int ordinal: row.index - row.menu.firstVisibleRow + 1
  readonly property bool numbered: row.menu.altHeld && row.kind !== "example"
    && row.ordinal >= 1 && row.ordinal <= 9
  // Where the label's middle sits, for the number and the actions.
  readonly property real labelCenterY: contentColumn.y + labelText.y + labelText.height / 2
  // The selected row's actions and their keys, where the date was.
  readonly property var actions: !row.hasCursor ? []
    : (row.kind === "file" || row.kind === "folder" ? [["↵", "open"], ["alt ↵", "folder"], ["^C", "path"]]
    : row.kind === "app" ? [["↵", "open"], ["shift ↵", "new window"]]
    : row.kind === "window" ? [["↵", "go to"]] : [])
  // The label with the query's match in the accent colour, or "" to keep
  // plain text (Menu.qml, markRow).
  required property string marked

  // The selection marker follows the row with the cursor (Menu.qml).
  onHasCursorChanged: if (row.hasCursor) row.menu.cursorRow = row
  Component.onCompleted: if (row.hasCursor) row.menu.cursorRow = row

  // Command examples are a read-only hint.
  opacity: row.kind === "example" ? 0.7 : 1
  width: ListView.view.width
  height: row.menu.rowHeightForDetail(row.detail, row.kind)
  radius: row.menu.rowRadius
  // The selection is drawn by the list (Menu.qml, selMarker), gliding
  // between rows; the rows themselves stay unfilled.
  color: "transparent"
  borderSpec: Border.none()

  Rectangle {
    visible: false
    width: Style.space(4)
    height: parent.height - Style.space(18)
    radius: Math.min(row.menu.cornerRadius, Style.space(4))
    color: row.menu.selectedBackground
    anchors.left: parent.left
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
  }

  // With Alt held: the row's number, as a keycap, over its icon. Loaded
  // only then: every row is rebuilt on each keystroke, so what a row does
  // not show should cost it nothing.
  Loader {
    active: row.numbered
    z: 2
    x: row.menu.rowReservedBorderLeft + Style.space(8) + (row.menu.iconSlotWidth - width) / 2
    y: Math.round(row.labelCenterY - height / 2)
    sourceComponent: Rectangle {
      width: Math.round(row.menu.scaledFont(Style.font.iconLarge) * 0.95)
      height: width
      radius: Style.space(4)
      color: row.menu.foreground

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(row.ordinal)
        color: row.menu.background
        font.family: row.menu.fontFamily
        font.pixelSize: row.menu.scaledFont(Style.font.body)
        font.weight: Font.Bold
      }
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
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8)
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
    anchors.leftMargin: row.menu.rowReservedBorderLeft + Style.space(8) + (row.menu.iconSlotWidth - width) / 2
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
    anchors.leftMargin: row.hasIcon ? Style.space(6) : row.menu.rowReservedBorderLeft + Style.space(18)
    anchors.right: actionRow.visible ? actionRow.left : (trailLabel.visible ? trailLabel.left : trail.left)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      id: labelText
      textFormat: row.marked ? Text.StyledText : Text.PlainText
      width: parent.width
      text: row.marked || row.label
      color: row.hasCursor ? row.menu.selectionText : row.menu.foreground
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

  // The selected row's actions, as keycaps; they take the date's place.
  // Loaded on the selected row only.
  Loader {
    id: actionRow
    active: row.actions.length > 0
    visible: active
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    y: Math.round(row.labelCenterY - height / 2)
    sourceComponent: Row {
      spacing: Style.space(10)

      Repeater {
        model: row.actions
        Row {
          required property var modelData
          spacing: Style.space(4)
          Rectangle {
            width: capText.implicitWidth + Style.space(8)
            height: capText.implicitHeight + Style.space(2)
            radius: Style.space(3)
            color: "transparent"
            border.width: 1
            border.color: Util.alpha(row.menu.foreground, 0.32)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              id: capText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData[0]
              color: row.menu.foreground
              opacity: 0.85
              font.family: row.menu.fontFamily
              font.pixelSize: row.menu.scaledFont(Style.font.caption)
            }
          }
          Text {
            textFormat: Text.PlainText
            text: modelData[1]
            color: row.menu.foreground
            opacity: 0.7
            font.family: row.menu.fontFamily
            font.pixelSize: row.menu.scaledFont(Style.font.caption)
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  Text {
    id: trailLabel
    textFormat: Text.PlainText
    visible: row.trailShown.length > 0 && !actionRow.visible
    text: row.trailShown
    color: row.menu.foreground
    opacity: 0.45
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
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
