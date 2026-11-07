import { Controller } from "@hotwired/stimulus"

// Counts down to an absolute deadline. The offset between the server's clock and this device's is taken on
// connect (a phase broadcast replaces the element, so connect runs again), and every tick redraws from the
// deadline rather than decrementing. At zero it says "time's up" and waits for the server.
export default class extends Controller {
  static targets = ["bar", "label"]
  static values = { deadline: String, serverNow: String }

  connect() {
    const serverNow = Date.parse(this.serverNowValue)
    this.offset = serverNow - Date.now()
    this.deadline = Date.parse(this.deadlineValue)
    this.total = this.deadline - serverNow
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = Math.max(0, this.deadline - (Date.now() + this.offset))
    if (this.hasBarTarget) {
      const fraction = this.total > 0 ? Math.min(1, remaining / this.total) : 0
      this.barTarget.style.width = `${fraction * 100}%`
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = remaining > 0 ? `${Math.ceil(remaining / 1000)}s` : "Time's up"
    }
    if (remaining === 0) clearInterval(this.timer)
  }
}
