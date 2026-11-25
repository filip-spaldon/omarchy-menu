import QtQuick
import qs.Commons
import "KeySheet.js" as KeySheet

// A key as the footer draws it: the key's name in an outlined box.
// The footer and the System tab's shortcut hints share it.
Rectangle {
  id: cap

  required property string text
  required property real fontSize
  property string fontFamily: ""
  property color ink: Color.menu.foreground

  width: label.implicitWidth + Style.space(8)
  height: label.implicitHeight + Style.space(2)
  implicitWidth: width
  implicitHeight: height
  radius: Style.space(3)
  color: "transparent"
  border.width: 1
  border.color: Util.alpha(cap.ink, 0.32)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: KeySheet.keyGlyphs(cap.text)
    color: cap.ink
    opacity: 0.8
    font.family: cap.fontFamily
    font.pixelSize: cap.fontSize
  }
}
