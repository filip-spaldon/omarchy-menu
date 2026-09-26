import QtQuick
import qs.Commons

// The running marker on an application's icon: an accent dot on its
// bottom-right corner, carrying the window count once there is more than
// one. Ringed in `ring` (whatever it sits on) so it reads over any icon.
Rectangle {
  id: badge

  required property int count
  required property real sizeScale
  property color ring: "transparent"

  readonly property bool numbered: badge.count > 1

  visible: badge.count > 0
  width: badge.numbered ? Math.max(height, countText.implicitWidth + Style.space(6) * badge.sizeScale) : height
  height: Math.round(Style.space(badge.numbered ? 14 : 9) * badge.sizeScale)
  radius: height / 2
  color: Color.accent
  border.width: Math.max(1, Math.round(Style.space(2) * badge.sizeScale))
  border.color: badge.ring

  Text {
    id: countText
    textFormat: Text.PlainText
    visible: badge.numbered
    text: badge.count > 9 ? "9+" : String(badge.count)
    color: Color.menu.background
    font.pixelSize: Math.max(1, Math.round(Style.space(9) * badge.sizeScale))
    font.weight: Font.Bold
    anchors.centerIn: parent
  }
}
