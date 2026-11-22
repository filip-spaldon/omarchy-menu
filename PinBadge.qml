import QtQuick
import qs.Commons

// The pin marker: an accent circle with a pin glyph. On an app's icon it
// says the app is pinned (its copy outside the pinned strip); on the strip's
// corner it names the strip. Ringed in `ring`, like RunningBadge.
Rectangle {
  id: badge

  required property real sizeScale
  property string fontFamily: ""
  property color ring: "transparent"

  width: height
  height: Math.round(Style.space(18) * badge.sizeScale)
  radius: height / 2
  color: Color.accent
  border.width: Math.max(1, Math.round(Style.space(2) * badge.sizeScale))
  border.color: badge.ring

  Text {
    textFormat: Text.PlainText
    text: "󰐃"
    color: Color.menu.background
    font.family: badge.fontFamily
    font.pixelSize: Math.max(1, Math.round(Style.space(12) * badge.sizeScale))
    anchors.centerIn: parent
  }
}
