import { Controller } from "@hotwired/stimulus"
import { saveMethod } from "meme_share"

// Progressive enhancement for a Meme's Save link: on devices that can share files,
// open the share sheet with the PNG. Anywhere else (or if fetching/sharing fails),
// the plain download link behaves as before.
export default class extends Controller {
  async save(event) {
    if (!navigator.share || !navigator.canShare) return
    event.preventDefault()
    const link = this.element
    try {
      const response = await fetch(link.href)
      if (!response.ok) throw new Error("fetch failed")
      const blob = await response.blob()
      const file = new File([blob], link.download, { type: "image/png" })
      if (saveMethod(navigator, file) !== "share") return this.download(link)
      await navigator.share({ files: [file] })
    } catch (error) {
      if (error && error.name === "AbortError") return // cancelled: do nothing
      this.download(link)
    }
  }

  download(link) {
    const a = document.createElement("a")
    a.href = link.href
    a.download = link.download
    document.body.appendChild(a)
    a.click()
    a.remove()
  }
}
