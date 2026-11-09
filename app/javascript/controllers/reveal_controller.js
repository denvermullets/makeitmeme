import { Controller } from "@hotwired/stimulus"
import { revealSchedule } from "reveal_schedule"

// Reveals Scoreboard places last to first on the shared schedule (ADR 0001). The server renders every row;
// this only hides rows not yet due, so without JavaScript the full Scoreboard shows. The offset between the
// server's clock and this device's is taken on connect, like the countdown. Rows are hidden with the `hidden`
// attribute, so a tab switch that only toggles visibility never reconnects the controller or restarts it.
export default class extends Controller {
  static targets = ["row"]
  static values = { finishedAt: String, serverNow: String }

  connect() {
    this.offset = Date.parse(this.serverNowValue) - Date.now()
    this.places = [...new Set(this.rowTargets.map((row) => Number(row.dataset.place)))].sort((a, b) => b - a)
    this.step()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  step() {
    const now = Date.now() + this.offset
    const { showing, nextAt } = revealSchedule({ finishedAt: this.finishedAtValue, serverNow: now, places: this.places })
    this.rowTargets.forEach((row) => {
      row.hidden = !showing.includes(Number(row.dataset.place))
    })
    if (nextAt === null) return
    this.timer = setTimeout(() => this.step(), Math.max(0, Date.parse(nextAt) - now))
  }
}
