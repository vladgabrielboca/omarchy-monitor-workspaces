.pragma library

// Pure helpers, kept out of the QML so tests/model-test.sh can run them.
// Mirrors hypr/monitor-workspaces.lua. Without Omarchy's engine, monitors
// ordered left to right (then top to bottom) each own a block of BLOCK real
// workspaces; with it, Omarchy's block file decides (see parseBlocks).

var BLOCK = 10
var ALWAYS_SHOWN = 5

// `monitors` is a list of { name, x, y, mirror }. Returns the first real
// workspace id of `name`'s block, or 1 when the monitor is unknown.
function firstWorkspace(monitors, name) {
  var real = []
  for (var i = 0; i < monitors.length; i++) {
    var m = monitors[i]
    if (m && !m.mirror) real.push(m)
  }
  real.sort(function(a, b) { return a.x !== b.x ? a.x - b.x : a.y - b.y })
  for (var j = 0; j < real.length; j++) {
    if (real[j].name === name) return j * BLOCK + 1
  }
  return 1
}

// Omarchy's block file: one "block<TAB>connector<TAB>identity" line per
// monitor it has seen. Returns { connector: block }; malformed lines are skipped.
function parseBlocks(text) {
  var blocks = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length && i < 256; i++) {
    var fields = lines[i].split("\t")
    if (fields.length < 3 || fields[1] === "" || !/^[0-9]{1,3}$/.test(fields[0])) continue
    blocks[fields[1]] = parseInt(fields[0], 10)
  }
  return blocks
}

// The first real workspace of `name`'s block under Omarchy's engine. Until it
// has written the file, the workspace the monitor shows is taken to be its own.
function builtinFirst(blocks, name, activeId) {
  var block = blocks ? blocks[name] : undefined
  if (block === undefined) block = activeId > 0 ? Math.floor((activeId - 1) / BLOCK) : 0
  return block * BLOCK + 1
}

// Ids to draw: the first ALWAYS_SHOWN slots of the block, plus any other
// existing workspace in `existingIds` that falls inside it, then any workspace
// in `guestIds` (on this monitor but from another block, as after unplugging
// the monitor it belonged to).
function visibleIds(first, existingIds, guestIds) {
  var ids = []
  for (var slot = 0; slot < ALWAYS_SHOWN; slot++) ids.push(first + slot)
  for (var i = 0; i < existingIds.length; i++) {
    var id = existingIds[i]
    if (id >= first && id < first + BLOCK && ids.indexOf(id) === -1) ids.push(id)
  }
  ids.sort(function(a, b) { return a - b })

  var guests = []
  var others = guestIds || []
  for (var j = 0; j < others.length; j++) {
    var guest = others[j]
    if (guest > 0 && (guest < first || guest >= first + BLOCK) && guests.indexOf(guest) === -1) guests.push(guest)
  }
  guests.sort(function(a, b) { return a - b })
  return ids.concat(guests)
}

// The label for a real id within the block starting at `first`: 1..9, then 0.
// A workspace from another block shows its slot there in parentheses.
function slotLabel(first, id) {
  var slot = id - first + 1
  if (slot >= 1 && slot <= BLOCK) return slot === 10 ? "0" : String(slot)
  var home = ((id - 1) % BLOCK) + 1
  return "(" + (home === 10 ? "0" : String(home)) + ")"
}

// Strip markup-shaped characters before text reaches a shared tooltip sink.
function plain(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[<>&"']/g, "")
    .slice(0, 64)
}

// ---- Highlight colour. Each theme keeps its own choice in a small JSON map,
// { "<theme>": { mode, hex } }, so one theme's colour never carries over to
// another. A preset mode is kept by name rather than by value, so it follows
// the theme if the theme's palette changes; `hex` is the last custom colour,
// kept even while a preset is chosen so Custom returns to it.

var MODES = ["accent", "alert", "border", "plain", "custom"]
var DEFAULT_MODE = "accent"

// "#abc", "abc", "#aabbcc" or "aabbcc", any case, to "#aabbcc"; "" otherwise.
function normalizeHex(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "").replace(/^#/, "")
  if (/^[0-9a-fA-F]{3}$/.test(text)) text = text.charAt(0) + text.charAt(0) + text.charAt(1) + text.charAt(1) + text.charAt(2) + text.charAt(2)
  return /^[0-9a-fA-F]{6}$/.test(text) ? "#" + text.toLowerCase() : ""
}

// The saved map, with anything malformed dropped.
function parseHighlights(text) {
  var parsed = null
  try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
  var map = {}
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return map
  for (var theme in parsed) {
    var entry = parsed[theme]
    if (!entry || typeof entry !== "object" || MODES.indexOf(entry.mode) === -1) continue
    var hex = normalizeHex(entry.hex)
    if (entry.mode === "custom" && hex === "") continue
    map[theme] = { mode: entry.mode, hex: hex }
  }
  return map
}

// The choice for `theme`; a theme never set uses the accent.
function highlightFor(map, theme) {
  var entry = map ? map[theme] : undefined
  return entry ? { mode: entry.mode, hex: entry.hex } : { mode: DEFAULT_MODE, hex: "" }
}

// A copy of `map` with `theme` set to `mode` (and `hex` for custom). Choosing
// a preset keeps the theme's last custom colour; `mode` null forgets the theme.
function withHighlight(map, theme, mode, hex) {
  var next = {}
  for (var key in map) next[key] = map[key]
  if (mode === null) {
    delete next[theme]
    return next
  }
  var previous = highlightFor(map, theme)
  var kept = mode === "custom" ? normalizeHex(hex) : previous.hex
  if (mode === "custom" && kept === "") return next
  next[theme] = { mode: mode, hex: kept }
  return next
}

// "catppuccin-latte" -> "Catppuccin Latte"
function themeTitle(name) {
  return plain(name).split(/[-_\s]+/).filter(function(w) { return w !== "" }).map(function(w) {
    return w.charAt(0).toUpperCase() + w.slice(1)
  }).join(" ")
}

// HSV with every component in 0..1, for the picker.
function hexToHsv(hex) {
  var clean = normalizeHex(hex) || "#000000"
  var r = parseInt(clean.substr(1, 2), 16) / 255
  var g = parseInt(clean.substr(3, 2), 16) / 255
  var b = parseInt(clean.substr(5, 2), 16) / 255
  var max = Math.max(r, g, b)
  var delta = max - Math.min(r, g, b)
  var h = 0
  if (delta > 0) {
    if (max === r) h = ((g - b) / delta) % 6
    else if (max === g) h = (b - r) / delta + 2
    else h = (r - g) / delta + 4
    h /= 6
    if (h < 0) h += 1
  }
  return { h: h, s: max === 0 ? 0 : delta / max, v: max }
}

function hsvToHex(h, s, v) {
  h = Math.min(Math.max(h, 0), 1)
  s = Math.min(Math.max(s, 0), 1)
  v = Math.min(Math.max(v, 0), 1)
  var i = Math.floor(h * 6) % 6
  var f = h * 6 - Math.floor(h * 6)
  var p = v * (1 - s)
  var q = v * (1 - f * s)
  var t = v * (1 - (1 - f) * s)
  var rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i]
  return "#" + rgb.map(function(c) {
    var n = Math.round(c * 255).toString(16)
    return n.length === 1 ? "0" + n : n
  }).join("")
}
