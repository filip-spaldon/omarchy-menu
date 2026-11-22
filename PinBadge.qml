import QtQuick
import qs.Commons

// The pin marker: a thumbtack glyph on an accent circle, no ring. On an app's icon it
// says the app is pinned (its copy outside the pinned strip); on the strip's
// corner it names the strip.
Rectangle {
  id: badge

  required property real sizeScale
  property string fontFamily: ""
  property color ring: "transparent"

  width: height
  height: Math.round(Style.space(18) * badge.sizeScale)
  radius: height / 2
  color: Color.accent

  Text {
    textFormat: Text.PlainText
    text: "\uf08d"
    color: Color.menu.background
    font.family: badge.fontFamily
    font.pixelSize: Math.max(1, Math.round(Style.space(12) * badge.sizeScale))
    anchors.centerIn: parent
  }
}
