import { Controller } from "@hotwired/stimulus"

// Submits its form when a field changes, so edits save without a Save button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
