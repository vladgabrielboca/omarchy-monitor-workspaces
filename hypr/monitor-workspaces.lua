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

-- A monitor that has just connected sits at 0,0 until Hyprland places it, on
-- top of whichever monitor is really there. Ranking monitors in that moment
-- hands the newcomer someone else's block, so wait for the layout to settle.
local function overlapping(monitors)
  for i = 1, #monitors do
    for j = i + 1, #monitors do
      local a, b = monitors[i], monitors[j]
      local aw, ah = a.width / a.scale, a.height / a.scale
      local bw, bh = b.width / b.scale, b.height / b.scale
      if a.x < b.x + bw and b.x < a.x + aw and a.y < b.y + bh and b.y < a.y + ah then return true end
    end
  end
  return false
end

-- What the last few runs saw, for diagnosing login and hotplug behaviour.
-- Lives in the runtime directory, so it starts empty after every boot.
local log_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/monitor-workspaces.log"
local function log(message)
  local file = io.open(log_path, "a")
  if not file then return end
  -- Keep it small on machines that are rarely rebooted.
  if file:seek("end") > 65536 then
    file:close()
    file = io.open(log_path, "w")
    if not file then return end
  end
  local parts = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    local workspace = monitor.active_workspace
    parts[#parts + 1] = string.format("%s@%d,%d:%s", monitor.name, monitor.x, monitor.y, workspace and workspace.id or "-")
  end
  file:write(os.date("%H:%M:%S "), message, " [", table.concat(parts, " "), "]\n")
  file:close()
end

-- Pin each block to its monitor, so a workspace created for it opens there.
--
-- The rules are deliberately neither `default` nor `persistent`: with those, a
-- monitor that connects claims its block's first workspace even while another
-- monitor is showing it, which leaves that monitor pointing at a workspace
-- Hyprland no longer draws there; its windows then vanish until you switch away.
local rules = {}
local function apply_rules()
  local monitors = ordered_monitors()
  if overlapping(monitors) then
    log("rules: skipped, monitors overlap")
    return
  end

  for _, rule in ipairs(rules) do
    if rule and rule.set_enabled then rule:set_enabled(false) end
  end
  rules = {}

  for index, monitor in ipairs(monitors) do
    local first = (index - 1) * block + 1
    for offset = 0, block - 1 do
      rules[#rules + 1] = hl.workspace_rule({
        workspace = tostring(first + offset),
        monitor = monitor.name,
      })
    end
  end
  log("rules: applied")
end

local function visible_elsewhere(id, monitor)
  local workspace = hl.get_workspace(tostring(id))
  return workspace ~= nil and workspace.visible and workspace.monitor ~= nil
    and workspace.monitor.name ~= monitor.name
end

-- Put every monitor on a workspace of its own block. A monitor showing an empty
-- workspace from another block (Hyprland hands out 1, 2, ... before these rules
-- exist) moves to its block's first workspace. Right after login, a monitor on
-- an empty workspace of its own block moves to that block's first one too, so
-- each screen starts on its 1. A target another monitor is showing is skipped
-- this round: a monitor that must leave goes to a free workspace of its block
-- instead, and the next round finishes once the first one is free.
local login_monitor = nil
local function settle(at_login)
  local monitors = ordered_monitors()
  if overlapping(monitors) then
    log("settle: skipped, monitors overlap")
    return false
  end

  local focused = hl.get_active_monitor()
  local moved, blocked = false, false
  for index, monitor in ipairs(monitors) do
    local first = (index - 1) * block + 1
    local workspace = monitor.active_workspace
    local empty = workspace ~= nil and workspace.windows == 0
    local homeless = workspace ~= nil and not in_block(workspace.id, first)
    if empty and workspace.id ~= first and (homeless or at_login) then
      local target = first
      if visible_elsewhere(first, monitor) then
        blocked = true
        target = nil
        if homeless then
          for id = first + 1, first + block - 1 do
            if hl.get_workspace(tostring(id)) == nil then target = id break end
          end
        end
      end
      if target then
        hl.dispatch(hl.dsp.focus({ monitor = monitor.name }))
        hl.dispatch(hl.dsp.focus({ workspace = tostring(target) }))
        moved = true
      end
    end
  end
  -- After login, end on the monitor Hyprland started on rather than on one
  -- that connected later and grabbed focus.
  local home = focused and focused.name
  if at_login and login_monitor then home = login_monitor end
  if home and (moved or at_login) then hl.dispatch(hl.dsp.focus({ monitor = home })) end
  log(string.format("settle%s: moved=%s blocked=%s focus=%s", at_login and " (login)" or "", tostring(moved), tostring(blocked), tostring(home)))
  return blocked
end

-- Monitor events arrive in bursts while outputs connect and get placed, so
-- settle once things have been quiet for a moment, and retry while a move is
-- blocked by another monitor that still has to move.
local settle_timer = nil
local login_pending = false
local function schedule_settle(delay, retries)
  if settle_timer and settle_timer.set_enabled then settle_timer:set_enabled(false) end
  settle_timer = hl.timer(function()
    settle_timer = nil
    if settle(login_pending) and retries > 0 then
      schedule_settle(200, retries - 1)
    else
      login_pending = false
    end
  end, { type = "oneshot", timeout = delay })
end

local function on_monitors_changed()
  apply_rules()
  schedule_settle(400, 5)
end

apply_rules()
schedule_settle(400, 5)
hl.on("hyprland.start", function()
  login_pending = true
  -- The primary monitor: cursor.default_monitor when it is set, otherwise the
  -- one Hyprland started on (outputs that connect later take focus as they
  -- appear, which is how the secondary monitor ended up focused at login).
  local preferred = hl.get_config("cursor.default_monitor")
  local active = hl.get_active_monitor()
  login_monitor = (type(preferred) == "string" and preferred ~= "") and preferred or (active and active.name)
  log("hyprland.start")
  on_monitors_changed()
end)
hl.on("monitor.added", on_monitors_changed)
hl.on("monitor.removed", on_monitors_changed)
hl.on("monitor.layout_changed", on_monitors_changed)

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
