import QtQuick
import qs.Commons

// The Apps tab's pinned strip: an accent tint and outline with the pin
// marker in its corner. The card's grid (AppGrid.qml), the looks' grids and
// the list's pinned block (TileStrip.qml) all draw it behind the strip.
Rectangle {
  id: frame
  required property var menu

  radius: frame.menu.cornerRadius
  color: frame.menu.pinnedBackground
  border.width: Math.max(1, Style.space(1))
  border.color: frame.menu.pinnedBorder

  PinBadge {
    z: 1
    sizeScale: frame.menu.menuFontScale
    fontFamily: frame.menu.fontFamily
    ring: frame.menu.background
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(6)
  }
}
