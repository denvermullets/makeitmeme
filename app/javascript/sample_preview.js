// Sample captions and fit read-outs for the Admin sample-text preview. Pure helpers; the drawing itself is the
// shared render() in meme_render.js.
export const LEVELS = ["off", "short", "medium", "long"]

const SAMPLES = {
  off: () => "",
  short: (i) => `BOX ${i + 1}`,
  medium: () => "WHEN THE STANDUP RUNS LONG",
  long: () => "WHEN SOMEONE SAYS QUICK SYNC AND IT TURNS INTO A NINETY MINUTE ALL HANDS MEETING",
}

// One sample caption per box for the given level (unknown levels behave as off).
export function sampleCaptions(level, count) {
  const sample = SAMPLES[level] || SAMPLES.off
  return Array.from({ length: count }, (_, i) => sample(i))
}

// Read-out for one box from render()'s fit entry: { text, warning }.
export function fitSummary(fit) {
  if (!fit) return { text: "", warning: false }
  const warning = Boolean(fit.atMinimum && fit.overflow)
  return { text: warning ? `${fit.size}px, overflows` : `${fit.size}px`, warning }
}
