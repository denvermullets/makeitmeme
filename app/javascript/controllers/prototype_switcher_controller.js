// PROTOTYPE (MEME-5), throwaway. Floating variant switcher; only mounted on dev-only prototype routes.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { variants: Object, current: String }

  connect() {
    this.keys = Object.keys(this.variantsValue)
    this.labelTarget.textContent = `${this.currentValue} (${this.variantsValue[this.currentValue]})`
    this.onKey = (e) => {
      if (e.defaultPrevented || e.target.closest("input, textarea, select, [contenteditable]")) return
      if (e.key === "ArrowLeft") this.prev()
      if (e.key === "ArrowRight") this.next()
    }
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() { document.removeEventListener("keydown", this.onKey) }

  prev() { this.go(-1) }
  next() { this.go(1) }

  go(step) {
    const i = (this.keys.indexOf(this.currentValue) + step + this.keys.length) % this.keys.length
    const url = new URL(window.location)
    url.searchParams.set("variant", this.keys[i])
    window.location.replace(url)
  }
}
