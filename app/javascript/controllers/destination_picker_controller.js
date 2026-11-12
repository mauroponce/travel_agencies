import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "value", "menu", "option", "status"]

  connect() {
    this.reset()
  }

  open() {
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.render("")
    this.inputTarget.select()
  }

  toggle() {
    if (!this.menuTarget.hidden) return this.reset()
    this.inputTarget.focus()
    this.open()
  }

  filter() {
    this.menuTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.render(this.inputTarget.value)
  }

  render(query) {
    const normalize = value => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("es").trim()
    const term = normalize(query)
    this.optionTargets.forEach(option => {
      option.hidden = !normalize(option.dataset.label).includes(term)
    })
    this.activeIndex = -1
    this.highlight()
    const count = this.visibleOptions.length
    this.statusTarget.textContent = count ? "" : "No encontramos ese destino. Probá con otro nombre."
    this.statusTarget.hidden = count > 0
  }

  get visibleOptions() {
    return this.optionTargets.filter(option => !option.hidden)
  }

  navigate(event) {
    if (event.key === "Escape" || event.key === "Tab") {
      if (event.key === "Escape") event.preventDefault()
      this.reset()
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
      if (this.menuTarget.hidden) return this.open()
      const option = this.visibleOptions[Math.max(this.activeIndex, 0)]
      if (option) this.select(option)
    }
  }

  highlight() {
    this.optionTargets.forEach(option => delete option.dataset.active)
    const active = this.visibleOptions[this.activeIndex]
    if (active) {
      active.dataset.active = "true"
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  choose(event) {
    this.select(event.currentTarget)
  }

  select(option) {
    this.valueTarget.value = option.dataset.value
    this.optionTargets.forEach(item => item.setAttribute("aria-selected", String(item === option)))
    this.reset()
    this.element.requestSubmit()
  }

  dismiss(event) {
    if (!this.element.contains(event.target)) this.reset()
  }

  blur(event) {
    if (!this.element.contains(event.relatedTarget)) this.reset()
  }

  reset() {
    this.menuTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    const selected = this.optionTargets.find(option => option.dataset.value === this.valueTarget.value)
    this.inputTarget.value = selected?.dataset.label || "Todos los destinos"
  }
}
