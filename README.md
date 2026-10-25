# Monitor Workspaces for Omarchy

Per-monitor workspaces for multi-monitor Omarchy setups. Every monitor gets its
own workspaces 1–9, 0, `Super + number` acts on the monitor you're on, a small
icon in the middle of the bar tells you which monitor has focus, and one chord
sends a window to any workspace on the other monitor.

![Both monitors' bars: each shows its own workspaces 1-5, the main monitor has a parked window on 7, and the monitor icon is lit on the focused one](preview.png)

## Why

With stock Hyprland, workspaces are global: `Super + 3` might be on either
screen, both bars show the same numbers, and it's easy to lose track of which
monitor you're on or about to send a window to. This plugin makes each monitor
self-contained and always tells you where you are:

- **Each monitor owns its own workspaces.** Hyprland numbers workspaces
  globally, so each monitor owns a block of ten real workspaces (1–10, 11–20,
  …). Every bar shows its own block as **1–9, 0**.
- **`Super + 1…0` acts on the focused monitor.** Press `Super + 2` on your left
  monitor and you get the left monitor's 2; on the main monitor, the main
  monitor's 2.
- **You can see which monitor has focus.** A monitor icon next to the clock
  lights up on the focused monitor's bar, and only the focused monitor's
  current workspace number is coloured.
- **`Super + Tab` jumps between monitors**, so you never need the mouse to
  change which monitor you're on.
- **Send a window to any workspace on the other monitor** in one chord:
  `Super + Ctrl + Shift + 3` puts it on the other monitor's 3, and you follow
  it there.
- **Slots 1–5 are always shown; 6–0 appear only while they exist**, so you can
  park a window on 6 without cluttering the bar.

![After Super+Tab: the left monitor's icon and workspace light up, and the main monitor's dim](screenshots/focus-switch.png)

## Works with Omarchy's built-in per-monitor workspaces

Omarchy's development channel now has per-monitor workspaces built in
(`default/hypr/monitor-workspaces.lua`), and they will reach stable in a later
release. The plugin detects which Omarchy you run and adapts, so nothing needs
reinstalling when you upgrade:

| | Omarchy with built-in per-monitor workspaces | Omarchy without it |
|---|---|---|
| Blocks and `Super + 1…0` | Omarchy's: each block follows the physical monitor (make, model, serial) | The plugin's: monitors ordered left to right |
| Unplugging a monitor | Omarchy folds its workspaces into another screen and restores them when it returns | Its windows stay on another screen, shown as `(2)` |
| Focus badge, coloured current workspace | Plugin | Plugin |
| `Super + Tab`, `Super + Shift + Tab` | Plugin (Omarchy uses them for next/previous workspace) | Plugin |
| `Super + Ctrl + Shift + 1…0` | Plugin, built on Omarchy's workspace API | Plugin |

## Keys

| Keys | Action |
|---|---|
| `Super + 1…9, 0` | Switch to that workspace on the focused monitor |
| `Super + Shift + 1…9, 0` | Move the window to that workspace on the focused monitor |
| `Super + Shift + Alt + 1…9, 0` | Move the window there without following it |
| `Super + Ctrl + Shift + 1…9, 0` | Move the window to that workspace on the **other** monitor, and follow it |
| `Super + Tab` | Focus the next monitor |
| `Super + Shift + Tab` | Move the window to the next monitor |

With Omarchy's built-in per-monitor workspaces, the first three rows are
Omarchy's own keys, which work the same way. Teardown restores Omarchy's
`Super + Tab` and `Super + Shift + Tab`, and, on an Omarchy without the
built-in, its global `Super + 1…0`.

Clicking a workspace number switches to it; clicking the badge opens the
highlight colour menu (see below). After login, focus returns to your primary monitor (Hyprland's
`cursor.default_monitor`, or the monitor that came up first).

## Highlight colour

The badge and the focused monitor's current workspace are lit with one colour,
chosen **per theme**: click the badge to open the menu.

- **Accent** (the default): the theme's accent colour.
- **Alert**: the colour the bar uses for alerts (recording, updates). This
  was the only colour before 2.1.0.
- **Border**: the focused window's border colour.
- **Plain**: no colour; the unfocused monitor's bar is dimmed instead.
- **Custom**: drag in the picker or type a hex colour.

Each theme remembers its own choice, so a colour picked for one theme never
carries over to another; a theme you haven't set uses Accent. The choices are
kept in `~/.local/state/vladgabrielboca.monitor-workspaces/highlight.json`,
which `teardown` leaves in place.

## Install

```bash
omarchy plugin add https://github.com/vladgabrielboca/omarchy-monitor-workspaces.git --yes && ~/.config/omarchy/plugins/vladgabrielboca.monitor-workspaces/setup
```

`omarchy plugin add` fetches the plugin. `setup` then lists the changes below
and asks before making them (pass `--yes` to skip the question):

1. adds a small, clearly marked hook to the end of `~/.config/hypr/hyprland.lua`
   that loads the plugin's [`hypr/monitor-workspaces.lua`](hypr/monitor-workspaces.lua)
   (its keybindings, and its workspace engine on an Omarchy without the
   built-in one), and reloads Hyprland;
2. puts the workspace numbers where `omarchy.workspaces` was (or right after
   the Omarchy menu) and the monitor badge just right of the clock.

Both files are backed up with a `.bak.<timestamp>` suffix first, and `setup` is
safe to run again.

> `omarchy plugin add --enable` on its own only places the bar widget. The
> keybindings need `setup`, so use the command above.

## Disable

Turn it off but keep it installed: this removes the plugin's keys and widgets
and puts `omarchy.workspaces` back exactly where it was.

```bash
~/.config/omarchy/plugins/vladgabrielboca.monitor-workspaces/teardown
```

Turn it back on with `setup`:

```bash
~/.config/omarchy/plugins/vladgabrielboca.monitor-workspaces/setup
```

> `omarchy plugin disable` only hides the bar widget and leaves the plugin's
> keybindings active, so use `teardown` to switch it off fully.

## Remove

```bash
~/.config/omarchy/plugins/vladgabrielboca.monitor-workspaces/teardown && omarchy plugin remove vladgabrielboca.monitor-workspaces --yes
```

## Update

```bash
omarchy plugin update vladgabrielboca.monitor-workspaces --yes && hyprctl reload && omarchy restart shell
```

The keybindings update along with the plugin, since Hyprland loads them
straight from the plugin directory; `hyprctl reload` applies them, and
restarting the shell makes sure the widget's logic file is reloaded.

## Customising

- **Bar placement:** drag the widgets on the bar, or use `omarchy bar move`.
  Both are instances of `vladgabrielboca.monitor-workspaces`; the badge is the
  one with `"display": "Monitor badge"` in `~/.config/omarchy/shell.json`.
- **Primary monitor after login:** set Hyprland's `cursor.default_monitor`.

## Known limitations

- **Workspace numbers in your own window rules** (for example
  `o.window("qemu", { workspace = "5" })`) refer to real workspaces, so `5` is
  the first block's 5. Use the real number for another monitor's workspace:
  `15` for the second block's 5. Omarchy lists its blocks in
  `~/.local/state/omarchy/monitor-workspaces`.
- **With three or more monitors**, `Super + Tab` and `Super + Ctrl + Shift +
  number` go to the next monitor to the right, wrapping around.
- **Without Omarchy's built-in engine:** an unplugged monitor's windows show
  on another bar in parentheses, such as `(2)`; click one to open it, or plug
  the monitor back in to return them. After `teardown`, windows on workspaces
  11 and up are off Omarchy's bar and number keys; move them to 1–10 first.

## Troubleshooting

At load and each time monitors change (including at login), the plugin notes
what it saw and did in `$XDG_RUNTIME_DIR/monitor-workspaces.log`, which starts
empty after every boot and stays under 64 KiB. The first line says which engine
is in use. Include it when reporting a problem:

```bash
cat "$XDG_RUNTIME_DIR/monitor-workspaces.log"
```

## Requirements

- Omarchy with shell plugin support and the Lua Hyprland config
  (`~/.config/hypr/hyprland.lua`; Hyprland 0.56+)
- `jq` (included with Omarchy)

## Tests

```bash
tests/model-test.sh   # block lookup, visible slots, labels, per-theme highlight colours (needs node)
tests/lua-test.sh     # both engines' keys and rules against a stand-in Hyprland API (needs lua)
tests/setup-test.sh   # setup/teardown round trip in a sandboxed config
```

## License

MIT
