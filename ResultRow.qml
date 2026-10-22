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

  // An app of All's Apps section shown as a tile (AllTiles.js): the strip's
  // first row draws the whole strip, the rest take no room. The row's own
  // content and highlight stay hidden; each tile has its own.
  readonly property var tileInfo: row.menu.allTileAt(row.index, row.menu.layoutSerial)
  readonly property bool tiled: row.tileInfo !== null

  readonly property bool hasCursor: row.menu.cursorActive && row.index === row.menu.selectedIndex && row.kind !== "example"
    && (!row.menu.systemTwoPane || row.menu.systemPane === "right") && !row.tiled
  // Window rows borrow their application's icon when a desktop entry
  // matches the window class, and fall back to a glyph when none does.
  readonly property bool isApp: !row.tiled && (row.kind === "app" || (row.kind === "window" && row.appIcon.length > 0))
  readonly property bool hasIcon: !row.tiled && (row.icon.length > 0 || row.isApp)
  // Open windows of an application row, for the running marker.
  readonly property int windowCount: row.kind === "app" && !row.tiled ? row.menu.appWindowCount(row.appId) : 0
  readonly property string trailShown: row.tiled ? "" : row.trailText.length > 0 ? row.trailText : Windows.runningLabel(row.windowCount)

  // Command examples are a read-only hint.
  opacity: row.kind === "example" ? 0.7 : 1
  width: ListView.view.width
  height: row.tiled ? row.menu.allTileRowHeight(row.index) : row.menu.rowHeightForDetail(row.detail, row.kind)
  radius: row.menu.cornerRadius
  color: row.hasCursor ? row.menu.selectedBackground : "transparent"
  borderSpec: row.hasCursor ? row.menu.selectedBorderSpec : Border.none()

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

  Text {
    id: iconText
    textFormat: Text.PlainText
    visible: row.hasIcon && !row.isApp
    text: row.icon
    color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
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
    visible: !row.tiled
    anchors.left: row.hasIcon ? iconText.right : parent.left
    anchors.leftMargin: row.hasIcon ? Style.space(6) : row.menu.rowReservedBorderLeft + Style.space(18)
    anchors.right: trailLabel.visible ? trailLabel.left : trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      id: labelText
      textFormat: Text.PlainText
      width: parent.width
      text: row.label
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
    color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
    opacity: 0.45
    font.family: row.menu.fontFamily
    font.pixelSize: row.menu.scaledFont(Style.font.bodySmall)
    anchors.right: trail.left
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
  }

  Row {
    id: trail
    visible: !row.tiled
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
      color: row.hasCursor ? row.menu.selectedText : row.menu.foreground
      opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
      font.family: row.menu.fontFamily
      font.pixelSize: row.menu.scaledFont(Style.font.heading)
      font.weight: Font.Normal
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // The strip: up to `columns` tiles across the row's width, the whole tile
  // height tall (the row itself is shorter on purpose; see
  // AllTiles.stripHeight). Only a lead carries tiles.
  Repeater {
    model: row.tiled && row.tileInfo.tiles ? row.tileInfo.tiles : []

    delegate: Item {
      id: cell
      required property var modelData
      readonly property real cellWidth: row.width / Math.max(1, row.menu.allTileColumns)

      x: cell.modelData.col * cell.cellWidth
      width: cell.cellWidth
      height: row.menu.allTileHeight

      AppTile {
        menu: row.menu
        tileIndex: cell.modelData.index
        tileLabel: cell.modelData.row.label
        tileIcon: cell.modelData.row.appIcon
        tileKind: cell.modelData.row.kind
        tileAppId: cell.modelData.row.appId
        width: parent.width - Style.space(6)
        height: parent.height - Style.space(6)
        anchors.centerIn: parent
      }
    }
  }

  MouseArea {
    id: mouseArea
    enabled: !row.tiled
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
