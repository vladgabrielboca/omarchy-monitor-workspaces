-- Monitor Workspaces for Omarchy: each monitor owns a block of ten real
-- workspaces, ordered by physical position from left to right, and
-- SUPER + 1..0 acts on the focused monitor's block. The bar widget in this
-- plugin uses the same ordering and shows every block as 1..9, 0.
--
--   1st monitor from the left -> workspaces 1-10
--   2nd monitor               -> workspaces 11-20
--   3rd monitor               -> workspaces 21-30, and so on
--
-- SUPER + TAB focuses the next monitor; SUPER + SHIFT + TAB moves the active
-- window there, and SUPER + CTRL + SHIFT + 1..0 moves it straight to that slot
-- on the next monitor. Loaded from ~/.config/hypr/hyprland.lua by the plugin's
-- `setup` script; `teardown` removes that hook.

local block = 10

-- Real monitors (mirrors share a screen), left to right, then top to bottom.
local function ordered_monitors()
  local monitors = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror then monitors[#monitors + 1] = monitor end
  end
  table.sort(monitors, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  return monitors
end

local function first_workspace(monitor)
  for index, candidate in ipairs(ordered_monitors()) do
    if monitor and candidate.name == monitor.name then return (index - 1) * block + 1 end
  end
  return 1
end

local function in_block(id, first)
  return id >= first and id < first + block
end

-- Pin each block to its monitor, and move a monitor still showing an empty
-- workspace from someone else's block (as at login) onto its own first one.
local rules = {}
local function apply_rules()
  for _, rule in ipairs(rules) do
    if rule and rule.set_enabled then rule:set_enabled(false) end
  end
  rules = {}

  local monitors = ordered_monitors()
  for index, monitor in ipairs(monitors) do
    local first = (index - 1) * block + 1
    for offset = 0, block - 1 do
      rules[#rules + 1] = hl.workspace_rule({
        workspace = tostring(first + offset),
        monitor = monitor.name,
        default = offset == 0,
        persistent = offset == 0,
      })
    end
  end

  local focused = hl.get_active_monitor()
  local moved = false
  for index, monitor in ipairs(monitors) do
    local first = (index - 1) * block + 1
    local workspace = monitor.active_workspace
    if workspace and not in_block(workspace.id, first) and workspace.windows == 0 then
      hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
      hl.dispatch(hl.dsp.focus({ workspace = tostring(first) }))
      moved = true
    end
  end
  if moved and focused then hl.dispatch(hl.dsp.focus({ monitor = focused.name })) end
end

apply_rules()
hl.on("monitor.added", apply_rules)
hl.on("monitor.removed", apply_rules)
hl.on("monitor.layout_changed", apply_rules)

-- The focused monitor's real workspace for slot 1..10.
local function workspace_for(slot)
  return tostring(first_workspace(hl.get_active_monitor()) + slot - 1)
end

-- Slot 1..10 on the monitor after the focused one, wrapping around; with a
-- single monitor that is the focused monitor itself.
local function next_monitor_workspace_for(slot)
  local monitors = ordered_monitors()
  local active = hl.get_active_monitor()
  local index = 1
  for i, monitor in ipairs(monitors) do
    if active and monitor.name == active.name then index = i end
  end
  return tostring((index % math.max(#monitors, 1)) * block + slot)
end

for slot = 1, block do
  local key = "code:" .. tostring(slot + 9)
  local label = slot == 10 and "0" or tostring(slot)
  hl.unbind("SUPER + " .. key)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)

  o.bind("SUPER + " .. key, "Switch to workspace " .. label .. " on this monitor", function()
    hl.dispatch(hl.dsp.focus({ workspace = workspace_for(slot) }))
  end)
  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. label .. " on this monitor", function()
    hl.dispatch(hl.dsp.window.move({ workspace = workspace_for(slot) }))
  end)
  o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. label .. " on this monitor", function()
    hl.dispatch(hl.dsp.window.move({ workspace = workspace_for(slot), follow = false }))
  end)

  hl.unbind("SUPER + CTRL + SHIFT + " .. key)
  o.bind("SUPER + CTRL + SHIFT + " .. key, "Move window to workspace " .. label .. " on the next monitor", function()
    hl.dispatch(hl.dsp.window.move({ workspace = next_monitor_workspace_for(slot) }))
  end)
end

hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Focus next monitor", hl.dsp.focus({ monitor = "+1" }))
o.bind("SUPER + SHIFT + TAB", "Move window to next monitor", hl.dsp.window.move({ monitor = "+1" }))
