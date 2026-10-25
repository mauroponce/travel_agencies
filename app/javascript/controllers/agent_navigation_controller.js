import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["toggle"]
  toggle() {
    const collapsed = this.element.classList.toggle("agent-sidebar-collapsed")
    this.toggleTarget.setAttribute("aria-expanded", String(!collapsed))
    this.toggleTarget.setAttribute("aria-label", collapsed ? "Expandir menú lateral" : "Contraer menú lateral")
    this.toggleTarget.textContent = collapsed ? "›" : "‹"
  }
}
