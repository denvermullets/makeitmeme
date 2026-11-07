import test from 'node:test'
import assert from 'node:assert/strict'
import { msUntilZero, submissionBody, failureMessage } from '../../app/javascript/meme_submit.js'

test('msUntilZero corrects for the gap between the server clock and the device clock', () => {
  const serverNow = '2026-11-08T10:00:00.000Z'
  const deadline = '2026-11-08T10:01:30.000Z'
  // The device is 5s ahead of the server and 2s have passed since the page was built.
  const deviceAtConnect = Date.parse(serverNow) + 5000
  assert.equal(msUntilZero(deadline, serverNow, deviceAtConnect, deviceAtConnect + 2000), 88000)
})

test('msUntilZero never goes negative and is null without a deadline', () => {
  const serverNow = '2026-11-08T10:00:00.000Z'
  const deviceNow = Date.parse(serverNow)
  assert.equal(msUntilZero('2026-11-08T09:59:00.000Z', serverNow, deviceNow, deviceNow), 0)
  assert.equal(msUntilZero('', serverNow, deviceNow, deviceNow), null)
})

test('submissionBody sends the blob, the Template and one caption per Text Box (blank allowed)', () => {
  assert.deepEqual(submissionBody('sid', 7, ['top'], 2), { signed_id: 'sid', template_id: 7, captions: ['top', ''] })
  assert.deepEqual(submissionBody('sid', 7, [], 1), { signed_id: 'sid', template_id: 7, captions: [''] })
  assert.deepEqual(submissionBody('sid', 7, [undefined, 'b'], 2).captions, ['', 'b'])
})

test('failureMessage names the failure in words a Player can act on', () => {
  assert.match(failureMessage(new DOMException('tainted', 'SecurityError')), /export/i)
  assert.match(failureMessage(new Error('Direct upload failed')), /upload/i)
  assert.match(failureMessage(null), /Could not make/i)
  assert.equal(failureMessage({ serverErrors: ['Time is up'] }), 'Time is up')
})
