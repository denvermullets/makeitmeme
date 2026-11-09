// Debounced, serialised autosave. Edits call schedule(); after `delay` ms of quiet it calls send(), and never
// runs two sends at once. Each send reads the latest state, so the last edit wins and an older response can
// never overwrite newer state. Status: 'saving' | 'saved' | 'error'.
export class Autosaver {
  constructor({ send, onStatus = () => {}, delay = 400 }) {
    this.send = send
    this.onStatus = onStatus
    this.delay = delay
    this.timer = null
    this.inFlight = false
    this.dirty = false
  }

  schedule() {
    this.dirty = true
    this.onStatus('saving')
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.flush(), this.delay)
  }

  // Saves now (drag end, retry, teardown). Safe to call any time.
  async flush() {
    clearTimeout(this.timer)
    this.timer = null
    if (this.inFlight || !this.dirty) return
    this.inFlight = true
    this.dirty = false
    this.onStatus('saving')
    let failed = false
    try {
      await this.send()
    } catch (error) {
      failed = true
    }
    this.inFlight = false
    if (failed) {
      this.dirty = true
      this.onStatus('error')
    } else if (this.dirty) {
      this.timer = setTimeout(() => this.flush(), this.delay)
    } else {
      this.onStatus('saved')
    }
  }

  retry() {
    this.dirty = true
    return this.flush()
  }
}
