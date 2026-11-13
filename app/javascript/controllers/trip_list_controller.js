import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "manual", "selection", "compareButton", "heading"]
  static values = { focus: Boolean }

  connect() {
    this.updateComparison()
    if (this.focusValue) this.headingTarget.focus({ preventScroll: true })
  }

  updateComparison() {
    const count = this.selectionTargets.filter(input => input.checked).length
    this.compareButtonTarget.disabled = count < 2 || count > 3
  }

  navigateTabs(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    const tabs = [...event.currentTarget.querySelectorAll('[role="tab"]')]
    const index = tabs.indexOf(document.activeElement)
    if (index < 0) return
    event.preventDefault()
    const next = event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1
      : (index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length
    tabs.forEach((tab, position) => { tab.tabIndex = position === next ? 0 : -1 })
    tabs[next].focus()
  }

  async copyLink(event) {
    const url = event.currentTarget.dataset.url
    event.currentTarget.dispatchEvent(new CustomEvent("trip-menu:close", { bubbles: true }))
    try {
      await navigator.clipboard.writeText(url)
      this.manualTarget.hidden = true
      this.statusTarget.textContent = "Enlace copiado."
    } catch {
      this.manualTarget.hidden = false
      this.manualTarget.value = url
      this.manualTarget.focus()
      this.manualTarget.select()
      this.statusTarget.textContent = "Seleccioná el enlace y elegí Copiar."
    }
  }
}
