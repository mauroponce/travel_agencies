import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "menu", "options", "status"]
  static values = { url: String }

  connect() {
    this.lastDestination = this.inputTarget.value
    this.activeIndex = -1
  }

  disconnect() {
    clearTimeout(this.searchTimer)
    this.close()
  }

  search(event) {
    if (event.isComposing) return
    clearTimeout(this.searchTimer)
    this.close()
    this.suggestionTimer = setTimeout(() => this.suggest(), 200)
    this.searchTimer = setTimeout(() => this.submit(), 350)
  }

  submit() {
    clearTimeout(this.searchTimer)
    if (this.inputTarget.value !== this.lastDestination) this.element.requestSubmit()
  }

  submitting(event) {
    clearTimeout(this.searchTimer)
    this.lastDestination = this.inputTarget.value
    if (event.submitter) this.close()
  }

  async suggest() {
    clearTimeout(this.suggestionTimer)
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const query = this.inputTarget.value
    const url = new URL(this.urlValue, window.location.origin)
    for (const [key, value] of new FormData(this.element)) {
      if (value) url.searchParams.set(key, value)
    }
    this.optionsTarget.replaceChildren()
    this.activeIndex = -1
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.showStatus("Buscando destinos…")
    try {
      const response = await fetch(url, { signal: request.signal, headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("Suggestions unavailable")
      const { destinations } = await response.json()
      if (request.signal.aborted || query !== this.inputTarget.value) return
      destinations.forEach((destination, index) => {
        const option = document.createElement("button")
        option.type = "button"
        option.id = `trip-destination-${index}`
        option.role = "option"
        option.tabIndex = -1
        option.setAttribute("aria-selected", "false")
        option.dataset.destination = destination
        option.dataset.action = "click->trip-search#choose"
        option.textContent = destination
        this.optionsTarget.append(option)
      })
      this.showStatus(destinations.length ? "" : "No encontramos ese destino.")
    } catch {
      if (!request.signal.aborted) this.showStatus("No pudimos cargar las sugerencias.")
    }
  }

  showStatus(message) {
    this.statusTarget.textContent = message
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  choose(event) {
    this.select(event.currentTarget)
  }

  select(option) {
    this.inputTarget.value = option.dataset.destination
    this.inputTarget.focus({ preventScroll: true })
    this.close()
    this.submit()
  }

  async navigate(event) {
    if (["Escape", "Tab"].includes(event.key)) {
      if (event.key === "Escape") event.preventDefault()
      this.close()
      return
    }
    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      if (this.menuTarget.hidden) await this.suggest()
      const options = [...this.optionsTarget.children]
      if (!options.length || document.activeElement !== this.inputTarget) return
      const direction = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = this.activeIndex < 0 ? (direction > 0 ? 0 : options.length - 1)
        : (this.activeIndex + direction + options.length) % options.length
      options.forEach((option, index) => option.setAttribute("aria-selected", String(index === this.activeIndex)))
      const active = options[this.activeIndex]
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    } else if (event.key === "Enter") {
      event.preventDefault()
      const option = this.optionsTarget.children[this.activeIndex]
      if (!this.menuTarget.hidden && option) this.select(option)
      else { this.close(); this.submit() }
    }
  }

  dismiss(event) {
    if (!this.inputTarget.closest(".agent-trip-destination").contains(event.target)) this.close()
  }

  blur(event) {
    if (!this.inputTarget.closest(".agent-trip-destination").contains(event.relatedTarget)) this.close()
  }

  close() {
    clearTimeout(this.suggestionTimer)
    this.request?.abort()
    this.menuTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.optionsTarget.replaceChildren()
    this.activeIndex = -1
  }
}
