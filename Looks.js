// Looks: the launcher's switchable designs. style.json "look" picks one;
// "classic" is the stock card. Not called themes: Omarchy themes are
// colours, and every look follows them. A look is a name here plus a
// State in the QML that sets what it changes (Menu.qml, "What a look can
// change"); whatever it leaves alone stays as classic. Pure data in, data
// out, so it runs under node.

var DEFAULT_LOOK = "classic"

// In the order Alt+L goes through them.
var LOOKS = [
  { name: "classic", label: "Classic" },
]

function entry(name) {
  for (var i = 0; i < LOOKS.length; i++) if (LOOKS[i].name === name) return LOOKS[i]
  return null
}

function isLook(name) {
  return entry(name) !== null
}

// The look named in a parsed style.json, or classic.
function styleLook(style) {
  var name = style ? style.look : undefined
  return isLook(name) ? name : DEFAULT_LOOK
}

function cycleLook(name, direction) {
  var i = 0
  while (i < LOOKS.length && LOOKS[i].name !== name) i++
  if (i === LOOKS.length) i = 0
  return LOOKS[(i + direction + LOOKS.length) % LOOKS.length].name
}

function lookLabel(name) {
  return (entry(name) || entry(DEFAULT_LOOK)).label
}

if (typeof module !== "undefined") {
  module.exports = {
    LOOKS: LOOKS,
    DEFAULT_LOOK: DEFAULT_LOOK,
    isLook: isLook,
    styleLook: styleLook,
    cycleLook: cycleLook,
    lookLabel: lookLabel
  }
}
