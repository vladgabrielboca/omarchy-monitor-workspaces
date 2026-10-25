#!/usr/bin/env bash
# setup/teardown round trip in a sandboxed XDG config: idempotent setup, and a
# teardown that leaves the Hyprland config and bar layout as they started.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ID=vladgabrielboca.monitor-workspaces
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export XDG_CONFIG_HOME=$sandbox/config XDG_STATE_HOME=$sandbox/state
unset HYPRLAND_INSTANCE_SIGNATURE
mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/omarchy"
printf 'require("default.hypr.omarchy")\nrequire("hypr.bindings")\n' >"$XDG_CONFIG_HOME/hypr/hyprland.lua"
cat >"$XDG_CONFIG_HOME/omarchy/shell.json" <<'JSON'
{"bar": {"layout": {
  "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces", "custom": 1}, {"id": "x.after"}],
  "center": [{"id": "omarchy.clock"}],
  "centerEnd": [{"id": "omarchy.weather"}],
  "right": [{"id": "omarchy.tray"}]
}}}
JSON
cp "$XDG_CONFIG_HOME/hypr/hyprland.lua" "$sandbox/hypr.orig"
jq -S . "$XDG_CONFIG_HOME/omarchy/shell.json" >"$sandbox/shell.orig"

# Without a terminal to confirm on, or --yes, nothing may change.
if "$ROOT/setup" </dev/null >/dev/null 2>&1; then fail "setup ran without consent"; fi
cmp -s "$XDG_CONFIG_HOME/hypr/hyprland.lua" "$sandbox/hypr.orig" || fail "setup changed files without consent"

"$ROOT/setup" --yes >/dev/null
"$ROOT/setup" --yes >/dev/null
hypr=$XDG_CONFIG_HOME/hypr/hyprland.lua
layout=$(jq -c .bar.layout "$XDG_CONFIG_HOME/omarchy/shell.json")

[[ $(grep -c ">>> $ID >>>" "$hypr") == 1 ]] || fail "hook not added exactly once"
grep -qF "\"$ROOT/hypr/monitor-workspaces.lua\"" "$hypr" || fail "hook does not point at the plugin"
[[ $(jq -r '.left | map(.id) | join(",")' <<<"$layout") == "omarchy.menu,$ID,x.after" ]] ||
  fail "workspaces widget not in omarchy.workspaces' place: $layout"
[[ $(jq -r '.centerEnd | map(.id + ":" + (.display // "")) | join(",")' <<<"$layout") == "$ID:Monitor badge,omarchy.weather:" ]] ||
  fail "badge not first in centerEnd: $layout"

echo '{"hackerman":{"mode":"accent","hex":""}}' >"$XDG_STATE_HOME/$ID/highlight.json"
if "$ROOT/teardown" </dev/null >/dev/null 2>&1; then fail "teardown ran without consent"; fi
"$ROOT/teardown" --yes >/dev/null
cmp -s "$hypr" "$sandbox/hypr.orig" || fail "teardown left the Hyprland config changed"
jq -S . "$XDG_CONFIG_HOME/omarchy/shell.json" | cmp -s - "$sandbox/shell.orig" || fail "teardown left the bar layout changed"
[[ $(ls -A "$XDG_STATE_HOME/$ID") == highlight.json ]] || fail "teardown should keep only the highlight colours"
"$ROOT/setup" --yes >/dev/null && "$ROOT/teardown" --yes >/dev/null
rm "$XDG_STATE_HOME/$ID/highlight.json"
"$ROOT/setup" --yes >/dev/null && "$ROOT/teardown" --yes >/dev/null
[[ ! -e $XDG_STATE_HOME/$ID ]] || fail "teardown left state behind"
echo ok
