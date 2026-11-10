import { Controller } from "@hotwired/stimulus"

// Add to library saves any pending edits first: it flushes the Text Box editor's autosaver, and only submits once
// everything is saved (a failed save stays on the page, where the editor shows "Couldn't save" and Retry).
export default class extends Controller {
  async submit(event) {
    if (this.submitting) return
    event.preventDefault()
    this.submitting = true
    const saver = this.editorSaver()
    if (saver && !(await this.settle(saver))) {
      this.submitting = false
      return
    }
    this.element.submit()
  }

  editorSaver() {
    const editor = document.querySelector("[data-text-box-editor]")
    return editor && this.application.getControllerForElementAndIdentifier(editor, "text-box-editor")?.saver
  }

  async settle(saver) {
    for (let attempt = 0; attempt < 5; attempt++) {
      await saver.flush()
      while (saver.inFlight) await new Promise((resolve) => setTimeout(resolve, 50))
      if (!saver.dirty && !saver.timer) return true
    }
    return false
  }
}
