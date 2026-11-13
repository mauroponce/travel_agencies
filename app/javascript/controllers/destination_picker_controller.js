import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "value", "menu", "option", "status", "clear", "toggle", "field", "filters", "filterToggle", "counter"]

  connect() {
    this.lastQuery = this.queryKey()
    this.close()
    this.syncControls()
  }

  disconnect() { clearTimeout(this.timer) }

  queryKey() { return new URLSearchParams(new FormData(this.element)).toString() }

  open() {
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.render("")
  }

  toggle() {
    if (!this.menuTarget.hidden) return this.close()
    this.inputTarget.focus()
    this.open()
  }

  filter(event) {
    if (event.isComposing) return
    clearTimeout(this.timer)
    this.valueTarget.value = ""
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.render(this.inputTarget.value)
    this.syncControls()
    this.timer = setTimeout(() => this.submit(), 350)
  }

  render(query) {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("es").trim()
    const term = normalize(query)
    this.optionTargets.forEach(option => {
      option.hidden = !normalize(option.dataset.label).includes(term)
      option.setAttribute("aria-selected", String(option.dataset.value === this.valueTarget.value))
    })
    this.activeIndex = -1
    this.highlight()
    this.statusTarget.textContent = this.visibleOptions.length ? "" : "No encontramos ese destino. Probá con otro nombre."
  }

  get visibleOptions() { return this.optionTargets.filter(option => !option.hidden) }

  navigate(event) {
    if (["Escape", "Tab"].includes(event.key)) {
      if (event.key === "Escape") event.preventDefault()
      this.close()
      return
    }
    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      if (this.menuTarget.hidden) this.open()
      const count = this.visibleOptions.length
      if (!count) return
      const direction = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = this.activeIndex < 0 ? (direction > 0 ? 0 : count - 1) : (this.activeIndex + direction + count) % count
      this.highlight()
    } else if (event.key === "Enter") {
      event.preventDefault()
      const option = this.menuTarget.hidden ? null : this.visibleOptions[Math.max(this.activeIndex, 0)]
      if (option) this.select(option)
      else { this.close(); this.submit() }
    }
  }

  highlight() {
    this.optionTargets.forEach(option => delete option.dataset.active)
    const active = this.visibleOptions[this.activeIndex]
    if (active) {
      active.dataset.active = "true"
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    } else this.inputTarget.removeAttribute("aria-activedescendant")
  }

  choose(event) { this.select(event.currentTarget) }

  select(option) {
    this.valueTarget.value = option.dataset.value
    this.inputTarget.value = option.dataset.value ? option.dataset.label : ""
    this.optionTargets.forEach(item => item.setAttribute("aria-selected", String(item === option)))
    this.inputTarget.focus({ preventScroll: true })
    this.close()
    this.syncControls()
    this.submit()
  }

  clear() {
    this.inputTarget.value = ""
    this.valueTarget.value = ""
    this.close()
    this.syncControls()
    this.submit()
    this.inputTarget.focus({ preventScroll: true })
  }

  toggleFilters() {
    const open = this.filtersTarget.hidden
    this.filtersTarget.hidden = !open
    this.filtersTarget.classList.toggle("open", open)
    this.filterToggleTarget.setAttribute("aria-expanded", String(open))
    this.close()
  }

  clearFilters() {
    for (const name of ["month", "transport", "duration", "currency", "price_unit", "max_price"]) this.element.elements.namedItem(name).value = ""
    this.apply()
  }

  apply() { this.close(); this.syncControls(); this.submit() }

  syncControls() {
    this.clearTarget.hidden = this.inputTarget.value.length === 0
    const count = ["month", "transport", "duration", "currency", "price_unit", "max_price"].filter(name => this.element.elements.namedItem(name).value).length
    this.counterTarget.textContent = String(count)
    this.counterTarget.hidden = count === 0
  }

  submit() {
    clearTimeout(this.timer)
    if (this.queryKey() !== this.lastQuery) this.element.requestSubmit()
  }

  submitting() { clearTimeout(this.timer); this.lastQuery = this.queryKey() }

  cache() { if (document.activeElement !== this.inputTarget) this.close() }

  dismiss(event) { if (!this.fieldTarget.contains(event.target)) this.close() }
  blur(event) { if (!this.fieldTarget.contains(event.relatedTarget)) this.close() }

  close() {
    this.menuTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
