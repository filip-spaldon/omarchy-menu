import QtQuick
import qs.Commons

// One number for the keyboard's numbered shortcuts: Ctrl+1…9 over the tabs
// and Alt+1…9 over the rows look the same. A filled keycap, or, for looks
// whose tabs are bare words, a small accent figure.
Item {
  id: cap

  required property string number
  required property real fontSize
  property string fontFamily: ""
  property bool bare: false
  property color ink: Color.menu.foreground
  property color paper: Color.menu.background

  implicitWidth: cap.bare ? figure.implicitWidth : Math.max(cap.implicitHeight, figure.implicitWidth + Style.space(6))
  implicitHeight: cap.bare ? figure.implicitHeight : Math.round(cap.fontSize * 1.05)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    visible: !cap.bare
    anchors.fill: parent
    radius: Style.space(4)
    color: cap.ink
  }

  Text {
    id: figure
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: cap.number
    color: cap.bare ? Color.accent : cap.paper
    font.family: cap.fontFamily
    font.pixelSize: Math.max(1, Math.round(cap.fontSize * (cap.bare ? 0.75 : 0.8)))
    font.weight: cap.bare ? Font.DemiBold : Font.Bold
  }
}
