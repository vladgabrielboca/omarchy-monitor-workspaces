#!/usr/bin/env bash
# Loads hypr/monitor-workspaces.lua against a stand-in for Hyprland's Lua API,
# with and without Omarchy's built-in engine (o.workspaces), and checks what
# each mode registers and what the shared keys do.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v lua >/dev/null || { echo "SKIP: lua not installed"; exit 0; }
export XDG_RUNTIME_DIR=$(mktemp -d)
trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT

lua - "$ROOT/hypr/monitor-workspaces.lua" <<'LUA'
local plugin = arg[1]

local function workspace(id, monitor) return { id = id, windows = 0, visible = true, monitor = monitor } end

local function fresh(with_builtin)
  local left = { name = "DP-2", x = 0, y = 0, width = 1920, height = 1080, scale = 1 }
  local main = { name = "DP-1", x = 1920, y = -140, width = 2560, height = 1440, scale = 1, focused = true }
  left.active_workspace = workspace(1, left)
  main.active_workspace = workspace(11, main)
  local state = { rules = 0, binds = {}, dispatched = {}, focus_calls = {}, events = {}, active = main }
  local window = { address = "0xabc" }

  hl = {
    get_monitors = function() return { main, left } end,
    get_active_monitor = function() return state.active end,
    get_monitor = function(name) return name == "DP-1" and main or name == "DP-2" and left or nil end,
    get_active_window = function() return window end,
    get_workspace = function() return nil end,
    get_config = function() return "" end,
    workspace_rule = function() state.rules = state.rules + 1; return { set_enabled = function() end } end,
    unbind = function() end,
    on = function(name, fn) state.events[name] = fn end,
    timer = function(fn) return { set_enabled = function() end } end,
    dispatch = function(d) state.dispatched[#state.dispatched + 1] = d end,
    dsp = {
      focus = function(t) return { focus = t } end,
      window = { move = function(t) return { move = t } end },
    },
  }
  o = { bind = function(keys, desc, fn) state.binds[keys] = fn end }
  if with_builtin then
    o.workspaces = {
      workspace_id = function(monitor, slot) return (monitor.name == "DP-1" and 0 or 1) * 10 + slot end,
      focus = function(slot, name)
        return function() state.focus_calls[#state.focus_calls + 1] = name .. ":" .. slot end
      end,
    }
  end
  dofile(plugin)
  return state
end

local function count(binds, pattern)
  local n = 0
  for keys in pairs(binds) do if keys:match(pattern) then n = n + 1 end end
  return n
end

local function last_move(state)
  for i = #state.dispatched, 1, -1 do
    if state.dispatched[i].move then return state.dispatched[i].move end
  end
end

-- Omarchy's engine present: no rules or SUPER + 1..0 of our own.
local s = fresh(true)
assert(s.rules == 0, "built-in mode must not add workspace rules")
assert(count(s.binds, "^SUPER %+ code:") == 0, "built-in mode must leave SUPER + 1..0 to Omarchy")
assert(count(s.binds, "^SUPER %+ CTRL %+ SHIFT %+ code:") == 10, "missing SUPER + CTRL + SHIFT + 1..0")
assert(s.binds["SUPER + TAB"] and s.binds["SUPER + SHIFT + TAB"], "missing SUPER + TAB binds")
assert(s.events["hyprland.start"] and s.events["monitor.added"], "missing login focus handlers")
-- From the main monitor, slot 3 on the next one is the left monitor's block (13
-- under Omarchy's assignment), made to exist there through Omarchy's focus.
s.binds["SUPER + CTRL + SHIFT + code:12"]()
assert(s.focus_calls[1] == "DP-2:3", "should focus slot 3 on DP-2 first, got " .. tostring(s.focus_calls[1]))
assert(last_move(s).workspace == "13" and last_move(s).window == "address:0xabc", "window not sent to 13")

-- Without it: our own engine, rules for both blocks, our own SUPER + 1..0.
s = fresh(false)
assert(s.rules == 20, "fallback mode should pin 2 x 10 workspaces, got " .. s.rules)
assert(count(s.binds, "^SUPER %+ code:") == 10, "fallback mode needs SUPER + 1..0")
assert(count(s.binds, "^SUPER %+ SHIFT %+ code:") == 10, "fallback mode needs SUPER + SHIFT + 1..0")
assert(count(s.binds, "^SUPER %+ CTRL %+ SHIFT %+ code:") == 10, "missing SUPER + CTRL + SHIFT + 1..0")
-- Left to right: DP-2 owns 1-10, so slot 3 on it from the main monitor is 3.
s.binds["SUPER + CTRL + SHIFT + code:12"]()
assert(last_move(s).workspace == "3", "fallback should send to 3, got " .. tostring(last_move(s).workspace))
-- SUPER + 2 on the main monitor (second from the left) is 12.
s.binds["SUPER + code:11"]()
assert(s.dispatched[#s.dispatched].focus.workspace == "12", "SUPER + 2 on DP-1 should be 12")

-- SUPER + TAB goes to the next monitor left to right, wrapping.
s.binds["SUPER + TAB"]()
assert(s.dispatched[#s.dispatched].focus.monitor == "DP-2", "SUPER + TAB from DP-1 should wrap to DP-2")
print("ok")
LUA
