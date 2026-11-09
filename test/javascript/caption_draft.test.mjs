import test from 'node:test'
import assert from 'node:assert/strict'
import { saveDraft, loadDraft, clearDraft, clearOtherDrafts } from '../../app/javascript/caption_draft.js'

function fakeStorage() {
  const data = new Map()
  return {
    get length() { return data.size },
    key: (i) => [...data.keys()][i] ?? null,
    getItem: (k) => (data.has(k) ? data.get(k) : null),
    setItem: (k, v) => data.set(k, String(v)),
    removeItem: (k) => data.delete(k),
  }
}
const blocked = new Proxy({}, { get() { throw new DOMException('blocked', 'SecurityError') } })

test('a saved draft comes back for the same Round and Template only', () => {
  const s = fakeStorage()
  saveDraft('1-2', 7, ['top', 'bottom'], s)
  assert.deepEqual(loadDraft('1-2', 7, 2, s), ['top', 'bottom'])
  assert.deepEqual(loadDraft('1-3', 7, 2, s), [])
  assert.deepEqual(loadDraft('1-2', 8, 2, s), [])
})

test('a draft is trimmed to the Text Box count and ignores junk', () => {
  const s = fakeStorage()
  saveDraft('1-2', 7, ['a', 'b', 'c'], s)
  assert.deepEqual(loadDraft('1-2', 7, 2, s), ['a', 'b'])
  s.setItem('caption-draft:1-2:9', '{not json')
  assert.deepEqual(loadDraft('1-2', 9, 2, s), [])
  s.setItem('caption-draft:1-2:9', '{"a":1}')
  assert.deepEqual(loadDraft('1-2', 9, 2, s), [])
})

test('an all-blank caption leaves no draft, and clearDraft removes one', () => {
  const s = fakeStorage()
  saveDraft('1-2', 7, ['x'], s)
  saveDraft('1-2', 7, ['', undefined], s)
  assert.equal(s.length, 0)
  saveDraft('1-2', 7, ['x'], s)
  clearDraft('1-2', 7, s)
  assert.equal(s.length, 0)
})

test('clearOtherDrafts keeps this Round and leaves unrelated keys alone', () => {
  const s = fakeStorage()
  saveDraft('1-1', 7, ['old'], s)
  saveDraft('1-2', 7, ['now'], s)
  s.setItem('other', 'x')
  clearOtherDrafts('1-2', s)
  assert.deepEqual(loadDraft('1-1', 7, 1, s), [])
  assert.deepEqual(loadDraft('1-2', 7, 1, s), ['now'])
  assert.equal(s.getItem('other'), 'x')
  clearOtherDrafts(undefined, s)
  assert.deepEqual(loadDraft('1-2', 7, 1, s), [])
})

test('blocked or missing storage means no draft and no throw', () => {
  assert.doesNotThrow(() => saveDraft('1-2', 7, ['a'], blocked))
  assert.deepEqual(loadDraft('1-2', 7, 1, blocked), [])
  assert.doesNotThrow(() => clearDraft('1-2', 7, blocked))
  assert.doesNotThrow(() => clearOtherDrafts('1-2', blocked))
  assert.deepEqual(loadDraft('1-2', 7, 1, null), [])
})
