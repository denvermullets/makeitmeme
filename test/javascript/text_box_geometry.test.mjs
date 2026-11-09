import { test } from "node:test"
import assert from "node:assert/strict"
import {
  MIN_PX, normAngle, toPx, fromPx, clampBox, moveBox, resizeBox, rotationAngle, rotateBox, dragBox,
} from "../../app/javascript/text_box_geometry.js"

const W = 400, H = 300
const box = { x: 0.25, y: 0.25, w: 0.5, h: 0.2, angle: 0 }
const close = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} !~ ${b}`)

test("normAngle maps onto (-180, 180]", () => {
  assert.equal(normAngle(190), -170)
  assert.equal(normAngle(-190), 170)
  assert.equal(normAngle(-180), 180)
  assert.equal(normAngle(360), 0)
})

test("toPx and fromPx round trip", () => {
  assert.deepEqual(fromPx(toPx(box, W, H), W, H), box)
})

test("fromPx never lets x + w or y + h exceed 1 after rounding", () => {
  const out = fromPx({ cx: 0.7504 * W, cy: 150, w: 0.5004 * W, h: 30, a: 0 }, W, H)
  assert.ok(out.x + out.w <= 1 + 1e-9)
  assert.ok(out.x >= 0 && out.y >= 0)
})

test("clampBox enforces minimum size, image size and keeps the box inside", () => {
  const tiny = clampBox({ cx: 5, cy: 5, w: 1, h: 1, a: 0 }, W, H)
  assert.equal(tiny.w, MIN_PX)
  assert.equal(tiny.cx, MIN_PX / 2)
  const huge = clampBox({ cx: 900, cy: -50, w: 900, h: 20, a: 0 }, W, H)
  assert.equal(huge.w, W)
  assert.equal(huge.cx, W / 2)
  assert.equal(huge.cy, 10)
})

test("moveBox shifts and clamps", () => {
  const moved = moveBox(toPx(box, W, H), 10, -5, W, H)
  close(moved.cx, toPx(box, W, H).cx + 10)
  const stuck = moveBox(toPx(box, W, H), 9999, 9999, W, H)
  close(stuck.cx + stuck.w / 2, W)
  close(stuck.cy + stuck.h / 2, H)
})

test("resizeBox from the east handle keeps the west edge fixed", () => {
  const b0 = toPx(box, W, H)
  const b = resizeBox(b0, "e", 20, 0, W, H)
  close(b.w, b0.w + 20)
  close(b.cx - b.w / 2, b0.cx - b0.w / 2)
  assert.equal(b.h, b0.h)
})

test("resizeBox from the north-west handle keeps the south-east corner fixed", () => {
  const b0 = toPx(box, W, H)
  const b = resizeBox(b0, "nw", -30, -10, W, H)
  close(b.w, b0.w + 30)
  close(b.h, b0.h + 10)
  close(b.cx + b.w / 2, b0.cx + b0.w / 2)
  close(b.cy + b.h / 2, b0.cy + b0.h / 2)
})

test("resizeBox never goes below the minimum size", () => {
  const b = resizeBox(toPx(box, W, H), "w", 9999, 0, W, H)
  assert.equal(b.w, MIN_PX)
})

test("resizeBox on a rotated box works in the box's own axes", () => {
  const b0 = { ...toPx(box, W, H), a: 90 }
  // Rotated 90 degrees, the box's local x axis points down the screen.
  const b = resizeBox(b0, "e", 0, 20, W, H)
  close(b.w, b0.w + 20)
  close(b.cy, b0.cy + 10)
  close(b.cx, b0.cx)
})

test("rotation: straight above the centre is 0, to the right is 90", () => {
  const b = toPx(box, W, H)
  close(rotationAngle(b, { x: b.cx, y: b.cy - 50 }), 0)
  close(rotationAngle(b, { x: b.cx + 50, y: b.cy }), 90)
})

test("rotation snaps near-flat angles to 0 and shift snaps to 15", () => {
  const b = toPx(box, W, H)
  const at = (deg) => ({ x: b.cx + 100 * Math.sin((deg * Math.PI) / 180), y: b.cy - 100 * Math.cos((deg * Math.PI) / 180) })
  assert.equal(rotationAngle(b, at(3)), 0)
  assert.equal(rotationAngle(b, at(-3.5)), 0)
  close(rotationAngle(b, at(5)), 5)
  assert.equal(rotationAngle(b, at(38), true), 45)
  assert.equal(rotationAngle(b, at(-38), true), -45)
})

test("rotateBox and dragBox dispatch", () => {
  const b0 = toPx(box, W, H)
  close(rotateBox(b0, { x: b0.cx + 50, y: b0.cy }).a, 90)
  close(dragBox({ mode: "rotate", b0, point: { x: b0.cx + 50, y: b0.cy }, W, H }).a, 90)
  close(dragBox({ mode: "move", b0, dx: 5, dy: 0, W, H }).cx, b0.cx + 5)
  close(dragBox({ mode: "resize", handle: "e", b0, dx: 5, dy: 0, W, H }).w, b0.w + 5)
  assert.equal(dragBox({ mode: "nope", b0, W, H }), b0)
})

test("any drag output converts to fractions the server accepts", () => {
  for (const mode of ["move", "resize"]) {
    for (const handle of ["nw", "n", "ne", "e", "se", "s", "sw", "w"]) {
      for (const [dx, dy] of [[9999, 9999], [-9999, -9999], [3, -7]]) {
        const out = fromPx(dragBox({ mode, handle, b0: { ...toPx(box, W, H), a: 33 }, dx, dy, W, H }), W, H)
        assert.ok(out.x >= 0 && out.y >= 0 && out.w > 0 && out.h > 0, JSON.stringify(out))
        assert.ok(out.x + out.w <= 1 + 1e-6 && out.y + out.h <= 1 + 1e-6, JSON.stringify(out))
      }
    }
  }
})
