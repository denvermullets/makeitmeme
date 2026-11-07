import test from 'node:test'
import assert from 'node:assert/strict'
import { canvasSize, fitText, boxGeometry } from '../../app/javascript/meme_render.js'

// A fake font: every glyph is half the font size wide.
const measure = (text, size) => text.length * size * 0.5

test('canvasSize keeps small images and scales big ones down to 2048 on the long side', () => {
  assert.deepEqual(canvasSize(500, 400), { width: 500, height: 400 })
  assert.deepEqual(canvasSize(4096, 2048), { width: 2048, height: 1024 })
})

test('boxGeometry turns fractions into pixels about the box centre', () => {
  const g = boxGeometry({ x: 0.1, y: 0.2, w: 0.5, h: 0.25, angle: 90 }, 1000, 800)
  assert.deepEqual(g, { cx: 350, cy: 260, w: 500, h: 200, radians: Math.PI / 2 })
})

test('fitText takes the largest size where one line fits the box (height-limited)', () => {
  // "AB CD" is 5 glyphs: at size 36 one line is 90 wide (<=100) and 36*1.1=39.6 tall (<=40); 37 is too tall.
  const { size, lines } = fitText(measure, 'AB CD', 100, 40, false)
  assert.equal(size, 36)
  assert.deepEqual(lines, ['AB CD'])
})

test('fitText wraps greedily when a line is too wide', () => {
  // size 20: "AAAA BBBB" is 90 wide, fits one line. Taller box, narrower width forces a wrap.
  const { size, lines } = fitText(measure, 'AAAA BBBB', 50, 100, false)
  assert.deepEqual(lines, ['AAAA', 'BBBB'])
  assert.ok(lines.every((l) => measure(l, size) <= 50))
  assert.ok(lines.length * size * 1.1 <= 100)
  assert.equal(size, 25) // 4 glyphs * 12.5 = 50 wide; 2 lines * 27.5 = 55 tall
})

test('fitText floors at the minimum size for a long unbroken word', () => {
  assert.equal(fitText(measure, 'X'.repeat(200), 100, 30, false).size, 8)
})

test('stroked text leaves padding so it fits a little smaller', () => {
  assert.ok(fitText(measure, 'AB CD', 100, 40, true).size < fitText(measure, 'AB CD', 100, 40, false).size)
})
