#!/usr/bin/env bash
# Runs Model.js helpers under node: monitor ordering, visible slots, labels,
# and markup stripping.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
node - "$ROOT/Model.js" <<'JS'
const fs = require("fs")
const src = fs.readFileSync(process.argv[2], "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { firstWorkspace, visibleIds, slotLabel, plain }")()
const assert = require("assert")
const monitors = [
  { name: "DP-1", x: 1920, y: -140 },
  { name: "DP-2", x: 0, y: 0 },
  { name: "HDMI-A-1", x: 4480, y: 0 },
  { name: "MIRROR", x: -5000, y: 0, mirror: true },
]
assert.strictEqual(M.firstWorkspace(monitors, "DP-2"), 1)
assert.strictEqual(M.firstWorkspace(monitors, "DP-1"), 11)
assert.strictEqual(M.firstWorkspace(monitors, "HDMI-A-1"), 21)
assert.strictEqual(M.firstWorkspace(monitors, "unknown"), 1)
assert.deepStrictEqual(M.visibleIds(11, [1, 12, 18, 20, 21]), [11, 12, 13, 14, 15, 18, 20])
// A workspace left over from an unplugged monitor is shown after the block.
assert.deepStrictEqual(M.visibleIds(11, [1, 11, 22], [11, 22, -98]), [11, 12, 13, 14, 15, 22])
assert.strictEqual(M.slotLabel(11, 22), "(2)")
assert.strictEqual(M.slotLabel(1, 30), "(0)")
assert.strictEqual(M.slotLabel(11, 12), "2")
assert.strictEqual(M.slotLabel(11, 20), "0")
assert.strictEqual(M.slotLabel(11, 3), "(3)")
assert.strictEqual(M.plain('<img src="https://example.invalid/x">DP-1'), "img src=https://example.invalid/xDP-1")
console.log("ok")
JS
