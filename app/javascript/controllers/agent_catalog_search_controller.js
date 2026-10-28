import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "clear", "dropdown", "status", "results"]
  static values = { url: String }

  connect() {
    this.close()
  }

  disconnect() {
    this.close()
  }

  search() {
    this.close()
    const query = this.inputTarget.value.trim()
    this.clearTarget.hidden = this.inputTarget.value.length === 0
    if (query.length < 2) return
    this.timer = setTimeout(() => this.fetchResults(query), 200)
  }

  async fetchResults(query) {
    const request = new AbortController()
    this.request = request
    this.showStatus("Buscando viajes…")
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, { signal: request.signal, headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Search unavailable")
      const { results } = await response.json()
      if (request.signal.aborted) return
      this.renderResults(results)
    } catch (error) {
      if (request.signal.aborted) return
      this.showStatus("No pudimos cargar las sugerencias. Usá Buscar viajes para continuar.")
    }
  }

  renderResults(results) {
    this.resultsTarget.replaceChildren()
    this.activeIndex = -1
    const count = results.length === 1 ? "1 viaje disponible" : `${results.length} viajes disponibles`
    this.showStatus(results.length ? `${count}. Usá las flechas para elegir.` : "No encontramos viajes vigentes para esa búsqueda. Probá con otro destino.")
    results.forEach((trip, index) => {
      const option = document.createElement("a")
      option.id = `agent-search-option-${index}`
      option.href = trip.url
      option.className = "agent-search-option"
      option.role = "option"
      option.tabIndex = -1
      option.setAttribute("aria-selected", "false")
      const thumbnail = document.createElement("span")
      thumbnail.className = "agent-search-thumbnail"
      thumbnail.setAttribute("aria-hidden", "true")
      if (trip.image_url) {
        const image = document.createElement("img")
        image.src = trip.image_url
        image.alt = ""
        image.width = 64
        image.height = 80
        image.loading = "lazy"
        image.decoding = "async"
        thumbnail.append(image)
      } else {
        thumbnail.textContent = "↝"
      }
      const body = document.createElement("span")
      body.className = "agent-search-option-body"
      const destination = document.createElement("strong")
      destination.textContent = trip.destination
      const title = document.createElement("span")
      title.textContent = trip.title
      const details = document.createElement("span")
      details.textContent = `Salida ${trip.date}`
      const price = document.createElement("small")
      price.textContent = trip.price
      body.append(destination, title, details, price)
      option.append(thumbnail, body)
      this.resultsTarget.append(option)
    })
  }

  navigate(event) {
    if (["Escape", "Tab"].includes(event.key)) {
      if (event.key === "Escape") event.preventDefault()
      this.close()
      return
    }
    const options = Array.from(this.resultsTarget.children)
    if (this.dropdownTarget.hidden || options.length === 0) return
    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      const direction = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = this.activeIndex < 0 ? (direction > 0 ? 0 : options.length - 1) : (this.activeIndex + direction + options.length) % options.length
      options.forEach((option, index) => option.setAttribute("aria-selected", String(index === this.activeIndex)))
      const active = options[this.activeIndex]
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    } else if (event.key === "Enter" && this.activeIndex >= 0) {
      event.preventDefault()
      options[this.activeIndex].click()
    }
  }

  showStatus(message) {
    this.statusTarget.textContent = message
    this.dropdownTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  clear() {
    this.inputTarget.value = ""
    this.clearTarget.hidden = true
    this.close()
    this.inputTarget.focus()
  }

  dismiss(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  close() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.dropdownTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.resultsTarget.replaceChildren()
    this.activeIndex = -1
  }
}
