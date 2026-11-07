// PROTOTYPE (MEME-5), throwaway. Do not merge to main.
// Question: how should captioning feel on a phone? Three structurally different variants:
//   A  One Template at a time with its inputs inline; Back/Next moves and discards the caption (chosen direction).
//   B  Grid + type on image: all 10 thumbnails at once; type straight onto the Text Boxes. One draft; switching discards it.
//   C  Filmstrip: preview, filmstrip and inputs on one screen; your lines carry over when you switch Templates.
// The canvas render() is shared by preview and export (MEME-4). Submit bakes a PNG and shows it; nothing is uploaded.
import { Controller } from "@hotwired/stimulus"

const MAX_SIDE = 2048
const MIN_FONT = 8
const LINE_HEIGHT = 1.1
const MAX_CHARS = 80
const images = {}

function loadImage(url) {
  if (!images[url]) {
    images[url] = new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = url
    })
  }
  return images[url]
}

function wrap(ctx, text, size) {
  ctx.font = `${size}px Anton`
  const lines = []
  let line = ""
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word
    if (line && ctx.measureText(next).width > ctx._maxW) { lines.push(line); line = word } else line = next
  }
  if (line) lines.push(line)
  return lines
}

function fit(ctx, text, w, h, stroked) {
  let lo = MIN_FONT, hi = Math.max(MIN_FONT, Math.floor(h)), best = null
  while (lo <= hi) {
    const size = Math.floor((lo + hi) / 2)
    const pad = stroked ? size / 8 : 0
    ctx._maxW = w - pad
    const lines = wrap(ctx, text, size)
    const ok = lines.length * size * LINE_HEIGHT <= h - pad && lines.every((l) => ctx.measureText(l).width <= w - pad)
    if (ok) { best = { size, lines }; lo = size + 1 } else hi = size - 1
  }
  if (!best) { ctx._maxW = w; best = { size: MIN_FONT, lines: wrap(ctx, text, MIN_FONT) } }
  return best
}

// The one render function: preview and export both call this on the same canvas.
function render(canvas, tpl, img, captions, opts = {}) {
  const scale = Math.min(1, MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight))
  const W = Math.round(img.naturalWidth * scale), H = Math.round(img.naturalHeight * scale)
  if (canvas.width !== W) canvas.width = W
  if (canvas.height !== H) canvas.height = H
  const ctx = canvas.getContext("2d")
  ctx.drawImage(img, 0, 0, W, H)
  tpl.boxes.forEach((box, i) => {
    const bw = box.w * W, bh = box.h * H
    ctx.save()
    ctx.translate((box.x + box.w / 2) * W, (box.y + box.h / 2) * H)
    ctx.rotate((box.angle * Math.PI) / 180)
    let text = (captions[i] || "").trim()
    if (opts.outlines && !text) {
      ctx.setLineDash([8, 6]); ctx.lineWidth = 3; ctx.strokeStyle = "rgba(255,230,0,.9)"
      ctx.strokeRect(-bw / 2, -bh / 2, bw, bh)
      ctx.fillStyle = "rgba(255,230,0,.9)"; ctx.font = `${Math.min(bh * 0.6, 48)}px Anton`
      ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(String(i + 1), 0, 0)
    }
    if (text) {
      if (opts.caps !== false) text = text.toUpperCase()
      const stroked = box.font === "thick" || opts.color
      const fill = opts.color || box.color
      const { size, lines } = fit(ctx, text, bw, bh, stroked)
      ctx.font = `${size}px Anton`; ctx.textAlign = "center"; ctx.textBaseline = "middle"
      ctx.lineJoin = "round"; ctx.lineWidth = size / 8
      ctx.strokeStyle = fill === "black" ? "#fff" : "#000"; ctx.fillStyle = fill
      const top = -((lines.length - 1) * size * LINE_HEIGHT) / 2
      lines.forEach((l, n) => {
        const y = top + n * size * LINE_HEIGHT
        if (stroked) ctx.strokeText(l, 0, y)
        ctx.fillText(l, 0, y)
      })
    }
    ctx.restore()
  })
}

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
const mmss = (ms) => { const s = Math.max(0, Math.ceil(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` }

export default class extends Controller {
  static targets = ["root", "state"]
  static values = { hand: Array, variant: String, seconds: Number }

  async connect() {
    this.s = {
      variant: this.variantValue,
      screen: this.variantValue === "B" ? "hand" : "edit",
      selectedId: this.variantValue === "B" ? null : this.handValue[0].id,
      drafts: {},        // A: per-Template captions, kept when you go back to the Hand
      draft: [],         // B: one draft, discarded on switch
      lines: [],         // C: one list of lines, carried across Templates by Text Box index
      caps: true,
      color: null,
      submitted: null,
      remaining: this.secondsValue * 1000,
    }
    this.deadline = Date.now() + this.secondsValue * 1000
    this.rootTarget.innerHTML = `<p class="pme-loading">Loading fonts and Hand…</p>`
    try { await document.fonts.load("40px Anton", "ABC") } catch (e) { console.warn("Anton failed", e) }
    await Promise.all(this.handValue.map((t) => loadImage(t.url)))
    this.timer = setInterval(() => this.tick(), 200)
    this.show()
  }

  disconnect() { clearInterval(this.timer) }

  // ---------- shared plumbing ----------
  tpl(id = this.s.selectedId) { return this.handValue.find((t) => t.id === id) }

  captionsFor(tpl) {
    if (this.s.variant === "A") return this.s.selectedId === tpl.id ? this.s.draft : []
    if (this.s.variant === "B") return this.s.selectedId === tpl.id ? this.s.draft : []
    return this.s.lines
  }

  opts() {
    if (this.s.variant === "A") return {}
    if (this.s.variant === "B") return { caps: this.s.caps }
    return { caps: this.s.caps, color: this.s.color }
  }

  async draw(canvas, tpl, outlines = true) {
    render(canvas, tpl, await loadImage(tpl.url), this.captionsFor(tpl), { ...this.opts(), outlines })
  }

  redraw() {
    cancelAnimationFrame(this.raf)
    this.raf = requestAnimationFrame(() => {
      this.rootTarget.querySelectorAll("canvas[data-tpl]").forEach((c) => this.draw(c, this.tpl(c.dataset.tpl), !this.s.submitted))
      this.dump()
    })
  }

  dump() { this.stateTarget.textContent = JSON.stringify({ ...this.s, remaining: mmss(this.s.remaining) }, null, 2) }

  tick() {
    this.s.remaining = this.deadline - Date.now()
    const total = this.secondsValue * 1000
    const frac = Math.max(0, this.s.remaining / total)
    this.rootTarget.querySelectorAll(".pme-t-text").forEach((el) => (el.textContent = mmss(this.s.remaining)))
    this.rootTarget.querySelectorAll(".pme-t-bar").forEach((el) => (el.style.width = `${frac * 100}%`))
    this.rootTarget.querySelectorAll(".pme-t-ring").forEach((el) => (el.style.strokeDashoffset = `${(1 - frac) * 100}`))
    this.element.classList.toggle("pme-urgent", this.s.remaining <= 15000)
    this.element.classList.toggle("pme-critical", this.s.remaining <= 5000)
    this.element.classList.toggle("pme-final", this.s.remaining <= 10000)
    if (this.s.remaining <= 0 && !this.s.submitted) this.submit(true)
    this.dump()
  }

  select(id) { this.s.selectedId = id; this.s.screen = "edit"; this.show() }

  async submit(auto = false) {
    if (this.s.submitted) return
    clearInterval(this.timer)
    const tpl = this.s.selectedId && this.tpl()
    if (!tpl) { this.s.submitted = { auto, meme: null }; return this.modal(`<h2>Time's up</h2><p>You never picked a Template, so no Meme was submitted.</p>`) }
    const canvas = document.createElement("canvas")
    await this.draw(canvas, tpl, false) // export pass: same render(), no box outlines
    canvas.toBlob((blob) => {
      const url = URL.createObjectURL(blob)
      this.s.submitted = { auto, template: tpl.id, captions: this.captionsFor(tpl), kb: Math.round(blob.size / 1024), px: `${canvas.width}x${canvas.height}` }
      this.modal(`<h2>${auto ? "Time's up: auto-submitted" : "Submitted"}</h2>
        <img src="${url}" alt="Baked Meme">
        <p>${esc(tpl.name)} · ${canvas.width}×${canvas.height} · ${this.s.submitted.kb} KB PNG</p>`)
      this.dump()
    }, "image/png")
  }

  modal(html) {
    const m = document.createElement("div")
    m.className = "pme-modal"
    m.innerHTML = `<div class="pme-modal-card">${html}<button type="button" class="pme-btn" data-reset>Play again</button></div>`
    m.querySelector("[data-reset]").onclick = () => window.location.reload()
    this.element.appendChild(m)
  }

  bindInputs(get) {
    this.rootTarget.querySelectorAll("[data-box]").forEach((el) => {
      el.addEventListener("input", () => { get()[Number(el.dataset.box)] = el.value; this.redraw(); this.afterInput?.() })
    })
  }

  show() {
    this.afterInput = null
    this[`variant${this.s.variant}`]()
    this.tick()
    this.redraw()
  }

  // ---------- A: one Template at a time, inputs inline, Back/Next discards text ----------
  variantA() {
    const i = this.handValue.findIndex((t) => t.id === this.s.selectedId)
    const tpl = this.tpl()
    this.rootTarget.innerHTML = `<div class="pme-a">
      <header class="pme-a-head"><div class="pme-t-track"><div class="pme-t-bar"></div></div>
        <div class="pme-a-headrow"><strong>Round 1</strong><span class="pme-t-text"></span></div></header>
      <canvas class="pme-main" data-tpl="${tpl.id}"></canvas>
      <div class="pme-a-nav"><button type="button" data-step="-1" ${i === 0 ? "disabled" : ""}>‹ Back</button>
        <span>${i + 1} / ${this.handValue.length}</span>
        <button type="button" data-step="1" ${i === this.handValue.length - 1 ? "disabled" : ""}>Next ›</button></div>
      <div class="pme-a-fields">${tpl.boxes.map((b, n) => `
        <label>Box ${n + 1}<input data-box="${n}" maxlength="${MAX_CHARS}" value="${esc(this.s.draft[n] || "")}" placeholder="Caption for box ${n + 1}"></label>`).join("")}</div>
      <button type="button" class="pme-btn" data-submit>Submit this Meme</button></div>`
    this.bindInputs(() => this.s.draft)
    this.rootTarget.querySelectorAll("[data-step]").forEach((b) => (b.onclick = () => {
      this.s.selectedId = this.handValue[i + Number(b.dataset.step)].id
      this.s.draft = [] // navigating away loses the caption
      this.show()
    }))
    this.rootTarget.querySelector("[data-submit]").onclick = () => this.submit()
  }

  // ---------- B: grid + type on image ----------
  variantB() {
    const ring = `<div class="pme-b-ring"><svg viewBox="0 0 36 36"><circle cx="18" cy="18" r="15.9" pathLength="100" class="pme-b-ring-bg"/>
      <circle cx="18" cy="18" r="15.9" pathLength="100" class="pme-t-ring"/></svg><span class="pme-t-text"></span></div>`
    if (this.s.screen === "hand") {
      this.rootTarget.innerHTML = `<div class="pme-b">${ring}<h1>Pick a Template</h1>
        <div class="pme-b-grid">${this.handValue.map((t) => `
          <button type="button" class="pme-b-cell" data-id="${t.id}"><img src="${t.url}" alt="${esc(t.name)}"><span>${t.boxes.length}</span></button>`).join("")}</div></div>`
      this.rootTarget.querySelectorAll(".pme-b-cell").forEach((b) => (b.onclick = () => {
        if (b.dataset.id !== this.s.selectedId) this.s.draft = this.tpl(b.dataset.id).boxes.map(() => "")
        this.select(b.dataset.id)
      }))
    } else {
      const tpl = this.tpl()
      this.rootTarget.innerHTML = `<div class="pme-b">${ring}
        <button type="button" class="pme-link" data-change>⇄ Change Template</button>
        <div class="pme-b-stage"><canvas class="pme-main" data-tpl="${tpl.id}"></canvas>
          ${tpl.boxes.map((b, i) => `<textarea data-box="${i}" maxlength="${MAX_CHARS}" rows="1" aria-label="Box ${i + 1}"
            style="left:${b.x * 100}%;top:${b.y * 100}%;width:${b.w * 100}%;height:${b.h * 100}%;transform:rotate(${b.angle}deg)">${esc(this.s.draft[i] || "")}</textarea>`).join("")}
        </div>
        <p class="pme-hint">Tap a yellow box and type right on the image.</p>
        <label class="pme-toggle"><input type="checkbox" data-caps ${this.s.caps ? "checked" : ""}> ALL CAPS</label>
        <button type="button" class="pme-btn" data-submit>Submit Meme</button></div>`
      this.bindInputs(() => this.s.draft)
      this.rootTarget.querySelector("[data-caps]").onchange = (e) => { this.s.caps = e.target.checked; this.redraw() }
      this.rootTarget.querySelector("[data-change]").onclick = () => {
        if (this.s.draft.some(Boolean) && !confirm("Switching Templates throws away your caption. Switch anyway?")) return
        this.s.screen = "hand"; this.show()
      }
      this.rootTarget.querySelector("[data-submit]").onclick = () => this.submit()
    }
  }

  // ---------- C: filmstrip, lines carry over ----------
  variantC() {
    const tpl = this.tpl()
    const hidden = this.s.lines.slice(tpl.boxes.length).filter(Boolean).length
    const colors = [[null, "Template"], ["#fff", "White"], ["black", "Black"], ["#ffe14d", "Yellow"]]
    this.rootTarget.innerHTML = `<div class="pme-c">
      <header class="pme-c-head"><strong>${esc(tpl.name)}</strong><span class="pme-t-text"></span></header>
      <canvas class="pme-main" data-tpl="${tpl.id}"></canvas>
      <div class="pme-c-strip">${this.handValue.map((t) => `
        <button type="button" class="${t.id === tpl.id ? "on" : ""}" data-id="${t.id}"><img src="${t.url}" alt="${esc(t.name)}"><span>${t.boxes.length}</span></button>`).join("")}</div>
      <div class="pme-c-fields">${tpl.boxes.map((b, i) => `
        <input data-box="${i}" maxlength="${MAX_CHARS}" value="${esc(this.s.lines[i] || "")}" placeholder="Line ${i + 1}">`).join("")}
        ${hidden ? `<p class="pme-hint">+${hidden} line${hidden > 1 ? "s" : ""} from another Template not shown here (kept if you switch back)</p>` : ""}</div>
      <div class="pme-c-style">
        ${colors.map(([c, n]) => `<button type="button" class="pme-chip ${this.s.color === c ? "on" : ""}" data-color="${c ?? ""}" style="--chip:${c ?? "linear-gradient(135deg,#fff 50%,#000 50%)"}">${n}</button>`).join("")}
        <label class="pme-toggle"><input type="checkbox" data-caps ${this.s.caps ? "checked" : ""}> CAPS</label>
      </div>
      <button type="button" class="pme-btn pme-c-submit" data-submit>Submit · <span class="pme-t-text"></span></button></div>`
    this.bindInputs(() => this.s.lines)
    this.rootTarget.querySelectorAll(".pme-c-strip button").forEach((b) => (b.onclick = () => { this.s.selectedId = b.dataset.id; this.show() }))
    this.rootTarget.querySelectorAll("[data-color]").forEach((b) => (b.onclick = () => { this.s.color = b.dataset.color || null; this.show() }))
    this.rootTarget.querySelector("[data-caps]").onchange = (e) => { this.s.caps = e.target.checked; this.redraw() }
    this.rootTarget.querySelector("[data-submit]").onclick = () => this.submit()
  }
}
