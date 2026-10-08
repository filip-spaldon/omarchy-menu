import QtQuick

// No shell dependencies: the same constraints are exercised in Qt tests.
QtObject {
  property real viewportHeight: 0
  property real gap: 0
  property real requestedTop: -1
  // The card's bottom edge, when it is pinned to the bottom of the screen
  // (>= 0 wins over requestedTop): the card then grows upward from it.
  property real requestedBottom: -1
  // How far a centred card is moved down (negative: up) from the centre.
  property real centerShift: 0
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
  readonly property bool bottomAnchored: requestedBottom >= 0
  // Pinned to the bottom: the edge the card grows up from, raised if needed
  // so the smallest full card still fits above it.
  readonly property real bottomEdge: Math.min(viewportHeight - gap, Math.max(requestedBottom, gap + minimumHeight))
  // bottomEdge as it stands once the rows want at least minimumBodyHeight,
  // for a caller budgeting those rows: bottomEdge itself reads
  // desiredBodyHeight (through minimumHeight), so a budget that feeds
  // desiredBodyHeight cannot bind to it. `chrome` is what the caller counts
  // above and below its rows.
  function rowsBottomEdge(chrome) {
    return Math.min(viewportHeight - gap,
      Math.max(requestedBottom, gap + Math.min(maximumHeight, chrome + minimumBodyHeight)))
  }
  readonly property real cardTop: bottomAnchored
    ? Math.max(gap, bottomEdge - contentHeight)
    : requestedTop < 0
      ? Math.max(gap, Math.min((viewportHeight - centeredHeight) / 2 + centerShift, viewportHeight - gap - centeredHeight))
      : Math.max(gap, Math.min(requestedTop, viewportHeight - gap - minimumHeight))
  // If even the controls and a row cannot fit, the outer Flickable scrolls
  // the whole content. Results remain reachable rather than disappearing.
  readonly property real bodyHeight: desiredBodyHeight <= 0 ? 0
    : Math.max(Math.min(desiredBodyHeight, minimumBodyHeight),
        Math.min(desiredBodyHeight, (bottomAnchored ? bottomEdge - gap : viewportHeight - gap - cardTop) - chromeHeight))
  readonly property real contentHeight: chromeHeight + bodyHeight
  readonly property real cardHeight: Math.max(0, Math.min(contentHeight, viewportHeight - gap - cardTop))
}
