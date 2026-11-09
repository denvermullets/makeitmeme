// Pure geometry for the Text Box editor stage. Works in stage pixels with centre-based boxes
// ({cx, cy, w, h, a}) while dragging; `fromPx` turns that back into the stored shape (0-1 fractions, x/y = top left).
// Every result passes through `clampBox`, so no drag can produce geometry TextBoxes.check on the server would reject.
export const MIN_PX = 12
export const SNAP_STEP = 15
export const SNAP_ZERO = 4

export const HANDLE_DIRS = {
  nw: [-1, -1], n: [0, -1], ne: [1, -1], e: [1, 0], se: [1, 1], s: [0, 1], sw: [-1, 1], w: [-1, 0],
}

const r3 = (v) => Math.round(v * 1000) / 1000
const r1 = (v) => Math.round(v * 10) / 10

// Maps any angle onto (-180, 180].
export const normAngle = (a) => {
  const wrapped = ((((a + 180) % 360) + 360) % 360) - 180
  return wrapped <= -180 ? 180 : wrapped
}

export const toPx = (b, W, H) => ({ cx: (b.x + b.w / 2) * W, cy: (b.y + b.h / 2) * H, w: b.w * W, h: b.h * H, a: b.angle })

// Stored fractions. x/y are pulled back so that x + w and y + h never exceed 1 after rounding.
export const fromPx = (p, W, H) => {
  const w = Math.min(r3(p.w / W), 1)
  const h = Math.min(r3(p.h / H), 1)
  const x = Math.max(0, Math.min(r3((p.cx - p.w / 2) / W), r3(1 - w)))
  const y = Math.max(0, Math.min(r3((p.cy - p.h / 2) / H), r3(1 - h)))
  return { x, y, w, h, angle: r1(p.a) }
}

// Minimum size, never bigger than the image, and the whole (unrotated) rectangle stays inside the image.
export const clampBox = (b, W, H) => {
  const w = Math.min(Math.max(b.w, Math.min(MIN_PX, W)), W)
  const h = Math.min(Math.max(b.h, Math.min(MIN_PX, H)), H)
  const cx = Math.min(Math.max(b.cx, w / 2), W - w / 2)
  const cy = Math.min(Math.max(b.cy, h / 2), H - h / 2)
  return { ...b, w, h, cx, cy }
}

export const moveBox = (b0, dx, dy, W, H) => clampBox({ ...b0, cx: b0.cx + dx, cy: b0.cy + dy }, W, H)

// Drag one handle by (dx, dy) in stage pixels. The opposite edge/corner stays put, in the box's rotated frame.
export const resizeBox = (b0, handle, dx, dy, W, H) => {
  const [sx, sy] = HANDLE_DIRS[handle]
  const rad = (b0.a * Math.PI) / 180, c = Math.cos(rad), s = Math.sin(rad)
  const lx = dx * c + dy * s, ly = -dx * s + dy * c
  const b = { ...b0 }
  if (sx) b.w = Math.max(MIN_PX, b0.w + sx * lx)
  if (sy) b.h = Math.max(MIN_PX, b0.h + sy * ly)
  const ux = (sx * (b.w - b0.w)) / 2, uy = (sy * (b.h - b0.h)) / 2
  b.cx += ux * c - uy * s
  b.cy += ux * s + uy * c
  return clampBox(b, W, H)
}

// Angle from the box centre to the pointer (knob sits above the box, so 0 = straight up).
// Shift snaps to 15 degrees; otherwise angles within ~4 degrees of flat snap to 0.
export const rotationAngle = (b, point, shift = false) => {
  let a = normAngle((Math.atan2(point.y - b.cy, point.x - b.cx) * 180) / Math.PI + 90)
  if (shift) a = Math.round(a / SNAP_STEP) * SNAP_STEP
  else if (Math.abs(a) < SNAP_ZERO) a = 0
  return normAngle(a)
}

export const rotateBox = (b0, point, shift = false) => ({ ...b0, a: rotationAngle(b0, point, shift) })

// One entry point for the controller: mode is "move", "resize" (needs handle) or "rotate" (needs point).
export const dragBox = ({ mode, handle, b0, dx, dy, point, shift, W, H }) => {
  if (mode === "move") return moveBox(b0, dx, dy, W, H)
  if (mode === "resize") return resizeBox(b0, handle, dx, dy, W, H)
  if (mode === "rotate") return rotateBox(b0, point, shift)
  return b0
}
