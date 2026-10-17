.pragma library

// Pure helpers, kept out of the QML so tests/model-test.sh can run them.
// Mirrors hypr/monitor-workspaces.lua: monitors ordered left to
// right (then top to bottom) each own a block of BLOCK real workspaces.

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
