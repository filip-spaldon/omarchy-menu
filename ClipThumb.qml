import QtQuick
import qs.Commons
import "Clipboard.js" as Clipboard

// A copied image's thumbnail, for the looks that draw their own rows (Mala,
// Wayfinder; the card's rows draw theirs in ResultRow.qml the same way).
// Decoded no larger than 256 px. Until it is ready, or if it cannot be
// read, the row's image glyph stands in.
Item {
  id: box
  required property var menu
  property string path: ""
  property string glyph: ""
  property string glyphFont: ""
  property color ink: box.menu.foreground

  Image {
    id: thumb
    anchors.fill: parent
    source: box.path.length > 0 ? Clipboard.imageSource(box.path) : ""
    asynchronous: true
    cache: false
    autoTransform: true
    smooth: true
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.min(256, Math.ceil(box.width * Screen.devicePixelRatio))
    sourceSize.height: Math.min(256, Math.ceil(box.height * Screen.devicePixelRatio))
  }

  Text {
    textFormat: Text.PlainText
    visible: thumb.status !== Image.Ready
    text: box.glyph
    color: box.ink
    font.family: box.glyphFont.length > 0 ? box.glyphFont : box.menu.fontFamily
    font.pixelSize: box.menu.scaledFont(Style.font.iconLarge)
    anchors.centerIn: parent
  }
}
