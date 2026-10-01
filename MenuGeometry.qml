import QtQuick

// No shell dependencies: the same constraints are exercised in Qt tests.
QtObject {
  property real viewportHeight: 0
  property real gap: 0
  property real requestedTop: -1
  property real desiredBodyHeight: 0
  property real minimumBodyHeight: 0
  property real chromeHeight: 0
  // What the card gains besides rows once it leaves the compact prompt (the
  // gap above the rows and the footer). Reserved up front so growing from the
  // prompt never has to move the card up, or push its footer off the screen.
  property real reserveHeight: 0

  readonly property real maximumHeight: Math.max(0, viewportHeight - 2 * gap)
  // A compact prompt (no body yet) reserves the room of the smallest full card.
  readonly property real minimumHeight: Math.min(maximumHeight, desiredBodyHeight > 0
    ? chromeHeight + Math.min(desiredBodyHeight, minimumBodyHeight)
    : chromeHeight + reserveHeight + minimumBodyHeight)
  readonly property real centeredHeight: Math.min(maximumHeight, chromeHeight + desiredBodyHeight)
  readonly property real cardTop: requestedTop < 0
    ? Math.max(gap, (viewportHeight - centeredHeight) / 2)
    : Math.max(gap, Math.min(requestedTop, viewportHeight - gap - minimumHeight))
  // If even the controls and a row cannot fit, the outer Flickable scrolls
  // the whole content. Results remain reachable rather than disappearing.
  readonly property real bodyHeight: desiredBodyHeight <= 0 ? 0
    : Math.max(Math.min(desiredBodyHeight, minimumBodyHeight),
        Math.min(desiredBodyHeight, viewportHeight - gap - cardTop - chromeHeight))
  readonly property real contentHeight: chromeHeight + bodyHeight
  readonly property real cardHeight: Math.max(0, Math.min(contentHeight, viewportHeight - gap - cardTop))
}
