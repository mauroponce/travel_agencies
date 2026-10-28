import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "editor", "photo", "placeholder"]

  connect() {
    this.toggle()
  }

  disconnect() {
    this.releasePhoto()
  }

  toggle() {
    const enabled = this.toggleTarget.checked
    this.editorTarget.hidden = !enabled
    this.editorTarget.disabled = !enabled
    this.toggleTarget.setAttribute("aria-expanded", String(enabled))
  }

  previewPhoto(event) {
    const file = event.target.files[0]
    if (!file) return
    this.releasePhoto()
    this.photoUrl = URL.createObjectURL(file)
    this.photoTarget.src = this.photoUrl
    this.photoTarget.hidden = false
    this.placeholderTarget.hidden = true
  }

  releasePhoto() {
    if (this.photoUrl) URL.revokeObjectURL(this.photoUrl)
    this.photoUrl = null
  }
}
