import { test } from 'node:test'
import assert from 'node:assert/strict'
import { revealSchedule, STEP_MS, LEAD_IN_MS, MAX_TOTAL_MS } from '../../app/javascript/reveal_schedule.js'

const FINISHED = '2026-11-09T20:00:00.000Z'
const t0 = Date.parse(FINISHED)
const at = (ms) => new Date(t0 + ms).toISOString()
const run = (ms, places) => revealSchedule({ finishedAt: FINISHED, serverNow: at(ms), places })

test('at the finished time the last place is due and nothing earlier is showing', () => {
  const r = run(0, [3, 2, 1])
  assert.deepEqual(r.showing, [3])
  assert.equal(r.nextAt, at(STEP_MS))
})

test('before the finished time nothing is showing and the first step is due at it', () => {
  const r = run(-500, [3, 2, 1])
  assert.deepEqual(r.showing, [])
  assert.equal(r.nextAt, at(0))
})

test('tied places are one step: the places list already holds each place once', () => {
  // three Players tied for 2nd and one 1st is just places [2, 1]
  assert.deepEqual(run(0, [2, 1]).showing, [2])
  assert.deepEqual(run(STEP_MS - 1, [2, 1]).showing, [2])
})

test('the step before first place is longer than the others', () => {
  const r = run(STEP_MS, [4, 3, 2, 1]) // 4 and 3 showing, 2 is next
  assert.deepEqual(r.showing, [4, 3])
  assert.equal(r.nextAt, at(2 * STEP_MS))
  const r2 = run(2 * STEP_MS, [4, 3, 2, 1]) // 2 showing, first place is next after the lead-in
  assert.deepEqual(r2.showing, [4, 3, 2])
  assert.equal(r2.nextAt, at(2 * STEP_MS + LEAD_IN_MS))
  assert.ok(LEAD_IN_MS > STEP_MS)
})

test('the total length stays under the cap with many Players', () => {
  const places = Array.from({ length: 200 }, (_, i) => 200 - i)
  const end = run(MAX_TOTAL_MS, places)
  assert.deepEqual(end.showing, places)
  assert.equal(end.nextAt, null)
  const justBefore = run(MAX_TOTAL_MS - 1, places)
  assert.equal(justBefore.showing.length, 199)
  assert.equal(justBefore.nextAt, at(MAX_TOTAL_MS))
})

test('a server time mid-schedule returns exactly the places due by then', () => {
  const r = run(2 * STEP_MS + 10, [5, 4, 3, 2, 1])
  assert.deepEqual(r.showing, [5, 4, 3])
  assert.equal(r.nextAt, at(3 * STEP_MS))
})

test('a server time past the end returns every place and no next step', () => {
  const r = run(10 * 60 * 1000, [3, 2, 1])
  assert.deepEqual(r.showing, [3, 2, 1])
  assert.equal(r.nextAt, null)
})

test('a single place is shown at the finished time with no next step', () => {
  const r = run(0, [1])
  assert.deepEqual(r.showing, [1])
  assert.equal(r.nextAt, null)
})

test('an empty list has nothing to show and no next step', () => {
  const r = run(0, [])
  assert.deepEqual(r.showing, [])
  assert.equal(r.nextAt, null)
})

test('the result depends only on finishedAt and serverNow, not the device clock', () => {
  const realNow = Date.now
  try {
    Date.now = () => 0
    const a = run(STEP_MS, [3, 2, 1])
    Date.now = () => 9e15
    const b = run(STEP_MS, [3, 2, 1])
    assert.deepEqual(a, b)
  } finally {
    Date.now = realNow
  }
})
