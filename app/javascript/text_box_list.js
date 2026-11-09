// Pure list operations for the Text Box editor. Each takes the ordered boxes (and a selected index where relevant)
// and returns a new `{ boxes, selected }`; nothing is mutated. Results always satisfy TextBoxes.check on the server.
export const DUPLICATE_OFFSET = 0.04
export const NEW_BOX = { w: 0.7, h: 0.2 }
export const ADD_STAGGER = 0.03
export const STYLE_PAIRS = {
  white: { color: "white", font: "thick" },
  black: { color: "black", font: "thin" },
}
export const CLASSIC_STRIPS = [
  { x: 0, y: 0, w: 1, h: 0.2, angle: 0, color: "white", font: "thick" },
  { x: 0, y: 0.8, w: 1, h: 0.2, angle: 0, color: "white", font: "thick" },
]

const r3 = (v) => Math.round(v * 1000) / 1000
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))
const inRange = (list, index) => Number.isInteger(index) && index >= 0 && index < list.length

// New 0.7 x 0.2 box near the middle, shifted a little per existing box (cycling every 8) and kept inside the image.
export function addBox(boxes) {
  const { w, h } = NEW_BOX
  const step = boxes.length % 8
  const x = clamp(r3((1 - w) / 2 + (step - 3.5) * ADD_STAGGER), 0, r3(1 - w))
  const y = clamp(r3((1 - h) / 2 + step * ADD_STAGGER), 0, r3(1 - h))
  const next = [...boxes, { x, y, w, h, angle: 0, ...STYLE_PAIRS.white }]
  return { boxes: next, selected: next.length - 1 }
}

// Copy of the box at `index`, offset +0.04 on both axes (clamped inside the image), inserted after it and selected.
export function duplicateBox(boxes, index) {
  if (!inRange(boxes, index)) return { boxes, selected: null }
  const source = boxes[index]
  const copy = {
    ...source,
    x: clamp(r3(source.x + DUPLICATE_OFFSET), 0, r3(1 - source.w)),
    y: clamp(r3(source.y + DUPLICATE_OFFSET), 0, r3(1 - source.h)),
  }
  const next = [...boxes.slice(0, index + 1), copy, ...boxes.slice(index + 1)]
  return { boxes: next, selected: index + 1 }
}

// Removes the box at `index`, but never the last one. Selection moves to the box now at that spot (or the new last).
export function removeBox(boxes, index) {
  if (boxes.length <= 1 || !inRange(boxes, index)) return { boxes, selected: inRange(boxes, index) ? index : null }
  const next = boxes.filter((_, i) => i !== index)
  return { boxes: next, selected: Math.min(index, next.length - 1) }
}

// Moves the box at `index` by `delta` places (-1 earlier, +1 later); the selection follows it. No-op at the ends.
export function reorderBox(boxes, index, delta) {
  const target = index + delta
  if (!inRange(boxes, index) || !inRange(boxes, target)) return { boxes, selected: inRange(boxes, index) ? index : null }
  const next = [...boxes]
  const [moved] = next.splice(index, 1)
  next.splice(target, 0, moved)
  return { boxes: next, selected: target }
}

// The two classic strips, top and bottom.
export function resetBoxes() {
  return { boxes: CLASSIC_STRIPS.map((box) => ({ ...box })), selected: null }
}

export const canRemove = (boxes) => boxes.length > 1
export const canMove = (boxes, index, delta) => inRange(boxes, index) && inRange(boxes, index + delta)

export const styleKey = (box) => (box.color === "black" ? "black" : "white")
export const applyStyle = (box, key) => ({ ...box, ...(STYLE_PAIRS[key] || STYLE_PAIRS.white) })
