import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  choose(event) {
    event.preventDefault()
    this.select(Number(event.currentTarget.dataset.index))
  }

  key(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const current = this.tabTargets.findIndex(tab => tab.getAttribute("aria-selected") === "true")
    const count = this.tabTargets.length
    this.select(event.key === "Home" ? 0 : event.key === "End" ? count - 1 : (current + (event.key === "ArrowRight" ? 1 : -1) + count) % count)
  }

  select(index) {
    this.tabTargets.forEach((tab, position) => {
      tab.setAttribute("aria-selected", String(position === index))
      tab.tabIndex = position === index ? 0 : -1
    })
    this.panelTargets.forEach((panel, position) => { panel.hidden = position !== index })
    this.tabTargets[index]?.focus({ preventScroll: true })
  }
}
