// PROTOTYPE (MEME-6), throwaway. Do not merge to main.
// Question: how does the Admin place Text Boxes on a Template, and what else lives in the admin panel?
// Three structurally different variants on one route (?variant=A|B|C):
//   A  Studio (desktop, three panes): library grid | stage with drag/resize/rotate handles | numeric inspector. Autosaves.
//   B  Phone form: list -> edit screen. No dragging: layout presets + per-box sliders. Explicit Save, confirm on discard.
//   C  Review queue: one Template at a time from "needs review". Drag on the image to draw a box, drag a box to move it,
//      keyboard for everything else. "Approve & next" commits; "Skip" discards.
// Text Box format everywhere: { x, y, w, h } as 0-1 fractions of the image (top-left + size), angle in degrees about
// the box centre, color white|black, font thick (outlined) | thin. Same shape as the Meme editor prototype (MEME-5).
// Nothing persists: reload to reset.
import { Controller } from "@hotwired/stimulus"

const MAX_SIDE = 2048, MIN_FONT = 8, LINE_HEIGHT = 1.1, MIN_PX = 12
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

function wrap(ctx, text, size, maxW) {
  ctx.font = `${size}px Anton`
  const lines = []
  let line = ""
  for (const word of text.split(/\s+/).filter(Boolean)) {
    const next = line ? `${line} ${word}` : word
    if (line && ctx.measureText(next).width > maxW) { lines.push(line); line = word } else line = next
  }
  if (line) lines.push(line)
  return lines
}

function fit(ctx, text, w, h, stroked) {
  let lo = MIN_FONT, hi = Math.max(MIN_FONT, Math.floor(h)), best = null
  while (lo <= hi) {
    const size = Math.floor((lo + hi) / 2)
    const pad = stroked ? size / 8 : 0
    const lines = wrap(ctx, text, size, w - pad)
    const ok = lines.length * size * LINE_HEIGHT <= h - pad && lines.every((l) => ctx.measureText(l).width <= w - pad)
    if (ok) { best = { size, lines }; lo = size + 1 } else hi = size - 1
  }
  return best || { size: MIN_FONT, lines: wrap(ctx, text, MIN_FONT, w), floor: true }
}

// Same render as the Meme editor: what the Admin previews is exactly what Players will bake.
function render(canvas, img, boxes, captions) {
  const scale = Math.min(1, MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight))
  const W = Math.round(img.naturalWidth * scale), H = Math.round(img.naturalHeight * scale)
  if (canvas.width !== W) canvas.width = W
  if (canvas.height !== H) canvas.height = H
  const ctx = canvas.getContext("2d")
  ctx.drawImage(img, 0, 0, W, H)
  const fits = []
  boxes.forEach((box, i) => {
    const text = (captions[i] || "").trim().toUpperCase()
    if (!text) return fits.push(null)
    const bw = box.w * W, bh = box.h * H
    ctx.save()
    ctx.translate((box.x + box.w / 2) * W, (box.y + box.h / 2) * H)
    ctx.rotate((box.angle * Math.PI) / 180)
    const stroked = box.font === "thick"
    const { size, lines, floor } = fit(ctx, text, bw, bh, stroked)
    fits.push({ size: Math.round(size / scale), floor: !!floor })
    ctx.font = `${size}px Anton`; ctx.textAlign = "center"; ctx.textBaseline = "middle"
    ctx.lineJoin = "round"; ctx.lineWidth = size / 8
    ctx.strokeStyle = box.color === "black" ? "#fff" : "#000"; ctx.fillStyle = box.color
    const top = -((lines.length - 1) * size * LINE_HEIGHT) / 2
    lines.forEach((l, n) => {
      const y = top + n * size * LINE_HEIGHT
      if (stroked) ctx.strokeText(l, 0, y)
      ctx.fillText(l, 0, y)
    })
    ctx.restore()
  })
  return fits
}

const box = (x, y, w, h) => ({ x, y, w, h, angle: 0, color: "white", font: "thick" })
const TOP_BOTTOM = () => [box(0, 0, 1, 0.2), box(0, 0.8, 1, 0.2)]
const PRESETS = [
  ["tb", "Top & bottom", TOP_BOTTOM],
  ["top", "Top only", () => [box(0, 0, 1, 0.22)]],
  ["bottom", "Bottom only", () => [box(0, 0.78, 1, 0.22)]],
  ["right", "Right column", () => [box(0.5, 0, 0.5, 0.5), box(0.5, 0.5, 0.5, 0.5)]],
  ["grid", "2 × 2 grid", () => [box(0, 0, 0.5, 0.5), box(0.5, 0, 0.5, 0.5), box(0, 0.5, 0.5, 0.5), box(0.5, 0.5, 0.5, 0.5)]],
  ["three", "Three across", () => [box(0, 0.4, 0.333, 0.2), box(0.333, 0.4, 0.334, 0.2), box(0.667, 0.4, 0.333, 0.2)]],
  ["centre", "Centre", () => [box(0.15, 0.4, 0.7, 0.2)]],
]
const SAMPLES = {
  off: () => "",
  short: (i) => `BOX ${i + 1}`,
  medium: () => "WHEN THE STANDUP RUNS LONG",
  long: () => "WHEN SOMEONE SAYS QUICK SYNC AND IT TURNS INTO A NINETY MINUTE ALL HANDS MEETING",
}
const FILTERS = [["all", "All"], ["review", "Needs review"], ["uploads", "Player uploads"], ["hidden", "Hidden"]]
const HANDLE_DIRS = { nw: [-1, -1], n: [0, -1], ne: [1, -1], e: [1, 0], se: [1, 1], s: [0, 1], sw: [-1, 1], w: [-1, 0] }
const HANDLES = `<i class="pab-rot" data-handle="rot"></i>` +
  Object.entries(HANDLE_DIRS).map(([k, [sx, sy]]) => `<i class="pab-h" data-handle="${k}" style="left:${(sx + 1) * 50}%;top:${(sy + 1) * 50}%"></i>`).join("")

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
const r3 = (v) => Math.round(v * 1000) / 1000
const r1 = (v) => Math.round(v * 10) / 10
const normAngle = (a) => ((((a + 180) % 360) + 360) % 360) - 180
const toPx = (b, W, H) => ({ cx: (b.x + b.w / 2) * W, cy: (b.y + b.h / 2) * H, w: b.w * W, h: b.h * H, a: b.angle })
const fromPx = (p, W, H) => ({ x: r3((p.cx - p.w / 2) / W), y: r3((p.cy - p.h / 2) / H), w: r3(p.w / W), h: r3(p.h / H), angle: r1(p.a) })
const fieldVal = (b, k) => (k === "angle" ? r1(b.angle) : r1(b[k] * 100))

export default class extends Controller {
  static targets = ["root", "state"]
  static values = { templates: Array, variant: String }

  async connect() {
    const v = this.variantValue
    this.s = {
      variant: v,
      templates: structuredClone(this.templatesValue),
      selectedId: null,
      boxIndex: null,
      sample: "medium",
      filter: v === "C" ? "review" : "all",
      query: "",
      screen: "list",   // B only
      dirty: false,     // B, C
      savedAt: null,    // A
      queue: [], pos: 0, approved: 0, // C
    }
    this.rootTarget.addEventListener("click", (e) => this.onClick(e))
    this.rootTarget.addEventListener("input", (e) => this.onInput(e))
    this.rootTarget.addEventListener("change", (e) => this.onChange(e))
    if (v === "C") { this.onKey = (e) => this.keyC(e); window.addEventListener("keydown", this.onKey, true) }

    this.rootTarget.innerHTML = `<p class="pab-loading">Loading Anton and the Template Library…</p>`
    try { await document.fonts.load("40px Anton", "ABC") } catch (e) { console.warn("Anton failed", e) }
    await Promise.all(this.s.templates.map(async (t) => {
      try { const img = await loadImage(t.url); t.iw = img.naturalWidth; t.ih = img.naturalHeight } catch { t.broken = true }
    }))
    if (v === "A") this.pick(this.s.templates[0].id)
    if (v === "C") this.buildQueue()
    this.show()
  }

  disconnect() { if (this.onKey) window.removeEventListener("keydown", this.onKey, true) }

  // ---------- data ----------
  tpl(id = this.s.selectedId) { return this.s.templates.find((t) => t.id === id) }
  sel() { return this.tpl()?.boxes[this.s.boxIndex] }

  visible() {
    const q = this.s.query.trim().toLowerCase()
    return this.s.templates.filter((t) => {
      if (q && !t.name.toLowerCase().includes(q)) return false
      if (this.s.filter === "review") return !t.reviewed && !t.hidden
      if (this.s.filter === "uploads") return t.source !== "memegen import"
      if (this.s.filter === "hidden") return t.hidden
      return true
    })
  }

  pick(id) {
    this.s.selectedId = id
    this.s.boxIndex = this.tpl(id)?.boxes.length ? 0 : null
    this.snapshot = structuredClone(this.tpl(id))
    this.s.dirty = false
  }

  discard() {
    const i = this.s.templates.findIndex((t) => t.id === this.s.selectedId)
    if (i >= 0 && this.snapshot) this.s.templates[i] = structuredClone(this.snapshot)
    this.s.dirty = false
  }

  // Called after any edit. full=true rebuilds the screen (structure changed); false just repaints.
  changed(full = false) {
    if (this.s.variant === "A") { this.tpl().reviewed = true; this.s.savedAt = new Date() } else this.s.dirty = true
    if (full) return this.show()
    this.paint()
    this.syncFields()
    this.refreshChrome()
  }

  // ---------- rendering plumbing ----------
  stage(tpl, maxh) {
    const ar = tpl.broken ? 1 : tpl.iw / tpl.ih
    return `<div class="pab-stage" data-stage style="--ar:${ar};--maxh:${maxh}">
      ${tpl.broken ? `<div class="pab-broken">image failed to load</div>` : `<canvas data-canvas></canvas>`}
      <div class="pab-overlay" data-overlay></div></div>`
  }

  overlay(tpl, handles) {
    return tpl.boxes.map((b, i) => {
      const on = i === this.s.boxIndex
      return `<div class="pab-box ${on ? "on" : ""} ${b.color === "black" ? "dark" : ""}" data-boxi="${i}"
        style="left:${b.x * 100}%;top:${b.y * 100}%;width:${b.w * 100}%;height:${b.h * 100}%;transform:rotate(${b.angle}deg)">
        <span class="pab-num">${i + 1}</span>${on && handles ? HANDLES : ""}</div>`
    }).join("")
  }

  paint() {
    cancelAnimationFrame(this.raf)
    this.raf = requestAnimationFrame(async () => {
      const tpl = this.tpl()
      const ov = this.rootTarget.querySelector("[data-overlay]")
      if (!tpl || !ov) return this.dump()
      ov.innerHTML = this.overlay(tpl, this.s.variant === "A")
      const canvas = this.rootTarget.querySelector("[data-canvas]")
      if (canvas) {
        this.fits = render(canvas, await loadImage(tpl.url), tpl.boxes, tpl.boxes.map((_, i) => SAMPLES[this.s.sample](i)))
        this.rootTarget.querySelectorAll("[data-fit]").forEach((el) => {
          const f = this.fits[Number(el.dataset.fit)]
          el.textContent = f ? `${f.size}px${f.floor ? " ⚠ at min size, overflows" : ""}` : ""
          el.classList.toggle("warn", !!f?.floor)
        })
        const info = this.rootTarget.querySelector("[data-info]")
        if (info) info.innerHTML = this.infoC()
      }
      this.dump()
    })
  }

  syncFields() {
    const tpl = this.tpl()
    if (!tpl) return
    this.rootTarget.querySelectorAll("[data-field]").forEach((el) => {
      const b = tpl.boxes[Number(el.dataset.i)]
      if (!b) return
      const v = fieldVal(b, el.dataset.field)
      if (el !== document.activeElement) el.value = v
      const out = el.closest("label")?.querySelector("[data-out]")
      if (out) out.textContent = el.dataset.field === "angle" ? `${v}°` : `${v}%`
    })
  }

  refreshChrome() {
    const saved = this.rootTarget.querySelector("[data-saved]")
    if (saved) saved.textContent = this.s.savedAt ? `Saved ✓ ${this.s.savedAt.toLocaleTimeString()}` : "No changes yet"
    const save = this.rootTarget.querySelector("[data-act=save]")
    if (save) save.disabled = !this.s.dirty
    this.rootTarget.querySelectorAll("[data-dirty]").forEach((el) => (el.hidden = !this.s.dirty))
    const info = this.rootTarget.querySelector("[data-info]")
    if (info) info.innerHTML = this.infoC()
  }

  dump() {
    const t = this.tpl()
    this.stateTarget.textContent = JSON.stringify({
      stored_template: t && { id: t.id, name: t.name, source: t.source, hidden: t.hidden, reviewed: t.reviewed, uses: t.uses, text_boxes: t.boxes },
      ui: { variant: this.s.variant, boxIndex: this.s.boxIndex, sample: this.s.sample, filter: this.s.filter, dirty: this.s.dirty,
        savedAt: this.s.savedAt, queue: this.s.variant === "C" ? `${this.s.pos + 1}/${this.s.queue.length}` : undefined },
    }, null, 2)
  }

  show() {
    this[`variant${this.s.variant}`]()
    this.bindStage()
    this.paint()
    this.syncFields()
    this.refreshChrome()
  }

  sampleSeg() {
    return `<div class="pab-seg" title="Sample text shrinks to fit each box">Sample ${Object.keys(SAMPLES).map((k) =>
      `<button type="button" data-act="sample" data-arg="${k}" class="${this.s.sample === k ? "on" : ""}">${k}</button>`).join("")}</div>`
  }

  styleSeg(i, b) {
    return `<div class="pab-seg">${[["white", "White, outlined"], ["black", "Black"]].map(([k, n]) =>
      `<button type="button" data-act="style" data-i="${i}" data-arg="${k}" class="${(b.color === "black" ? "black" : "white") === k ? "on" : ""}">${n}</button>`).join("")}</div>`
  }

  filterChips() {
    return `<div class="pab-chips">${FILTERS.map(([k, n]) => {
      const count = this.s.templates.filter((t) => k === "all" || (k === "review" ? !t.reviewed && !t.hidden : k === "uploads" ? t.source !== "memegen import" : t.hidden)).length
      return `<button type="button" data-act="filter" data-arg="${k}" class="${this.s.filter === k ? "on" : ""}">${n} <small>${count}</small></button>`
    }).join("")}</div>`
  }

  badges(t) {
    return `<span class="pab-badge">${t.boxes.length} box${t.boxes.length === 1 ? "" : "es"}</span>` +
      (t.hidden ? `<span class="pab-badge muted">hidden</span>` : "") +
      (!t.reviewed && !t.hidden ? `<span class="pab-badge warn">needs review</span>` : "") +
      (t.source !== "memegen import" ? `<span class="pab-badge up">upload</span>` : "")
  }

  // ---------- pointer: drag / resize / rotate / draw ----------
  bindStage() {
    const st = this.rootTarget.querySelector("[data-stage]")
    if (!st) return
    st.classList.add(`pab-mode-${this.s.variant}`)
    st.onpointerdown = (e) => this.down(e, st)
  }

  down(e, st) {
    const v = this.s.variant, tpl = this.tpl()
    const r = st.getBoundingClientRect(), W = r.width, H = r.height
    const p = { x: e.clientX - r.left, y: e.clientY - r.top }
    const hEl = e.target.closest("[data-handle]"), bEl = e.target.closest("[data-boxi]")
    let mode = null, i = this.s.boxIndex, sx = 0, sy = 0
    if (hEl && v === "A") {
      if (hEl.dataset.handle === "rot") mode = "rot"; else { mode = "resize"; [sx, sy] = HANDLE_DIRS[hEl.dataset.handle] }
    } else if (bEl) {
      i = Number(bEl.dataset.boxi)
      this.s.boxIndex = i
      if (v === "B") return this.show() // tap selects; no dragging in B
      mode = "move"
      this.afterSelect()
    } else if (v === "C") {
      tpl.boxes.push({ ...box(p.x / W, p.y / H, 0, 0) })
      i = tpl.boxes.length - 1
      this.s.boxIndex = i
      mode = "draw"
    } else {
      this.s.boxIndex = null
      return this.afterSelect()
    }
    e.preventDefault()
    st.setPointerCapture(e.pointerId)
    this.drag = { mode, i, W, H, r, p0: p, b0: toPx(tpl.boxes[i], W, H), sx, sy, moved: false }
    st.onpointermove = (ev) => this.dragMove(ev)
    st.onpointerup = st.onpointercancel = () => this.dragEnd(st)
  }

  afterSelect() {
    if (this.s.variant === "A") { this.inspectorA(); this.paint(); this.syncFields() }
    else { this.paint(); this.refreshChrome() }
  }

  dragMove(ev) {
    const d = this.drag
    if (!d) return
    const p = { x: ev.clientX - d.r.left, y: ev.clientY - d.r.top }
    const dx = p.x - d.p0.x, dy = p.y - d.p0.y
    if (Math.abs(dx) + Math.abs(dy) > 2) d.moved = true
    if (!d.moved) return
    const b = { ...d.b0 }, rad = (b.a * Math.PI) / 180, c = Math.cos(rad), s = Math.sin(rad)
    if (d.mode === "move") { b.cx += dx; b.cy += dy }
    if (d.mode === "resize") {
      const lx = dx * c + dy * s, ly = -dx * s + dy * c
      if (d.sx) b.w = Math.max(MIN_PX, d.b0.w + d.sx * lx)
      if (d.sy) b.h = Math.max(MIN_PX, d.b0.h + d.sy * ly)
      const ux = (d.sx * (b.w - d.b0.w)) / 2, uy = (d.sy * (b.h - d.b0.h)) / 2
      b.cx += ux * c - uy * s; b.cy += ux * s + uy * c
    }
    if (d.mode === "rot") {
      let a = normAngle((Math.atan2(p.y - b.cy, p.x - b.cx) * 180) / Math.PI + 90)
      if (ev.shiftKey) a = Math.round(a / 15) * 15
      else if (Math.abs(a) < 4) a = 0
      b.a = a
    }
    if (d.mode === "draw") {
      b.cx = (d.p0.x + p.x) / 2; b.cy = (d.p0.y + p.y) / 2; b.w = Math.abs(dx); b.h = Math.abs(dy); b.a = 0
    }
    b.cx = Math.min(Math.max(b.cx, 0), d.W); b.cy = Math.min(Math.max(b.cy, 0), d.H)
    Object.assign(this.tpl().boxes[d.i], fromPx(b, d.W, d.H))
    this.paint()
    this.syncFields()
  }

  dragEnd(st) {
    const d = this.drag
    this.drag = null
    st.onpointermove = st.onpointerup = st.onpointercancel = null
    if (!d) return
    const b = this.tpl().boxes[d.i]
    if (d.mode === "draw" && (b.w * d.W < MIN_PX * 2 || b.h * d.H < MIN_PX * 2)) {
      // A click (or tiny drag) on empty image: drop a default-sized box centred there.
      Object.assign(b, { w: 0.5, h: 0.18 })
      b.x = r3(Math.min(Math.max(d.p0.x / d.W - 0.25, 0), 0.5)); b.y = r3(Math.min(Math.max(d.p0.y / d.H - 0.09, 0), 0.82))
      return this.changed(true)
    }
    if (d.moved || d.mode === "draw") this.changed(d.mode === "draw")
  }

  // ---------- events ----------
  onClick(e) {
    const el = e.target.closest("[data-act]")
    if (!el) return
    const { act, arg } = el.dataset, i = Number(el.dataset.i), tpl = this.tpl()
    switch (act) {
      case "pick":
        if (this.s.variant === "B" && this.s.dirty && !confirm("Discard unsaved changes?")) return
        if (this.s.variant === "B") this.discard()
        this.pick(arg); this.s.screen = "edit"; return this.show()
      case "back":
        if (this.s.dirty && !confirm("Discard unsaved changes?")) return
        this.discard(); this.s.screen = "list"; return this.show()
      case "filter":
        this.s.filter = arg
        if (this.s.variant === "C") { if (this.s.dirty) this.discard(); this.buildQueue() }
        return this.show()
      case "sample": this.s.sample = arg; return this.show()
      case "sel-box": this.s.boxIndex = i; return this.show()
      case "add-box": {
        const n = tpl.boxes.length
        tpl.boxes.push(box(0.15, r3(Math.min(0.4 + n * 0.05, 0.78)), 0.7, 0.2))
        this.s.boxIndex = n; return this.changed(true)
      }
      case "dup-box": tpl.boxes.push({ ...tpl.boxes[i], x: r3(Math.min(tpl.boxes[i].x + 0.04, 0.9)), y: r3(Math.min(tpl.boxes[i].y + 0.04, 0.9)) }); this.s.boxIndex = tpl.boxes.length - 1; return this.changed(true)
      case "del-box": tpl.boxes.splice(i, 1); this.s.boxIndex = tpl.boxes.length ? Math.min(i, tpl.boxes.length - 1) : null; return this.changed(true)
      case "preset": tpl.boxes = PRESETS.find((p) => p[0] === arg)[2](); this.s.boxIndex = 0; return this.changed(true)
      case "clear": tpl.boxes = []; this.s.boxIndex = null; return this.changed(true)
      case "style": Object.assign(tpl.boxes[i], arg === "black" ? { color: "black", font: "thin" } : { color: "white", font: "thick" }); return this.changed(true)
      case "hide":
        tpl.hidden = !tpl.hidden
        if (this.s.variant === "C") { this.s.dirty = false; return this.next(true) }
        return this.changed(true)
      case "delete-tpl": return this.deleteTpl()
      case "save": tpl.reviewed = true; this.snapshot = structuredClone(tpl); this.s.dirty = false; return this.show()
      case "approve": tpl.reviewed = true; this.s.approved++; this.s.dirty = false; return this.next(false)
      case "skip": this.discard(); return this.next(false)
      case "restart": this.buildQueue(); return this.show()
    }
  }

  onInput(e) {
    const el = e.target
    if (el.matches("[data-query]")) { this.s.query = el.value; return this.s.variant === "A" ? this.gridA() : this.listB() }
    if (el.matches("[data-name]")) { this.tpl().name = el.value; return this.changed() }
    if (el.matches("[data-field]")) {
      const v = parseFloat(el.value)
      if (Number.isNaN(v)) return
      const b = this.tpl().boxes[Number(el.dataset.i)], k = el.dataset.field
      b[k] = k === "angle" ? normAngle(v) : r3(v / 100)
      this.changed()
    }
  }

  onChange(e) {
    if (e.target.matches("[data-qfilter]")) { this.s.filter = e.target.value; if (this.s.dirty) this.discard(); this.buildQueue(); this.show() }
  }

  deleteTpl() {
    const tpl = this.tpl()
    if (!confirm(`Delete "${tpl.name}" from the Template Library for good? Memes already made from it are kept.`)) return
    const idx = this.s.templates.indexOf(tpl)
    this.s.templates.splice(idx, 1)
    if (this.s.variant === "C") { this.s.dirty = false; this.snapshot = null; return this.next(true) }
    if (this.s.variant === "B") { this.s.screen = "list"; this.s.selectedId = null; this.s.dirty = false; return this.show() }
    const nxt = this.visible()[0] || this.s.templates[0]
    this.pick(nxt?.id); this.show()
  }

  // ---------- A: studio ----------
  variantA() {
    const tpl = this.tpl()
    this.rootTarget.innerHTML = `<div class="pab-a">
      <aside class="pab-a-lib">
        <h2>Template Library</h2>
        <input type="search" data-query placeholder="Search Templates" value="${esc(this.s.query)}">
        ${this.filterChips()}
        <div class="pab-a-grid" data-grid></div>
      </aside>
      <main class="pab-a-main">${tpl ? `
        <div class="pab-toolbar">
          <button type="button" data-act="add-box">+ Text Box</button>
          <button type="button" data-act="preset" data-arg="tb">Reset to top &amp; bottom</button>
          ${this.sampleSeg()}
          <span class="pab-saved" data-saved></span>
        </div>
        ${this.stage(tpl, "calc(100dvh - 150px)")}
        <p class="pab-hint">Drag a box to move it · square handles resize · round knob rotates (Shift snaps to 15°, near 0° snaps flat) · click empty image to deselect</p>`
        : `<p class="pab-hint">Pick a Template.</p>`}
      </main>
      <aside class="pab-a-insp" data-insp></aside>
    </div>`
    this.gridA()
    this.inspectorA()
  }

  gridA() {
    const g = this.rootTarget.querySelector("[data-grid]")
    if (!g) return
    const list = this.visible()
    g.innerHTML = list.length ? list.map((t) => `
      <button type="button" class="pab-thumb ${t.id === this.s.selectedId ? "on" : ""} ${t.hidden ? "is-hidden" : ""}" data-act="pick" data-arg="${t.id}">
        <img src="${t.url}" alt="" loading="lazy"><em>${esc(t.name)}</em><span class="pab-badges">${this.badges(t)}</span></button>`).join("")
      : `<p class="pab-hint">Nothing matches.</p>`
  }

  inspectorA() {
    const el = this.rootTarget.querySelector("[data-insp]")
    const tpl = this.tpl()
    if (!el || !tpl) return
    const b = this.sel(), i = this.s.boxIndex
    el.innerHTML = `
      <section><h3>Template</h3>
        <label class="pab-lbl">Name<input data-name value="${esc(tpl.name)}"></label>
        <p class="pab-meta">${esc(tpl.source)} · used in ${tpl.uses} Meme${tpl.uses === 1 ? "" : "s"} · ${tpl.reviewed ? "reviewed" : "<b class='warn'>not reviewed</b>"}</p>
      </section>
      <section><h3>Text Boxes</h3>
        <div class="pab-boxlist">${tpl.boxes.map((bx, n) => `<button type="button" data-act="sel-box" data-i="${n}" class="${n === i ? "on" : ""}">${n + 1}</button>`).join("")}
          <button type="button" data-act="add-box">+</button></div>
        ${b ? `
          <div class="pab-nums">${[["x", "X %"], ["y", "Y %"], ["w", "Width %"], ["h", "Height %"], ["angle", "Angle °"]].map(([k, n]) =>
            `<label class="pab-lbl">${n}<input type="number" step="${k === "angle" ? 1 : 0.5}" data-field="${k}" data-i="${i}"></label>`).join("")}</div>
          <label class="pab-lbl">Text style</label>${this.styleSeg(i, b)}
          <p class="pab-meta">Sample fits at <span data-fit="${i}"></span></p>
          <div class="pab-row"><button type="button" data-act="dup-box" data-i="${i}">Duplicate</button>
            <button type="button" class="danger" data-act="del-box" data-i="${i}">Remove box</button></div>`
          : `<p class="pab-hint">${tpl.boxes.length ? "Select a box." : "No Text Boxes: Players can't caption this. Add one."}</p>`}
      </section>
      <section><h3>Library</h3>
        <div class="pab-row"><button type="button" data-act="hide">${tpl.hidden ? "Unhide (deal again)" : "Hide from Hands"}</button>
          <button type="button" class="danger" data-act="delete-tpl">Delete Template</button></div>
      </section>`
  }

  // ---------- B: phone form ----------
  variantB() {
    if (this.s.screen === "list" || !this.tpl()) {
      this.rootTarget.innerHTML = `<div class="pab-b">
        <header class="pab-b-head"><strong>Admin · Templates</strong></header>
        <input type="search" data-query placeholder="Search Templates" value="${esc(this.s.query)}">
        ${this.filterChips()}
        <div class="pab-b-list" data-list></div></div>`
      return this.listB()
    }
    const tpl = this.tpl()
    this.rootTarget.innerHTML = `<div class="pab-b">
      <header class="pab-b-head"><button type="button" class="pab-link" data-act="back">‹ Templates</button>
        <strong>${esc(tpl.name)}</strong><span class="pab-dot" data-dirty title="unsaved">●</span></header>
      ${this.stage(tpl, "45dvh")}
      ${this.sampleSeg()}
      <h3>Start from a layout</h3>
      <div class="pab-presets">${PRESETS.map(([k, n, f]) => `<button type="button" data-act="preset" data-arg="${k}">
        <span class="pab-mini">${f().map((b) => `<i style="left:${b.x * 100}%;top:${b.y * 100}%;width:${b.w * 100}%;height:${b.h * 100}%"></i>`).join("")}</span>${n}</button>`).join("")}</div>
      <h3>Text Boxes <small>tap one on the image or below</small></h3>
      ${tpl.boxes.map((b, i) => this.cardB(b, i)).join("") || `<p class="pab-hint">No Text Boxes: Players can't caption this.</p>`}
      <button type="button" class="pab-ghost" data-act="add-box">+ Add Text Box</button>
      <h3>Template</h3>
      <label class="pab-lbl">Name<input data-name value="${esc(tpl.name)}"></label>
      <p class="pab-meta">${esc(tpl.source)} · used in ${tpl.uses} Memes</p>
      <div class="pab-row"><button type="button" data-act="hide">${tpl.hidden ? "Unhide" : "Hide from Hands"}</button>
        <button type="button" class="danger" data-act="delete-tpl">Delete</button></div>
      <button type="button" class="pab-btn pab-b-save" data-act="save">Save changes</button></div>`
  }

  cardB(b, i) {
    const open = i === this.s.boxIndex
    return `<div class="pab-card ${open ? "open" : ""}">
      <button type="button" class="pab-card-head" data-act="sel-box" data-i="${i}"><b>Box ${i + 1}</b>
        <span>${r1(b.x * 100)}, ${r1(b.y * 100)} · ${r1(b.w * 100)}×${r1(b.h * 100)}%${b.angle ? ` · ${r1(b.angle)}°` : ""}</span><span>${open ? "▾" : "▸"}</span></button>
      ${open ? `<div class="pab-card-body">
        ${[["x", "Left", 0, 100], ["y", "Top", 0, 100], ["w", "Width", 2, 100], ["h", "Height", 2, 100], ["angle", "Angle", -45, 45]].map(([k, n, lo, hi]) => `
          <label class="pab-slider">${n} <output data-out></output><input type="range" min="${lo}" max="${hi}" step="0.5" data-field="${k}" data-i="${i}"></label>`).join("")}
        ${this.styleSeg(i, b)}
        <p class="pab-meta">Sample fits at <span data-fit="${i}"></span></p>
        <button type="button" class="pab-link danger" data-act="del-box" data-i="${i}">Remove Box ${i + 1}</button></div>` : ""}
    </div>`
  }

  listB() {
    const l = this.rootTarget.querySelector("[data-list]")
    if (!l) return
    l.innerHTML = this.visible().map((t) => `
      <button type="button" class="pab-b-row ${t.hidden ? "is-hidden" : ""}" data-act="pick" data-arg="${t.id}">
        <img src="${t.url}" alt="" loading="lazy"><span><b>${esc(t.name)}</b><span class="pab-badges">${this.badges(t)}</span></span><span>›</span></button>`).join("")
      || `<p class="pab-hint">Nothing matches.</p>`
  }

  // ---------- C: review queue ----------
  buildQueue() {
    this.s.queue = this.visible().map((t) => t.id)
    this.s.pos = 0
    this.s.queue.length ? this.pick(this.s.queue[0]) : (this.s.selectedId = null)
  }

  next(removed) {
    // removed: the current Template left the queue (hidden/deleted) without approval
    if (removed) this.s.queue.splice(this.s.pos, 1); else this.s.pos++
    const id = this.s.queue[this.s.pos]
    id && this.tpl(id) ? this.pick(id) : (this.s.selectedId = null)
    this.show()
  }

  variantC() {
    const tpl = this.tpl()
    const filterSel = `<select data-qfilter>${FILTERS.map(([k, n]) => `<option value="${k}" ${this.s.filter === k ? "selected" : ""}>${n}</option>`).join("")}</select>`
    if (!tpl) {
      this.rootTarget.innerHTML = `<div class="pab-c pab-c-done"><h2>All caught up</h2>
        <p>${this.s.approved} Template${this.s.approved === 1 ? "" : "s"} approved this session.</p>
        <p>Queue: ${filterSel} <button type="button" data-act="restart">Start again</button></p></div>`
      return
    }
    this.rootTarget.innerHTML = `<div class="pab-c">
      <header class="pab-c-head">
        <span>Review queue ${filterSel} <b>${this.s.pos + 1} / ${this.s.queue.length}</b></span>
        <input data-name value="${esc(tpl.name)}" aria-label="Template name">
        <span class="pab-meta">${esc(tpl.source)} · used ${tpl.uses}× ${tpl.hidden ? "· <b class='warn'>hidden</b>" : ""}</span>
      </header>
      <div class="pab-c-body">
        <div class="pab-c-stagewrap">${this.stage(tpl, "calc(100dvh - 300px)")}
          <p class="pab-c-info" data-info></p></div>
        <aside class="pab-keys">
          <h3>Mouse / touch</h3>
          <p>Drag on empty image: <b>draw a box</b><br>Click empty image: default box<br>Drag a box: move</p>
          <h3>Keyboard (box selected)</h3>
          <dl>
            <dt>← ↑ → ↓</dt><dd>nudge 0.5% (Shift 5%)</dd>
            <dt>Alt + arrows</dt><dd>resize</dd>
            <dt>[ ]</dt><dd>rotate 1° (Shift 15°)</dd><dt>0</dt><dd>angle flat</dd>
            <dt>Tab</dt><dd>next box</dd><dt>T</dt><dd>white / black text</dd>
            <dt>⌫</dt><dd>remove box</dd><dt>Esc</dt><dd>deselect</dd>
          </dl>
          <h3>Template</h3>
          <dl><dt>S</dt><dd>cycle sample text</dd><dt>X</dt><dd>clear all boxes</dd><dt>R</dt><dd>reset to top &amp; bottom</dd>
            <dt>H</dt><dd>hide + next</dd><dt>J</dt><dd>skip (discard)</dd><dt>Enter</dt><dd>approve + next</dd></dl>
        </aside>
      </div>
      <footer class="pab-c-bar">
        ${this.sampleSeg()}
        <button type="button" data-act="clear">Clear <kbd>X</kbd></button>
        <button type="button" data-act="hide">${tpl.hidden ? "Unhide" : "Hide"} <kbd>H</kbd></button>
        <button type="button" class="danger" data-act="delete-tpl">Delete</button>
        <span class="pab-dot" data-dirty>● unsaved</span>
        <button type="button" data-act="skip">Skip <kbd>J</kbd></button>
        <button type="button" class="pab-btn" data-act="approve">Approve &amp; next <kbd>↵</kbd></button>
      </footer></div>`
  }

  infoC() {
    const tpl = this.tpl(), b = this.sel()
    if (!tpl) return ""
    if (!b) return tpl.boxes.length ? `${tpl.boxes.length} boxes · Tab to select one` : `<b class="warn">No Text Boxes.</b> Drag on the image to draw one.`
    const f = this.fits?.[this.s.boxIndex]
    return `<b>Box ${this.s.boxIndex + 1}/${tpl.boxes.length}</b> · at ${r1(b.x * 100)}%, ${r1(b.y * 100)}% · ${r1(b.w * 100)} × ${r1(b.h * 100)}% · ${r1(b.angle)}° · ${b.color === "black" ? "black" : "white outlined"}${f ? ` · sample ${f.size}px${f.floor ? " <b class='warn'>overflows</b>" : ""}` : ""}`
  }

  keyC(e) {
    if (!this.tpl() || e.target.closest("input, textarea, select")) {
      if (e.key === "Escape") e.target.blur?.()
      return
    }
    const tpl = this.tpl(), b = this.sel(), k = e.key
    const step = e.shiftKey ? 0.05 : 0.005
    const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }
    let handled = true
    if (arrows[k] && b) {
      const [ax, ay] = arrows[k]
      if (e.altKey) { b.w = r3(Math.max(0.02, b.w + ax * step)); b.h = r3(Math.max(0.02, b.h + ay * step)) }
      else { b.x = r3(b.x + ax * step); b.y = r3(b.y + ay * step) }
      this.changed()
    } else if ((k === "[" || k === "]" || k === "{" || k === "}") && b) {
      b.angle = r1(normAngle(b.angle + (k === "[" || k === "{" ? -1 : 1) * (e.shiftKey ? 15 : 1))); this.changed()
    } else if (k === "0" && b) { b.angle = 0; this.changed() }
    else if (k === "Tab" && tpl.boxes.length) {
      const n = tpl.boxes.length
      this.s.boxIndex = this.s.boxIndex == null ? 0 : (this.s.boxIndex + (e.shiftKey ? n - 1 : 1)) % n
      this.afterSelect()
    } else if ((k === "Backspace" || k === "Delete") && b) {
      tpl.boxes.splice(this.s.boxIndex, 1); this.s.boxIndex = tpl.boxes.length ? Math.min(this.s.boxIndex, tpl.boxes.length - 1) : null; this.changed(true)
    } else if (k === "Escape") { this.s.boxIndex = null; this.afterSelect() }
    else if (k === "t" && b) { Object.assign(b, b.color === "black" ? { color: "white", font: "thick" } : { color: "black", font: "thin" }); this.changed() }
    else if (k === "s") { const ks = Object.keys(SAMPLES); this.s.sample = ks[(ks.indexOf(this.s.sample) + 1) % ks.length]; this.show() }
    else if (k === "x") { tpl.boxes = []; this.s.boxIndex = null; this.changed(true) }
    else if (k === "r") { tpl.boxes = TOP_BOTTOM(); this.s.boxIndex = 0; this.changed(true) }
    else if (k === "h") this.rootTarget.querySelector("[data-act=hide]").click()
    else if (k === "j") this.rootTarget.querySelector("[data-act=skip]").click()
    else if (k === "Enter") this.rootTarget.querySelector("[data-act=approve]").click()
    else handled = false
    if (handled) e.preventDefault()
  }
}
