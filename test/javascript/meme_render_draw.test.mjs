import test from 'node:test'
import assert from 'node:assert/strict'
import { render } from '../../app/javascript/meme_render.js'

// A recording fake 2d context: every glyph is half the font size wide.
function fakeCtx() {
  const calls = []
  const ctx = {
    calls,
    font: '',
    measureText: (s) => ({ width: s.length * parseInt(ctx.font, 10) * 0.5 }),
    drawImage: (...a) => calls.push(['drawImage', ...a]),
    fillText: (s) => calls.push(['fillText', s]),
    strokeText: (s) => calls.push(['strokeText', s]),
    strokeRect: () => calls.push(['strokeRect']),
    save() {}, restore() {}, translate() {}, rotate() {}, setLineDash() {}
  }
  return ctx
}
const template = { image: {}, width: 400, height: 200 }
const box = { x: 0, y: 0, w: 0.5, h: 0.5, angle: 0, color: 'white', font: 'thick' }

test('render draws the image, then each caption upper-cased, and reports the fit per box', () => {
  const ctx = fakeCtx()
  const fits = render(ctx, template, [box, box], ['hi', ''])
  assert.equal(ctx.calls[0][0], 'drawImage')
  assert.deepEqual(ctx.calls.filter((c) => c[0] === 'fillText').map((c) => c[1]), ['HI'])
  assert.equal(fits.length, 2)
  assert.equal(typeof fits[0].size, 'number')
  assert.equal(fits[0].overflow, false)
  assert.equal(fits[0].atMinimum, false)
  assert.equal(fits[1], null) // empty caption: nothing fitted
})

test('render flags a box whose text hits the minimum size and overflows', () => {
  const fits = render(fakeCtx(), template, [box], ['X'.repeat(200)])
  assert.equal(fits[0].size, 8)
  assert.equal(fits[0].atMinimum, true)
  assert.equal(fits[0].overflow, true)
})

test('render draws numbered guides on empty boxes only when outlines is set', () => {
  const on = fakeCtx()
  render(on, template, [box], [''], { outlines: true })
  const off = fakeCtx()
  render(off, template, [box], [''])
  assert.equal(on.calls.filter((c) => c[0] === 'strokeRect').length, 1)
  assert.equal(off.calls.filter((c) => c[0] === 'strokeRect').length, 0)
})
