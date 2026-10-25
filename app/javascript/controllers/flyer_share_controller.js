import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "shareButton", "manual"]
  static values = { image: String, url: String, text: String }

  connect() {
    this.abort = new AbortController()
    if (this.hasShareButtonTarget && this.imageValue) this.prepareFile()
  }

  disconnect() { this.abort.abort() }

  async prepareFile() {
    // Fetch before the click so iOS keeps the user activation for navigator.share.
    this.shareButtonTarget.disabled = true
    this.shareButtonTarget.setAttribute("aria-busy", "true")
    try {
      const response = await fetch(this.imageValue, { credentials: "same-origin", signal: this.abort.signal })
      if (!response.ok) throw new Error("download")
      const blob = await response.blob()
      const extensions = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }
      if (!extensions[blob.type] || blob.size > 10 * 1024 * 1024) throw new Error("type")
      this.file = new File([blob], `flyer.${extensions[blob.type]}`, { type: blob.type })
    } catch (error) {
      if (error.name !== "AbortError") this.statusTarget.textContent = "No pudimos preparar la imagen. Podés descargar el flyer y copiar el texto."
    } finally {
      if (this.element.isConnected) {
        this.shareButtonTarget.disabled = false
        this.shareButtonTarget.removeAttribute("aria-busy")
      }
    }
  }

  async share() {
    try {
      if (!window.isSecureContext || !this.file || !navigator.canShare || !navigator.share || !navigator.canShare({ files: [this.file] })) {
        this.statusTarget.textContent = "Este navegador no permite compartir archivos. Descargá el flyer y copiá el texto para pegarlo en WhatsApp."
        return
      }
      let data = { files: [this.file], text: this.textValue, url: this.urlValue }
      if (!navigator.canShare(data)) data = { files: [this.file], text: this.textValue }
      await navigator.share(data)
      this.statusTarget.textContent = "Menú de compartir cerrado. Revisá en WhatsApp que la imagen y el enlace estén incluidos."
    } catch (error) {
      this.statusTarget.textContent = error.name === "AbortError"
        ? "Se canceló el menú de compartir. Podés intentarlo de nuevo."
        : "No se pudo compartir desde este navegador. Descargá el flyer y copiá el texto."
    }
  }

  copyLink() { return this.copy(this.urlValue, "Enlace copiado.") }
  copyText() { return this.copy(this.textValue, "Texto copiado. Pegalo junto al flyer en WhatsApp.") }

  async copy(text, message) {
    try {
      await navigator.clipboard.writeText(text)
      this.statusTarget.textContent = message
    } catch {
      this.manualTarget.hidden = false
      this.manualTarget.value = text
      this.manualTarget.focus()
      this.manualTarget.select()
      this.statusTarget.textContent = "Mantené presionado el texto seleccionado y elegí Copiar."
    }
  }
}
