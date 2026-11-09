import { test } from "node:test"
import assert from "node:assert/strict"
import { LEVELS, sampleCaptions, fitSummary } from "../../app/javascript/sample_preview.js"

test("off gives empty captions for every box", () => {
  assert.deepEqual(sampleCaptions("off", 2), ["", ""])
})

test("short numbers the boxes, medium and long repeat one sentence", () => {
  assert.deepEqual(sampleCaptions("short", 2), ["BOX 1", "BOX 2"])
  assert.equal(new Set(sampleCaptions("medium", 3)).size, 1)
  assert.ok(sampleCaptions("long", 1)[0].length > sampleCaptions("medium", 1)[0].length)
})

test("unknown level behaves as off; levels are the four switch positions", () => {
  assert.deepEqual(sampleCaptions("bogus", 1), [""])
  assert.deepEqual(LEVELS, ["off", "short", "medium", "long"])
})

test("fitSummary shows the size and warns only at the minimum while overflowing", () => {
  assert.deepEqual(fitSummary(null), { text: "", warning: false })
  assert.deepEqual(fitSummary({ size: 40, overflow: false, atMinimum: false }), { text: "40px", warning: false })
  assert.deepEqual(fitSummary({ size: 8, overflow: false, atMinimum: true }), { text: "8px", warning: false })
  assert.deepEqual(fitSummary({ size: 8, overflow: true, atMinimum: true }), { text: "8px, overflows", warning: true })
})
