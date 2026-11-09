import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Autosaver } from '../../app/javascript/autosaver.js'

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

test('debounces rapid edits into one save and reports Saved', async () => {
  const statuses = []
  let sends = 0
  const saver = new Autosaver({ send: async () => { sends++ }, onStatus: (s) => statuses.push(s), delay: 10 })
  saver.schedule(); saver.schedule(); saver.schedule()
  await wait(40)
  assert.equal(sends, 1)
  assert.equal(statuses.at(-1), 'saved')
})

test('serialises saves: an edit during a save is sent after it, never concurrently', async () => {
  let active = 0, maxActive = 0
  const sent = []
  let state = 'a'
  const saver = new Autosaver({
    delay: 5,
    send: async () => {
      active++; maxActive = Math.max(maxActive, active)
      sent.push(state)
      await wait(30)
      active--
    },
  })
  saver.schedule()
  await wait(15)
  state = 'b'
  saver.schedule()
  await wait(100)
  assert.equal(maxActive, 1)
  assert.deepEqual(sent, ['a', 'b'])
})

test('a failure reports error and retry sends again', async () => {
  const statuses = []
  let fail = true
  let sends = 0
  const saver = new Autosaver({
    delay: 5,
    onStatus: (s) => statuses.push(s),
    send: async () => { sends++; if (fail) throw new Error('nope') },
  })
  saver.schedule()
  await wait(30)
  assert.equal(statuses.at(-1), 'error')
  fail = false
  await saver.retry()
  assert.equal(sends, 2)
  assert.equal(statuses.at(-1), 'saved')
})
