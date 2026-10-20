import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay", "toggle"]

  connect() {
    this.mobileMedia = window.matchMedia("(max-width: 760px)")
    this.handleMediaChange = () => this.syncSidebarAccessibility()
    this.mobileMedia.addEventListener("change", this.handleMediaChange)
    this.syncSidebarAccessibility()
  }

  open() {
    this.sidebarTarget.classList.add("mobile-open")
    this.overlayTarget.classList.add("visible")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    document.documentElement.classList.add("menu-open")
    this.syncSidebarAccessibility()
    this.sidebarTarget.querySelector("a")?.focus()
  }

  close() {
    if (!this.sidebarTarget.classList.contains("mobile-open")) return
    this.sidebarTarget.classList.remove("mobile-open")
    this.overlayTarget.classList.remove("visible")
    this.toggleTarget.setAttribute("aria-expanded", "false")
    document.documentElement.classList.remove("menu-open")
    this.syncSidebarAccessibility()
    this.toggleTarget.focus()
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  submitForm(event) {
    event.currentTarget.form?.requestSubmit()
  }

  syncSidebarAccessibility() {
    const hidden = this.mobileMedia.matches && !this.sidebarTarget.classList.contains("mobile-open")
    this.sidebarTarget.toggleAttribute("inert", hidden)
    this.sidebarTarget.setAttribute("aria-hidden", String(hidden))
  }

  disconnect() {
    this.mobileMedia?.removeEventListener("change", this.handleMediaChange)
    document.documentElement.classList.remove("menu-open")
  }
}
