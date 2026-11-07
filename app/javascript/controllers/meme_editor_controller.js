import { Controller } from '@hotwired/stimulus'
import { drawMeme, FONT_FAMILY } from 'meme_render'

const MAX_CHARS = 80
const images = {}

function loadImage(url) {
  images[url] ||= new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = url
  })
  return images[url]
}

// The Meme editor: one Template of the Player's Hand at a time, a field per Text Box, live canvas preview.
// Submit (MEME-26) and the auto-submit at zero read `canvas`, `templateId` and `captions`, then call
// `redraw({ outlines: false })` before `canvas.toBlob`.
export default class extends Controller {
  static targets = ['loading', 'body', 'canvas', 'fields', 'position', 'name', 'previousButton', 'nextButton']
  static values = { hand: Array }

  async connect() {
    this.index = 0
    this.captions = []
    this.images = []
    try {
      await document.fonts.load(`40px ${FONT_FAMILY}`, 'ABC')
    } catch (error) {
      console.warn('Anton failed to load, falling back', error)
    }
    this.images = await Promise.all(this.handValue.map((template) => loadImage(template.url)))
    if (!this.element.isConnected) return
    this.loadingTarget.hidden = true
    this.bodyTarget.hidden = false
    this.show()
  }

  get template() { return this.handValue[this.index] }
  get templateId() { return this.template?.id }
  get canvas() { return this.canvasTarget }

  previous() { this.go(-1) }
  next() { this.go(1) }

  // Moving to another Template discards the caption.
  go(step) {
    const index = this.index + step
    if (index < 0 || index >= this.handValue.length) return
    this.index = index
    this.captions = []
    this.show()
  }

  input(event) {
    this.captions[Number(event.target.dataset.box)] = event.target.value
    this.schedule()
  }

  show() {
    const template = this.template
    this.positionTarget.textContent = `${this.index + 1} / ${this.handValue.length}`
    this.nameTarget.textContent = template.name
    this.previousButtonTarget.disabled = this.index === 0
    this.nextButtonTarget.disabled = this.index === this.handValue.length - 1
    this.fieldsTarget.replaceChildren(...template.boxes.map((_, n) => this.field(n)))
    this.redraw()
  }

  field(n) {
    const label = document.createElement('label')
    label.textContent = `Box ${n + 1}`
    const input = document.createElement('input')
    input.type = 'text'
    input.maxLength = MAX_CHARS
    input.placeholder = `Caption for box ${n + 1}`
    input.dataset.box = n
    input.dataset.action = 'input->meme-editor#input'
    label.append(input)
    return label
  }

  schedule() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.redraw())
  }

  redraw({ outlines = true } = {}) {
    drawMeme(this.canvasTarget, this.template, this.images[this.index], this.captions, { outlines })
  }

  disconnect() { cancelAnimationFrame(this.frame) }
}
