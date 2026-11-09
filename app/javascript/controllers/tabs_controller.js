import { Controller } from "@hotwired/stimulus"

// Client-only tabs: shows one panel at a time by toggling `hidden`. Makes no request and touches nothing else,
// so a running reveal is never restarted. Without JS every panel stays visible.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.show(0)
  }

  select(event) {
    this.show(this.tabTargets.indexOf(event.currentTarget))
  }

  show(index) {
    this.tabTargets.forEach((tab, i) => tab.setAttribute("aria-selected", String(i === index)))
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
  }
}
