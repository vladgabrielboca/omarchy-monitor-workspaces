#!/usr/bin/env bash
# Runs Model.js helpers under node: monitor ordering, visible slots, labels,
# and markup stripping.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
node - "$ROOT/Model.js" <<'JS'
const fs = require("fs")
const src = fs.readFileSync(process.argv[2], "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { firstWorkspace, visibleIds, slotLabel, plain, parseBlocks, builtinFirst, normalizeHex, parseHighlights, highlightFor, withHighlight, themeTitle, hexToHsv, hsvToHex }")()
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
// Omarchy's block file, as its engine writes it.
const blocks = M.parseBlocks("0\tDP-1\tGIGA-BYTE M27Q3 0x01\n1\tDP-2\tASUS VG248 J9L\nbad line\nx\tHDMI-A-1\tY\n")
assert.deepStrictEqual(blocks, { "DP-1": 0, "DP-2": 1 })
assert.strictEqual(M.builtinFirst(blocks, "DP-2", 1), 11)
assert.strictEqual(M.builtinFirst(blocks, "DP-1", 3), 1)
// Before the file exists, the shown workspace decides.
assert.strictEqual(M.builtinFirst({}, "DP-1", 13), 11)
assert.strictEqual(M.builtinFirst({}, "DP-1", -1), 1)
// Highlight colour, per theme.
assert.strictEqual(M.normalizeHex("#ABC"), "#aabbcc")
assert.strictEqual(M.normalizeHex(" c38b7b "), "#c38b7b")
assert.strictEqual(M.normalizeHex("#12345"), "")
assert.strictEqual(M.normalizeHex("red"), "")
const saved = M.parseHighlights('{"hackerman":{"mode":"custom","hex":"#ff8800"},"catppuccin":{"mode":"accent","hex":""},"bad":{"mode":"neon"},"nohex":{"mode":"custom"},"list":[]}')
assert.deepStrictEqual(saved, { hackerman: { mode: "custom", hex: "#ff8800" }, catppuccin: { mode: "accent", hex: "" } })
assert.deepStrictEqual(M.parseHighlights("not json"), {})
assert.deepStrictEqual(M.parseHighlights("[1]"), {})
assert.deepStrictEqual(M.highlightFor(saved, "last-horizon"), { mode: "accent", hex: "" })
// A preset keeps the theme's custom colour; other themes are untouched.
let next = M.withHighlight(saved, "hackerman", "alert")
assert.deepStrictEqual(next.hackerman, { mode: "alert", hex: "#ff8800" })
assert.deepStrictEqual(saved.hackerman, { mode: "custom", hex: "#ff8800" })
next = M.withHighlight(next, "last-horizon", "custom", "C38B7B")
assert.deepStrictEqual(next["last-horizon"], { mode: "custom", hex: "#c38b7b" })
assert.deepStrictEqual(next.catppuccin, { mode: "accent", hex: "" })
assert.deepStrictEqual(M.withHighlight(next, "x", "custom", "nope"), next)
assert.strictEqual(M.withHighlight(next, "hackerman", null).hackerman, undefined)
assert.strictEqual(M.themeTitle("catppuccin-latte"), "Catppuccin Latte")
for (const hex of ["#000000", "#ffffff", "#c38b7b", "#89b4fa", "#50f872", "#ff0000", "#00ff7f"])
  assert.strictEqual(M.hsvToHex(...Object.values(M.hexToHsv(hex))), hex)
assert.deepStrictEqual(M.hexToHsv("#ff0000"), { h: 0, s: 1, v: 1 })
assert.strictEqual(M.hsvToHex(1, 1, 1), "#ff0000")
console.log("ok")
JS
