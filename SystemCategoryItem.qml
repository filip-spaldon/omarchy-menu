import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One category in the System tab's left pane. Highlighted when it is the
// category being browsed, filled when the keyboard is in the left pane.
BorderSurface {
  id: category
  required property var menu

  required property var modelData
  required property int index
  readonly property bool picked: category.index === category.menu.systemCategoryIndex
  readonly property bool focusedHere: category.picked && category.menu.systemPane === "left"

  width: ListView.view.width
  height: category.menu.baseRowHeight
  radius: category.menu.cornerRadius
  color: category.focusedHere ? category.menu.selectedBackground
    : (category.picked ? Util.alpha(category.menu.foreground, 0.08) : "transparent")
  borderSpec: category.focusedHere ? category.menu.selectedBorderSpec : Border.none()

  Text {
    id: categoryIcon
    textFormat: Text.PlainText
    text: category.modelData.icon
    color: category.focusedHere ? category.menu.selectedText : (category.picked ? Color.accent : category.menu.foreground)
    font.family: category.modelData.iconFont || category.menu.fontFamily
    font.pixelSize: category.menu.scaledFont(Style.font.iconLarge)
    width: category.menu.iconSlotWidth
    horizontalAlignment: Text.AlignHCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    textFormat: Text.PlainText
    text: category.modelData.label
    color: category.focusedHere ? category.menu.selectedText : category.menu.foreground
    opacity: category.picked ? 1 : 0.8
    font.family: category.menu.fontFamily
    font.pixelSize: category.menu.scaledFont(Style.font.heading)
    font.weight: category.picked ? Font.DemiBold : Font.Normal
    elide: Text.ElideRight
    anchors.left: categoryIcon.right
    anchors.leftMargin: Style.space(6)
    anchors.right: categoryChevron.left
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    id: categoryChevron
    textFormat: Text.PlainText
    text: category.modelData.kind === "menu" || category.modelData.kind === "link" ? "›" : ""
    color: category.menu.foreground
    opacity: category.picked ? 0.6 : 0.3
    font.family: category.menu.fontFamily
    font.pixelSize: category.menu.scaledFont(Style.font.heading)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (category.picked) category.menu.activateSystemCategory()
      else category.menu.selectSystemCategory(category.index)
    }
  }
}
