import { test } from "node:test"
import assert from "node:assert/strict"
import {
  addBox, duplicateBox, removeBox, reorderBox, resetBoxes, canRemove, canMove, applyStyle, styleKey,
} from "../../app/javascript/text_box_list.js"

const mk = (x, y, w = 0.5, h = 0.2) => ({ x, y, w, h, angle: 0, color: "white", font: "thick" })
const inside = (b) => b.x >= 0 && b.y >= 0 && b.x + b.w <= 1 + 1e-9 && b.y + b.h <= 1 + 1e-9

test("addBox appends a 0.7x0.2 white/thick box near the middle and selects it", () => {
  const { boxes, selected } = addBox([mk(0, 0)])
  assert.equal(boxes.length, 2)
  assert.equal(selected, 1)
  assert.deepEqual([boxes[1].w, boxes[1].h, boxes[1].color, boxes[1].font], [0.7, 0.2, "white", "thick"])
  assert.ok(Math.abs(boxes[1].x + 0.35 - 0.5) < 0.15 && Math.abs(boxes[1].y + 0.1 - 0.5) < 0.2)
})

test("addBox offsets each new box and always stays inside the image", () => {
  let boxes = []
  const seen = new Set()
  for (let i = 0; i < 30; i++) {
    boxes = addBox(boxes).boxes
    assert.ok(inside(boxes.at(-1)))
    if (i < 8) seen.add(`${boxes.at(-1).x},${boxes.at(-1).y}`)
  }
  assert.equal(seen.size, 8)
})

test("duplicateBox offsets +0.04 on both axes, inserts after the source and selects the copy", () => {
  const { boxes, selected } = duplicateBox([mk(0.1, 0.2), mk(0.3, 0.3)], 0)
  assert.equal(selected, 1)
  assert.equal(boxes.length, 3)
  assert.deepEqual([boxes[1].x, boxes[1].y], [0.14, 0.24])
  assert.deepEqual(boxes[2], mk(0.3, 0.3))
})

test("duplicateBox clamps at the image edge", () => {
  const { boxes } = duplicateBox([mk(0.5, 0.8)], 0)
  assert.deepEqual([boxes[1].x, boxes[1].y], [0.5, 0.8])
  const { boxes: b2 } = duplicateBox([mk(0.48, 0.79)], 0)
  assert.deepEqual([b2[1].x, b2[1].y], [0.5, 0.8])
})

test("duplicateBox copies by value", () => {
  const src = [mk(0.1, 0.1)]
  const { boxes } = duplicateBox(src, 0)
  boxes[1].color = "black"
  assert.equal(src[0].color, "white")
})

test("removeBox deletes the box and keeps a valid selection", () => {
  const list = [mk(0, 0), mk(0.1, 0.1), mk(0.2, 0.2)]
  assert.deepEqual(removeBox(list, 1), { boxes: [list[0], list[2]], selected: 1 })
  assert.equal(removeBox(list, 2).selected, 1)
})

test("removeBox never removes the last box", () => {
  const list = [mk(0, 0)]
  assert.deepEqual(removeBox(list, 0).boxes, list)
  assert.equal(canRemove(list), false)
  assert.equal(canRemove([...list, mk(0, 0)]), true)
})

test("reorderBox moves the box and the selection follows", () => {
  const [a, b, c] = [mk(0, 0), mk(0.1, 0.1), mk(0.2, 0.2)]
  assert.deepEqual(reorderBox([a, b, c], 1, -1), { boxes: [b, a, c], selected: 0 })
  assert.deepEqual(reorderBox([a, b, c], 1, 1), { boxes: [a, c, b], selected: 2 })
})

test("reorderBox is a no-op at the ends", () => {
  const list = [mk(0, 0), mk(0.1, 0.1)]
  assert.deepEqual(reorderBox(list, 0, -1), { boxes: list, selected: 0 })
  assert.deepEqual(reorderBox(list, 1, 1), { boxes: list, selected: 1 })
  assert.equal(canMove(list, 0, -1), false)
  assert.equal(canMove(list, 0, 1), true)
  assert.equal(canMove(list, null, 1), false)
})

test("resetBoxes gives exactly the two classic strips", () => {
  assert.deepEqual(resetBoxes().boxes, [
    { x: 0, y: 0, w: 1, h: 0.2, angle: 0, color: "white", font: "thick" },
    { x: 0, y: 0.8, w: 1, h: 0.2, angle: 0, color: "white", font: "thick" },
  ])
  resetBoxes().boxes[0].x = 5
  assert.equal(resetBoxes().boxes[0].x, 0)
})

test("applyStyle sets the matching color and font pair", () => {
  assert.deepEqual(applyStyle(mk(0, 0), "black"), { ...mk(0, 0), color: "black", font: "thin" })
  assert.equal(styleKey(applyStyle(mk(0, 0), "black")), "black")
  assert.equal(styleKey(mk(0, 0)), "white")
})
