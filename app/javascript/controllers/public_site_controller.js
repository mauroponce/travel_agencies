import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["catalog", "profile", "catalogLink", "profileLink", "favorite"]
  static values = { workspace: String, name: String }

  connect() { this.syncView() }

  syncView(event) {
    const profile = this.hasProfileTarget && (!this.hasCatalogTarget || window.location.hash === "#sobre-mi")
    if (this.hasCatalogTarget) this.catalogTarget.hidden = profile
    if (this.hasProfileTarget) this.profileTarget.hidden = !profile
    for (const [links, active] of [[this.catalogLinkTargets, !profile], [this.profileLinkTargets, profile]]) {
      links.forEach(link => {
        link.classList.toggle("active", active)
        if (active) link.setAttribute("aria-current", "page")
        else link.removeAttribute("aria-current")
      })
    }
    document.title = `${profile ? "Sobre mí" : "Viajes"} · ${this.nameValue}`
    if (event) window.scrollTo({ top: 0, behavior: "instant" })
  }

  get storageKey() { return `turistack:public-favorites:${this.workspaceValue}` }

  get favorites() {
    if (!this.savedFavorites) {
      try {
        const stored = JSON.parse(localStorage.getItem(this.storageKey) || "[]")
        this.savedFavorites = new Set(Array.isArray(stored) ? stored.filter(id => typeof id === "string") : [])
      } catch { this.savedFavorites = new Set() }
    }
    return this.savedFavorites
  }

  favoriteTargetConnected(button) { this.syncFavorite(button) }

  syncFavorite(button) {
    const saved = this.favorites.has(button.dataset.tripId)
    button.setAttribute("aria-pressed", String(saved))
    button.setAttribute("aria-label", `${saved ? "Quitar de favoritos" : "Agregar a favoritos"}: ${button.dataset.title}`)
  }

  favorite(event) {
    const button = event.currentTarget
    const id = button.dataset.tripId
    if (this.favorites.has(id)) this.favorites.delete(id)
    else this.favorites.add(id)
    try { localStorage.setItem(this.storageKey, JSON.stringify([...this.favorites])) } catch { /* Keep favorites usable when storage is unavailable. */ }
    this.favoriteTargets.forEach(target => this.syncFavorite(target))
  }

  submitForm(event) { event.currentTarget.form.requestSubmit() }
}
