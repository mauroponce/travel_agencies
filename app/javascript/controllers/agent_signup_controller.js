import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "slug", "status", "suggestion"]
  static values = { url: String, customSlug: Boolean }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  nameChanged() {
    if (!this.customSlugValue) this.schedule(true)
  }

  slugChanged() {
    this.customSlugValue = true
    this.schedule(false)
  }

  schedule(automatic) {
    clearTimeout(this.timer)
    this.request?.abort()
    this.suggestionTarget.hidden = true
    this.statusTarget.textContent = "Comprobando disponibilidad…"
    this.timer = setTimeout(() => this.suggest(automatic), 250)
  }

  async suggest(automatic) {
    this.request = new AbortController()
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set(automatic ? "name" : "slug", automatic ? this.nameTarget.value : this.slugTarget.value)
    try {
      const response = await fetch(url, { signal: this.request.signal, headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("availability")
      const result = await response.json()
      if (automatic) this.slugTarget.value = result.slug
      const available = automatic || result.available
      this.statusTarget.textContent = available ? "Link disponible. Lo confirmaremos al guardar." : "Este link no está disponible. Elegí otro o usá la sugerencia."
      this.suggestionTarget.dataset.slug = result.slug
      this.suggestionTarget.textContent = `Usar ${result.slug}`
      this.suggestionTarget.hidden = available
    } catch (error) {
      if (error.name !== "AbortError") this.statusTarget.textContent = "Validaremos la disponibilidad al guardar."
    }
  }

  useSuggestion() {
    this.slugTarget.value = this.suggestionTarget.dataset.slug
    this.customSlugValue = true
    this.schedule(false)
  }
}
