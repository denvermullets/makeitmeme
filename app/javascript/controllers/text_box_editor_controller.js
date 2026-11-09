import { Controller } from "@hotwired/stimulus"
import { Autosaver } from "autosaver"
import { render, canvasSize, FONT_FAMILY } from "meme_render"
import { sampleCaptions, fitSummary } from "sample_preview"
import { HANDLE_DIRS, toPx, fromPx, dragBox } from "text_box_geometry"
import { addBox, duplicateBox, removeBox, reorderBox, resetBoxes, canRemove, canMove, applyStyle, styleKey } from "text_box_list"

// Text Box editor. State is `this.boxes` (the ordered array, same shape the server stores); every change goes
// through `changed()`, which schedules an autosave. The stage, handles, add/duplicate/remove and preview extend
// this controller by mutating `this.boxes`, then calling `changed()` (and `syncFields()` while dragging).
const LABELS = { saving: "Saving…", saved: "Saved", error: "Couldn't save" }

export default class extends Controller {
  static targets = ["row", "status", "retry", "errors", "stage", "image", "overlay", "preview", "fits",
    "rows", "rowTemplate", "needsSelection", "removeButton", "earlierButton", "laterButton"]
  static values = { url: String, boxes: Array, image: String }

  connect() {
    this.boxes = this.boxesValue.map((box) => ({ ...box }))
    this.selected = null
    this.drag = null
    this.saver = new Autosaver({ send: () => this.save(), onStatus: (status) => this.showStatus(status) })
    this.loadImage()
    this.renderRows()
    this.renderStage()
    this.startPreview()
  }

  disconnect() {
    this.stopPreview()
    this.saver?.flush()
  }

  // crossOrigin must be set before src so the image stays usable for canvas previews (MEME-40).
  loadImage() {
    if (!this.hasImageTarget || !this.imageValue) return
    this.imageTarget.crossOrigin = "anonymous"
    this.imageTarget.addEventListener("load", () => {
      const { naturalWidth, naturalHeight } = this.imageTarget
      if (naturalWidth && naturalHeight) this.stageTarget.style.setProperty("--ar", `${naturalWidth} / ${naturalHeight}`)
      this.schedulePreview()
    })
    this.imageTarget.src = this.imageValue
  }

  // ---- Stage ----
  // The single place the stage is drawn from this.boxes. Boxes are positioned in percent so they follow the image at
  // any display size. Call it after any change to this.boxes or this.selected; it reuses elements (so an active drag
  // keeps working) and only creates or removes them when the box count changes.
  renderStage() {
    if (!this.hasOverlayTarget) return
    const overlay = this.overlayTarget
    while (overlay.children.length > this.boxes.length) overlay.lastElementChild.remove()
    while (overlay.children.length < this.boxes.length) overlay.append(this.buildBoxElement())
    this.boxes.forEach((box, index) => {
      const el = overlay.children[index]
      const finite = ["x", "y", "w", "h", "angle"].every((key) => Number.isFinite(box[key]))
      el.hidden = !finite
      if (!finite) return
      el.dataset.boxIndex = index
      el.classList.toggle("selected", index === this.selected)
      el.dataset.color = box.color
      el.querySelector(".tbe-num").textContent = index + 1
      Object.assign(el.style, {
        left: `${box.x * 100}%`, top: `${box.y * 100}%`, width: `${box.w * 100}%`, height: `${box.h * 100}%`,
        transform: `rotate(${box.angle}deg)`,
      })
    })
    this.rowTargets.forEach((row, index) => row.classList.toggle("selected", index === this.selected))
    this.renderActions()
    this.schedulePreview()
  }

  buildBoxElement() {
    const el = document.createElement("div")
    el.className = "tbe-box"
    el.innerHTML = '<span class="tbe-num"></span><i class="tbe-rotate" data-handle="rotate"></i>' +
      Object.entries(HANDLE_DIRS).map(([name, [sx, sy]]) =>
        `<i class="tbe-handle" data-handle="${name}" style="left:${(sx + 1) * 50}%;top:${(sy + 1) * 50}%"></i>`
      ).join("")
    return el
  }

  select(index) {
    if (this.selected === index) return
    this.selected = index
    this.renderStage()
  }

  selectRow(event) {
    this.select(Number(event.currentTarget.dataset.index))
  }

  // Mouse, touch and pen all arrive as pointer events. Press on a handle resizes/rotates, on a box moves it,
  // on empty image deselects.
  pointerDown(event) {
    if (event.button > 0) return
    const handleEl = event.target.closest("[data-handle]")
    const boxEl = event.target.closest("[data-box-index]")
    if (!boxEl) {
      this.select(null)
      return
    }
    const index = Number(boxEl.dataset.boxIndex)
    let mode = "move", handle = null
    if (handleEl && index === this.selected) {
      handle = handleEl.dataset.handle
      mode = handle === "rotate" ? "rotate" : "resize"
    }
    this.select(index)
    this.syncFields()
    event.preventDefault()
    const rect = this.stageTarget.getBoundingClientRect()
    if (!rect.width || !rect.height) return
    this.drag = {
      mode, handle, index, rect, W: rect.width, H: rect.height, moved: false,
      start: { x: event.clientX - rect.left, y: event.clientY - rect.top },
      b0: toPx(this.boxes[index], rect.width, rect.height),
    }
    this.stageTarget.setPointerCapture(event.pointerId)
    this.onMove = (e) => this.pointerMove(e)
    this.onEnd = () => this.pointerEnd()
    this.stageTarget.addEventListener("pointermove", this.onMove)
    this.stageTarget.addEventListener("pointerup", this.onEnd)
    this.stageTarget.addEventListener("pointercancel", this.onEnd)
  }

  pointerMove(event) {
    const d = this.drag
    if (!d) return
    const point = { x: event.clientX - d.rect.left, y: event.clientY - d.rect.top }
    const dx = point.x - d.start.x, dy = point.y - d.start.y
    if (Math.abs(dx) + Math.abs(dy) > 2) d.moved = true
    if (!d.moved) return
    const next = dragBox({ mode: d.mode, handle: d.handle, b0: d.b0, dx, dy, point, shift: event.shiftKey, W: d.W, H: d.H })
    Object.assign(this.boxes[d.index], fromPx(next, d.W, d.H))
    this.renderStage()
    this.syncFields()
  }

  pointerEnd() {
    const d = this.drag
    this.drag = null
    this.stageTarget.removeEventListener("pointermove", this.onMove)
    this.stageTarget.removeEventListener("pointerup", this.onEnd)
    this.stageTarget.removeEventListener("pointercancel", this.onEnd)
    if (d?.moved) this.changed()
  }

  // Numeric field edited (percent for x/y/w/h, degrees for angle).
  edit(event) {
    const input = event.target
    const index = Number(input.closest("[data-index]").dataset.index)
    const value = input.value.trim() === "" ? NaN : Number(input.value)
    this.boxes[index][input.dataset.field] = input.dataset.unit === "percent" ? value / 100 : value
    this.renderStage()
    this.changed()
  }

  style(event) {
    const index = Number(event.target.closest("[data-index]").dataset.index)
    this.boxes[index] = applyStyle(this.boxes[index], event.target.value)
    this.renderStage()
    this.changed()
  }

  // ---- Rows (MEME-39) ----
  // Rows are built here from this.boxes, never by the server. Call after the box count or order changes (not while
  // dragging; use syncFields for that).
  renderRows() {
    if (!this.hasRowsTarget) return
    this.rowsTarget.replaceChildren(...this.boxes.map((box, index) => {
      const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
      row.dataset.index = index
      row.querySelector("legend").textContent = `Box ${index + 1}`
      row.querySelector("select[data-field=style]").value = styleKey(box)
      return row
    }))
    this.syncFields()
  }

  // ---- Box actions (MEME-39) ----
  // Each applies a pure list operation (text_box_list.js), redraws rows and stage, and autosaves.
  addBox() { this.applyList(addBox(this.boxes)) }
  duplicateBox() { if (this.selected !== null) this.applyList(duplicateBox(this.boxes, this.selected)) }
  removeBox() { if (this.selected !== null && canRemove(this.boxes)) this.applyList(removeBox(this.boxes, this.selected)) }
  moveEarlier() { this.reorder(-1) }
  moveLater() { this.reorder(1) }
  resetBoxes() { this.applyList(resetBoxes()) }

  reorder(delta) {
    if (this.selected !== null && canMove(this.boxes, this.selected, delta)) {
      this.applyList(reorderBox(this.boxes, this.selected, delta))
    }
  }

  applyList({ boxes, selected }) {
    this.boxes = boxes.map((box) => ({ ...box }))
    this.selected = selected
    this.renderRows()
    this.renderStage()
    this.changed()
  }

  renderActions() {
    const has = this.selected !== null && this.selected !== undefined
    if (this.hasNeedsSelectionTarget) this.needsSelectionTargets.forEach((b) => (b.disabled = !has))
    if (this.hasRemoveButtonTarget) this.removeButtonTarget.disabled = !has || !canRemove(this.boxes)
    if (this.hasEarlierButtonTarget) this.earlierButtonTarget.disabled = !has || !canMove(this.boxes, this.selected, -1)
    if (this.hasLaterButtonTarget) this.laterButtonTarget.disabled = !has || !canMove(this.boxes, this.selected, 1)
  }

  changed() {
    this.saver.schedule()
  }

  // Pushes this.boxes into the numeric fields (for use while dragging).
  syncFields() {
    this.rowTargets.forEach((row, index) => {
      const box = this.boxes[index]
      row.querySelectorAll("input[data-field]").forEach((input) => {
        if (input === document.activeElement) return
        const value = input.dataset.unit === "percent" ? box[input.dataset.field] * 100 : box[input.dataset.field]
        input.value = Math.round(value * 10) / 10
      })
    })
  }

  // ---- Sample-text preview (MEME-40) ----
  // View-only: the level is never part of this.boxes, so it is never saved. Drawing goes through the shared render()
  // (no local fitting). Redraws are coalesced to one per animation frame so drags stay smooth, and nothing draws
  // until the self-hosted Anton font has loaded, so measurements never use a fallback font.
  startPreview() {
    this.sampleLevel = "off"
    this.fontReady = false
    this.previewFrame = null
    if (!this.hasPreviewTarget) return
    const ready = document.fonts?.load ? document.fonts.load(`40px ${FONT_FAMILY}`, "ABC") : Promise.resolve()
    Promise.resolve(ready).catch((error) => console.warn("Anton failed to load, falling back", error)).then(() => {
      this.fontReady = true
      this.schedulePreview()
    })
  }

  stopPreview() {
    if (this.previewFrame) cancelAnimationFrame(this.previewFrame)
    this.previewFrame = null
    this.fontReady = false
  }

  setSample(event) {
    this.sampleLevel = event.target.value
    this.schedulePreview()
  }

  schedulePreview() {
    if (!this.hasPreviewTarget || this.previewFrame) return
    this.previewFrame = requestAnimationFrame(() => {
      this.previewFrame = null
      this.drawPreview()
    })
  }

  drawPreview() {
    const canvas = this.previewTarget
    const img = this.imageTarget
    const on = this.sampleLevel !== "off"
    canvas.hidden = !on
    this.fitsTarget.hidden = !on
    if (!on) {
      this.fitsTarget.replaceChildren()
      return
    }
    if (!this.fontReady || !img.complete || !img.naturalWidth) return
    const { width, height } = canvasSize(img.naturalWidth, img.naturalHeight)
    if (canvas.width !== width) canvas.width = width
    if (canvas.height !== height) canvas.height = height
    const ctx = canvas.getContext("2d")
    ctx.clearRect(0, 0, width, height)
    // Boxes with non-numeric fields (mid-edit) get no caption; render() needs finite geometry.
    const finite = (box) => ["x", "y", "w", "h", "angle"].every((key) => Number.isFinite(box[key]))
    const captions = sampleCaptions(this.sampleLevel, this.boxes.length).map((text, i) => (finite(this.boxes[i]) ? text : ""))
    this.showFits(render(ctx, { image: img, width, height }, this.boxes, captions))
  }

  showFits(fits) {
    this.fitsTarget.replaceChildren(...fits.map((fit, index) => {
      const { text, warning } = fitSummary(fit)
      const li = Object.assign(document.createElement("li"), { textContent: `Box ${index + 1}: ${text || "n/a"}` })
      li.classList.toggle("warning", warning)
      return li
    }))
  }

  retry() {
    this.saver.retry()
  }

  async save() {
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content,
      },
      body: JSON.stringify({ text_boxes: this.boxes }),
    })
    const body = await response.json().catch(() => ({}))
    if (!response.ok) {
      this.showErrors(body.errors || [])
      throw new Error("save failed")
    }
    this.showErrors([])
    const reviewed = document.querySelector("[data-inspector-reviewed]")
    if (reviewed && body.reviewed_at) reviewed.textContent = `Reviewed ${body.reviewed_at.slice(0, 10)}`
  }

  showStatus(status) {
    this.statusTarget.textContent = LABELS[status] || ""
    this.statusTarget.dataset.status = status
    this.retryTarget.hidden = status !== "error"
  }

  showErrors(errors) {
    this.errorsTarget.replaceChildren(
      ...errors.map((message) => Object.assign(document.createElement("li"), { textContent: message }))
    )
  }
}
