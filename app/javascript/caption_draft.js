// Caption drafts: the Text Box texts a Player is typing, kept in browser storage keyed by Round and Template so a
// reload during the same Captioning restores them. Storage can be blocked or empty, so every access is wrapped:
// failure just means no draft.
const PREFIX = 'caption-draft:'

function defaultStorage() {
  try {
    return globalThis.localStorage
  } catch {
    return null
  }
}

export function draftKey(roundKey, templateId) { return `${PREFIX}${roundKey}:${templateId}` }

export function saveDraft(roundKey, templateId, captions, storage = defaultStorage()) {
  try {
    if (captions.some((text) => text)) storage.setItem(draftKey(roundKey, templateId), JSON.stringify(captions))
    else storage.removeItem(draftKey(roundKey, templateId))
  } catch { /* no storage, no draft */ }
}

// Returns an array of strings no longer than boxCount, or [] when there is no usable draft.
export function loadDraft(roundKey, templateId, boxCount, storage = defaultStorage()) {
  try {
    const parsed = JSON.parse(storage.getItem(draftKey(roundKey, templateId)))
    if (!Array.isArray(parsed)) return []
    return parsed.slice(0, boxCount).map((text) => (typeof text === 'string' ? text : ''))
  } catch {
    return []
  }
}

export function clearDraft(roundKey, templateId, storage = defaultStorage()) {
  try { storage.removeItem(draftKey(roundKey, templateId)) } catch { /* nothing to clear */ }
}

// Removes every draft that does not belong to this Round (earlier Rounds or Games). With no keep, removes them all.
export function clearOtherDrafts(keepRoundKey, storage = defaultStorage()) {
  try {
    const keep = keepRoundKey === undefined ? null : `${PREFIX}${keepRoundKey}:`
    const stale = []
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i)
      if (key?.startsWith(PREFIX) && !(keep && key.startsWith(keep))) stale.push(key)
    }
    stale.forEach((key) => storage.removeItem(key))
  } catch { /* no storage, no drafts */ }
}
