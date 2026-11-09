import { Controller } from "@hotwired/stimulus"

// Shares the url through the device share sheet where there is one, otherwise copies it to the clipboard.
export default class extends Controller {
  static targets = ["button", "status"]
  static values = { url: String, title: String }

  async share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: this.titleValue, url: this.urlValue })
      } catch (error) {
        if (error.name !== "AbortError") await this.copy()
      }
    } else {
      await this.copy()
    }
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.say("Link copied")
    } catch {
      this.say("Copy the link above")
    }
  }

  say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
