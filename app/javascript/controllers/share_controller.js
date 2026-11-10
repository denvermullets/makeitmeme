import { Controller } from "@hotwired/stimulus"

// Shares the Recap link through the device share sheet where there is one, otherwise copies it to the clipboard.
// The url value may be a path (broadcast renders have no host), so it is resolved against this page's origin.
export default class extends Controller {
  static targets = ["button", "status", "link"]
  static values = { url: String, title: String }

  connect() {
    if (this.hasLinkTarget) this.linkTarget.textContent = this.absoluteUrl
  }

  get absoluteUrl() {
    return new URL(this.urlValue, window.location.origin).href
  }

  async share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: this.titleValue, url: this.absoluteUrl })
      } catch (error) {
        if (error.name !== "AbortError") await this.copy()
      }
    } else {
      await this.copy()
    }
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.absoluteUrl)
      this.showStatus("Link copied")
    } catch {
      this.showStatus("Copy the link above")
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    clearTimeout(this.statusTimer)
    this.statusTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
  }

  disconnect() {
    clearTimeout(this.statusTimer)
  }
}
