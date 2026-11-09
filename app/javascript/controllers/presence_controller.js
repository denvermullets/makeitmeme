import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

// Holds a presence subscription open while this Room page is on screen, so the server can count it.
export default class extends Controller {
  static values = { code: String }

  async connect() {
    this.subscription = await cable.subscribeTo({ channel: "RoomPresenceChannel", code: this.codeValue })
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }
}
