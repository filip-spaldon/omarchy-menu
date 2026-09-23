import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The AI answer: status chip (agent, model, effort, state), the streaming
// answer and the key hints. State comes from the AI controller; the menu
// scrolls the answer through answerFlick.
Item {
  id: panel
  required property var menu
  required property var ai
  property alias answerFlick: aiAnswerFlick

  Rectangle {
    id: aiChip
    height: aiChipLabel.implicitHeight + Style.space(10)
    width: aiChipLabel.implicitWidth + Style.space(18)
    radius: height / 2
    color: panel.ai.aiSession && panel.ai.aiSession.state === "error" ? Util.alpha(Color.urgent, 0.18) : Util.alpha(Color.accent, 0.22)

    Text {
      id: aiChipLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: panel.ai.aiChipText()
      color: panel.ai.aiSession && panel.ai.aiSession.state === "error" ? Color.urgent : Color.accent
      font.family: panel.menu.fontFamily
      font.pixelSize: panel.menu.scaledFont(Style.font.body)
    }
  }

  Text {
    visible: panel.ai.aiConfigWarning !== ""
    anchors.left: aiChip.right
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.verticalCenter: aiChip.verticalCenter
    textFormat: Text.PlainText
    text: panel.ai.aiConfigWarning
    color: panel.menu.foreground
    opacity: 0.55
    elide: Text.ElideRight
    font.family: panel.menu.fontFamily
    font.pixelSize: panel.menu.scaledFont(Style.font.caption)
  }

  Rectangle {
    id: aiAnswerBox
    anchors.top: aiChip.bottom
    anchors.topMargin: panel.menu.contentSpacing
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: aiFooter.top
    anchors.bottomMargin: panel.menu.contentSpacing
    radius: panel.menu.cornerRadius
    color: Util.alpha(panel.menu.foreground, 0.05)
    visible: !!panel.ai.aiSession && panel.ai.aiSession.state !== "idle"

    Flickable {
      id: aiAnswerFlick
      anchors.fill: parent
      anchors.margins: Style.space(10)
      clip: true
      contentWidth: width
      contentHeight: aiAnswerText.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      property bool pinnedToBottom: true

      onContentHeightChanged: {
        if (aiAnswerFlick.pinnedToBottom)
          aiAnswerFlick.contentY = Math.max(0, aiAnswerFlick.contentHeight - aiAnswerFlick.height)
      }
      onMovementEnded: {
        aiAnswerFlick.pinnedToBottom = aiAnswerFlick.contentY >= (aiAnswerFlick.contentHeight - aiAnswerFlick.height - 4)
      }

      Text {
        id: aiAnswerText
        width: aiAnswerFlick.width
        text: {
          var s = panel.ai.aiSession
          if (!s) return ""
          if (s.state !== "error") return panel.ai.aiRenderable(s.displayedText)
          var msg = panel.ai.aiRenderable(s.errorMessage || "")
          return s.displayedText && s.displayedText.length > 0
            ? panel.ai.aiRenderable(s.displayedText) + "\n\n⚠ " + msg
            : msg
        }
        textFormat: Text.MarkdownText
        onLinkActivated: function(link) { panel.ai.aiOpenLink(link) }
        wrapMode: Text.Wrap
        color: (panel.ai.aiSession && panel.ai.aiSession.state === "error"
                && (!panel.ai.aiSession.displayedText || panel.ai.aiSession.displayedText.length === 0))
          ? Color.urgent : panel.menu.foreground
        font.family: panel.menu.fontFamily
        font.pixelSize: panel.menu.scaledFont(Style.font.body)
      }
    }
  }

  Text {
    id: aiFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: panel.ai.aiFooterText()
    color: panel.menu.foreground
    opacity: 0.5
    wrapMode: Text.Wrap
    font.family: panel.menu.fontFamily
    font.pixelSize: panel.menu.scaledFont(Style.font.caption)
  }
}
