// Pure schedule for the synced Scoreboard reveal (ADR 0001). No DOM, no Stimulus, no device clock: the result
// depends only on the Game's finished time and the current server time, so every phone agrees.
//
// `places` is the ordered list of distinct places, last place first (tied Players share one entry, so a tie is
// one step). Step 0 is due at the finished time, each later step one gap after the one before, except first
// place (the last step), which waits LEAD_IN_MS. The gap shrinks so the whole reveal never exceeds MAX_TOTAL_MS.
export const STEP_MS = 1500
export const LEAD_IN_MS = 3000
export const MAX_TOTAL_MS = 20000

// Milliseconds after the finished time at which each step is due.
export function stepOffsets(count) {
  if (count <= 0) return []
  if (count === 1) return [0]
  const gaps = count - 2 // gaps between steps before the lead-in
  const gap = gaps > 0 ? Math.min(STEP_MS, (MAX_TOTAL_MS - LEAD_IN_MS) / gaps) : STEP_MS
  const offsets = []
  for (let i = 0; i < count - 1; i++) offsets.push(i * gap)
  offsets.push(offsets[count - 2] + LEAD_IN_MS)
  return offsets
}

// finishedAt/serverNow: ISO strings or epoch ms. Returns { showing, nextAt } where `showing` is the places
// revealed so far (last place first) and `nextAt` the ISO time the next step is due, or null when done.
export function revealSchedule({ finishedAt, serverNow, places }) {
  const start = new Date(finishedAt).getTime()
  const now = new Date(serverNow).getTime()
  const offsets = stepOffsets(places.length)
  const shown = offsets.filter((offset) => start + offset <= now).length
  const next = offsets[shown]
  return {
    showing: places.slice(0, shown),
    nextAt: next === undefined ? null : new Date(start + next).toISOString(),
  }
}
