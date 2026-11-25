// Lua dispatchers hide the command. Only infer a hint when both the active
// description and chord match a known Omarchy binding, and the menu action
// still matches the packaged one. Real exec bindings can match by command.
const STOCK = {
  "system.lock": ["omarchy-system-lock", "Lock system", ["Super+Ctrl+L"]],
  "learn.keybindings": ["omarchy-menu-keybindings", "Keybindings", ["Super+K"]],
  "learn.tmux-keybindings": ["omarchy-menu-tmux-keybindings", "Tmux keybindings", ["Super+Alt+K"]],
  "learn.herdr-keybindings": ["omarchy-menu-herdr-keybindings", "Herdr keybindings", ["Super+Ctrl+K"]],
  "appearance.theme": ['omarchy-shell shell summon omarchy.image-picker \'{"source":"themes"}\'',
    "Theme menu", ["Super+Ctrl+T", "Super+Ctrl+Shift+Space"]],
  "trigger.emoji": ["omarchy-menu-emoji", "Emojis", ["Super+Ctrl+E"]],
  "trigger.clipboard-history": ["omarchy-shell shell summon omarchy.clipboard", "Clipboard manager", ["Super+Ctrl+V"]],
  "trigger.capture": ["", "Capture menu", ["Super+Ctrl+C"]],
  "trigger.toggle": ["", "Toggle menu", ["Super+Ctrl+O"]],
  "trigger.hardware": ["", "Hardware menu", ["Super+Ctrl+H"]],
  "trigger.capture.screenshot": ["omarchy-capture-screenshot", "Screenshot", ["Print", "Super+Ctrl+Alt+C"]],
  "trigger.capture.text": ["omarchy-capture-text", "Extract text (OCR) from screenshot", ["Super+Ctrl+Print"]],
  "trigger.capture.color": ["pkill hyprpicker || hyprpicker -a", "Color picker", ["Super+Print"]],
  "trigger.share": ["", "Share", ["Super+Ctrl+S"]],
  // Omni's own binding (README) or Omarchy's: either description counts.
  "system": ["", ["System menu", "System (Omni menu)", "System (Omni)"], ["Super+Esc"]]
}

const MODIFIERS = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "CapsLock"],
  [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]]
const KEY_NAMES = { SPACE: "Space", ESCAPE: "Esc", RETURN: "Enter", PRINT: "Print", BACKSPACE: "Backspace",
  TAB: "Tab", DELETE: "Delete", COMMA: ",", PERIOD: ".", SLASH: "/", BACKSLASH: "\\", MINUS: "-", EQUAL: "=" }
const MAX_INPUT = 262144

function bindingChord(bind) {
  if (!bind || (bind.submap && bind.submap !== "reset") || bind.mouse || bind.catch_all) return ""
  const mask = bind.modmask
  if (typeof mask !== "number" || mask < 0 || mask > 255 || Math.floor(mask) !== mask) return ""
  // Some Hyprland versions prefix the keysym with the modifier names.
  const key = typeof bind.key === "string" ? bind.key.split(" + ").pop() : ""
  if (!/^[A-Za-z0-9_]{1,24}$/.test(key)) return ""
  const upper = key.toUpperCase()
  const name = KEY_NAMES[upper] || (/^(?:[A-Z0-9]|F[0-9]{1,2})$/.test(upper) ? upper : key)
  return MODIFIERS.filter(pair => mask & pair[0]).map(pair => pair[1]).concat(name).join("+")
}

function parseBindings(text) {
  const empty = { exec: Object.create(null), lua: Object.create(null) }
  if (typeof text !== "string" || text.length > MAX_INPUT) return empty
  let binds
  try { binds = JSON.parse(text) } catch (e) { return empty }
  if (!Array.isArray(binds) || binds.length > 2000) return empty
  const chords = Object.create(null)
  binds.forEach(bind => {
    const chord = bindingChord(bind)
    if (!chord) return
    const held = chords[chord]
    if (held === undefined) chords[chord] = bind
    // A lock-screen bind on the same chord (`locked`, which only acts behind
    // the lock) does not make the desktop's bind ambiguous.
    else if (held && held.locked && !bind.locked) chords[chord] = bind
    else if (held && !held.locked && bind.locked) return
    else chords[chord] = null // Ambiguous global chord.
  })
  Object.keys(chords).forEach(chord => {
    const bind = chords[chord]
    if (!bind) return
    if (bind.dispatcher === "__lua" && typeof bind.description === "string") {
      empty.lua[chord] = bind.description
    } else if (bind.dispatcher === "exec" && typeof bind.arg === "string" && bind.arg.length <= 4096) {
      const action = bind.arg.trim()
      const current = empty.exec[action]
      if (!current || chord.length < current.length || (chord.length === current.length && chord < current))
        empty.exec[action] = chord
    }
  })
  return empty
}

function hintFor(bindings, itemId, kind, action) {
  if (!bindings || (kind !== "action" && kind !== "menu")) return ""
  if (kind === "action" && action && bindings.exec[action]) return bindings.exec[action]
  const stock = Object.prototype.hasOwnProperty.call(STOCK, itemId) ? STOCK[itemId] : null
  if (!stock || action !== stock[0] || kind !== (stock[0] ? "action" : "menu")) return ""
  const names = Array.isArray(stock[1]) ? stock[1] : [stock[1]]
  return stock[2].find(chord => names.indexOf(bindings.lua[chord]) >= 0) || ""
}

// A chord as a keycap reads it: "Super+Ctrl+L" is "SUPER+CTRL+L".
function capLabel(chord) {
  return String(chord || "").toUpperCase()
}

if (typeof module !== "undefined") module.exports = { bindingChord, parseBindings, hintFor, capLabel }
