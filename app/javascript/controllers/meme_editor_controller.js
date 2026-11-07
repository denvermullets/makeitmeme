import { Controller } from '@hotwired/stimulus'
import { DirectUpload } from '@rails/activestorage'
import { drawMeme, FONT_FAMILY } from 'meme_render'
import { msUntilZero, submissionBody, failureMessage } from 'meme_submit'

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
// Submit (and the auto-submit at the client's zero) redraws without outlines, bakes the same canvas to a PNG,
// direct-uploads it and posts the blob's signed_id with the Template id and caption texts.
export default class extends Controller {
  static targets = ['loading', 'body', 'canvas', 'fields', 'position', 'name', 'previousButton', 'nextButton',
    'error', 'submitButton', 'submitted', 'submittedImage']
  static values = { hand: Array, submitUrl: String, directUploadUrl: String, deadline: String, serverNow: String }

  async connect() {
    this.connectedAt = Date.now()
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
    this.armAutoSubmit()
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

  // At zero the Template on screen goes in as it is, blank or not, unless the Player already submitted.
  armAutoSubmit() {
    const ms = msUntilZero(this.deadlineValue, this.serverNowValue, this.connectedAt, Date.now())
    if (ms !== null) this.autoTimer = setTimeout(() => this.submit(), ms)
  }

  async submit() {
    if (this.busy || this.submittedMeme || !this.images?.length) return
    this.busy = true
    this.submitButtonTarget.disabled = true
    this.errorTarget.hidden = true
    // Capture what is on screen now: the Player may keep editing while the upload runs.
    const { templateId, captions, boxCount } = { templateId: this.templateId, captions: [...this.captions],
                                                  boxCount: this.template.boxes.length }
    let blob
    try {
      this.redraw({ outlines: false })
      blob = await this.bake()
      const signedId = await this.upload(blob)
      await this.post(submissionBody(signedId, templateId, captions, boxCount))
      this.showSubmitted(blob)
    } catch (error) {
      console.error('Meme submit failed', error)
      this.errorTarget.textContent = failureMessage(error)
      this.errorTarget.hidden = false
      this.submitButtonTarget.disabled = false
      this.redraw()
    } finally {
      this.busy = false
    }
  }

  // Same canvas as the preview. toBlob can throw SecurityError (tainted canvas) or hand back null.
  bake() {
    return new Promise((resolve, reject) => {
      try {
        this.canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('The image could not be made'))), 'image/png')
      } catch (error) {
        reject(error)
      }
    })
  }

  upload(blob) {
    const file = new File([blob], 'meme.png', { type: 'image/png' })
    return new Promise((resolve, reject) => {
      new DirectUpload(file, this.directUploadUrlValue).create((error, uploaded) => {
        if (error) reject(new Error(`Direct upload failed: ${error}`))
        else resolve(uploaded.signed_id)
      })
    })
  }

  async post(body) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.submitUrlValue, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrf },
      body: JSON.stringify(body),
    })
    if (response.ok) return
    const json = await response.json().catch(() => ({}))
    throw Object.assign(new Error(`Submit failed (${response.status})`), { serverErrors: json.errors })
  }

  showSubmitted(blob) {
    this.submittedMeme = true
    clearTimeout(this.autoTimer)
    this.submittedImageTarget.src = URL.createObjectURL(blob)
    this.bodyTarget.hidden = true
    this.submittedTarget.hidden = false
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    clearTimeout(this.autoTimer)
  }
}
