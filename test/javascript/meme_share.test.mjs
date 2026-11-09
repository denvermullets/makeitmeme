import { test } from 'node:test'
import assert from 'node:assert/strict'
import { saveMethod } from '../../app/javascript/meme_share.js'

const file = { name: 'round-2-ada.png' }

test('shares when the device says it can share the file', () => {
  const nav = { share: () => {}, canShare: (data) => data.files.length === 1 && data.files[0] === file }
  assert.equal(saveMethod(nav, file), 'share')
})

test('downloads when the device cannot share the file', () => {
  assert.equal(saveMethod({ share: () => {}, canShare: () => false }, file), 'download')
})

test('downloads when there is no canShare (desktop browsers)', () => {
  assert.equal(saveMethod({}, file), 'download')
  assert.equal(saveMethod(undefined, file), 'download')
})

test('downloads when canShare throws', () => {
  const nav = { share: () => {}, canShare: () => { throw new TypeError('nope') } }
  assert.equal(saveMethod(nav, file), 'download')
})

test('downloads when share is missing even if canShare says yes', () => {
  assert.equal(saveMethod({ canShare: () => true }, file), 'download')
})
