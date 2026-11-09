import { Controller } from "@hotwired/stimulus"
import { Autosaver } from "autosaver"

// Text Box editor. State is `this.boxes` (the ordered array, same shape the server stores); every change goes
// through `changed()`, which schedules an autosave. The stage, handles, add/duplicate/remove and preview extend
// this controller by mutating `this.boxes`, then calling `changed()` (and `syncFields()` while dragging).
const STYLES = { white: { color: "white", font: "thick" }, black: { color: "black", font: "thin" } }
const LABELS = { saving: "Saving…", saved: "Saved", error: "Couldn't save" }

export default class extends Controller {
  static targets = ["row", "status", "retry", "errors"]
  static values = { url: String, boxes: Array }

  connect() {
    this.boxes = this.boxesValue.map((box) => ({ ...box }))
    this.saver = new Autosaver({ send: () => this.save(), onStatus: (status) => this.showStatus(status) })
  }

  disconnect() {
    this.saver?.flush()
  }

  // Numeric field edited (percent for x/y/w/h, degrees for angle).
  edit(event) {
    const input = event.target
    const index = Number(input.closest("[data-index]").dataset.index)
    const value = input.value.trim() === "" ? NaN : Number(input.value)
    this.boxes[index][input.dataset.field] = input.dataset.unit === "percent" ? value / 100 : value
    this.changed()
  }

  style(event) {
    const index = Number(event.target.closest("[data-index]").dataset.index)
    Object.assign(this.boxes[index], STYLES[event.target.value])
    this.changed()
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
