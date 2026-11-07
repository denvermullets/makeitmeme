// Pure maths for rendering a Meme: export size, Text Box geometry, text fitting.
// No DOM here so it can be unit tested under node (see test/javascript). The canvas drawing lives in
// `drawMeme` below, which takes a 2d context and is the single render path for preview and export.

export const MAX_SIDE = 2048
export const MIN_FONT = 8
export const LINE_HEIGHT = 1.1
export const FONT_FAMILY = 'Anton'

export function canvasSize(naturalWidth, naturalHeight, maxSide = MAX_SIDE) {
  const scale = Math.min(1, maxSide / Math.max(naturalWidth, naturalHeight))
  return { width: Math.round(naturalWidth * scale), height: Math.round(naturalHeight * scale) }
}

// Text Box fractions (top-left x/y, w/h) to pixels about the box centre; angle in degrees.
export function boxGeometry(box, width, height) {
  return {
    cx: (box.x + box.w / 2) * width,
    cy: (box.y + box.h / 2) * height,
    w: box.w * width,
    h: box.h * height,
    radians: ((box.angle || 0) * Math.PI) / 180
  }
}

// Greedy word wrap. `measure(text, size)` returns the pixel width of text at that font size.
export function wrapLines(measure, text, size, maxWidth) {
  const lines = []
  let line = ''
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word
    if (line && measure(next, size) > maxWidth) {
      lines.push(line)
      line = word
    } else {
      line = next
    }
  }
  if (line) lines.push(line)
  return lines
}

// Binary search for the largest integer font size at which the wrapped text fits w x h.
// Stroked text reserves size/8 of padding. Falls back to MIN_FONT with `overflow: true`.
export function fitText(measure, text, w, h, stroked, { minSize = MIN_FONT, maxSize = Math.floor(h) } = {}) {
  let lo = minSize
  let hi = Math.max(minSize, maxSize)
  let best = null
  while (lo <= hi) {
    const size = Math.floor((lo + hi) / 2)
    const pad = stroked ? size / 8 : 0
    const lines = wrapLines(measure, text, size, w - pad)
    const fits = lines.length * size * LINE_HEIGHT <= h - pad && lines.every((l) => measure(l, size) <= w - pad)
    if (fits) {
      best = { size, lines }
      lo = size + 1
    } else {
      hi = size - 1
    }
  }
  return best || { size: minSize, lines: wrapLines(measure, text, minSize, w), overflow: true }
}

// Draw the Template image and every non-empty caption onto `canvas`. `captions[i]` belongs to Text Box i.
// opts.outlines draws dashed numbered guides on empty boxes (preview only, never in the export).
export function drawMeme(canvas, template, img, captions, { outlines = false } = {}) {
  const { width, height } = canvasSize(img.naturalWidth, img.naturalHeight)
  if (canvas.width !== width) canvas.width = width
  if (canvas.height !== height) canvas.height = height
  const ctx = canvas.getContext('2d')
  ctx.drawImage(img, 0, 0, width, height)

  template.boxes.forEach((box, i) => {
    const g = boxGeometry(box, width, height)
    const text = (captions[i] || '').trim().toUpperCase()
    ctx.save()
    ctx.translate(g.cx, g.cy)
    ctx.rotate(g.radians)
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    if (outlines && !text) {
      ctx.setLineDash([8, 6])
      ctx.lineWidth = 3
      ctx.strokeStyle = 'rgba(255,230,0,.9)'
      ctx.strokeRect(-g.w / 2, -g.h / 2, g.w, g.h)
      ctx.fillStyle = 'rgba(255,230,0,.9)'
      ctx.font = `${Math.min(g.h * 0.6, 48)}px ${FONT_FAMILY}`
      ctx.fillText(String(i + 1), 0, 0)
    }
    if (text) {
      const stroked = box.font === 'thick'
      const measure = (s, size) => {
        ctx.font = `${size}px ${FONT_FAMILY}`
        return ctx.measureText(s).width
      }
      const { size, lines } = fitText(measure, text, g.w, g.h, stroked)
      ctx.font = `${size}px ${FONT_FAMILY}`
      ctx.lineJoin = 'round'
      ctx.lineWidth = size / 8
      ctx.strokeStyle = box.color === 'black' ? '#fff' : '#000'
      ctx.fillStyle = box.color
      const top = -((lines.length - 1) * size * LINE_HEIGHT) / 2
      lines.forEach((line, n) => {
        const y = top + n * size * LINE_HEIGHT
        if (stroked) ctx.strokeText(line, 0, y)
        ctx.fillText(line, 0, y)
      })
    }
    ctx.restore()
  })
}
