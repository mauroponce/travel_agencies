import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "menu"]

  connect() {
    this.outside = event => { if (!this.element.contains(event.target)) this.close() }
    this.scrolled = event => { if (!this.menuTarget.contains(event.target)) this.position() }
    this.resized = () => this.close()
  }

  disconnect() { this.close() }

  toggle() { this.opened ? this.close(true) : this.open() }

  open(last = false) {
    this.menuTarget.hidden = false
    if (this.menuTarget.showPopover) this.menuTarget.showPopover()
    this.opened = true
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.position()
    const items = this.items()
    items[last ? items.length - 1 : 0]?.focus({ preventScroll: true })
    document.addEventListener("click", this.outside)
    document.addEventListener("scroll", this.scrolled, true)
    window.addEventListener("resize", this.resized)
  }

  position() {
    if (!this.opened) return
    const anchor = this.triggerTarget.getBoundingClientRect()
    if (anchor.bottom < 0 || anchor.top > innerHeight || anchor.right < 0 || anchor.left > innerWidth) {
      this.close()
      return
    }
    const menu = this.menuTarget.getBoundingClientRect()
    const left = Math.max(8, Math.min(anchor.right - menu.width, innerWidth - menu.width - 8))
    const below = anchor.bottom + 6
    const top = Math.max(8, below + menu.height <= innerHeight - 8 ? below : anchor.top - menu.height - 6)
    Object.assign(this.menuTarget.style, { left: `${left}px`, top: `${top}px` })
  }

  close(restoreFocus = false) {
    if (!this.opened) return
    this.opened = false
    if (this.menuTarget.hidePopover && this.menuTarget.matches(":popover-open")) this.menuTarget.hidePopover()
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.outside)
    document.removeEventListener("scroll", this.scrolled, true)
    window.removeEventListener("resize", this.resized)
    if (restoreFocus && this.triggerTarget.isConnected) this.triggerTarget.focus({ preventScroll: true })
  }

  dismiss() { this.close() }
  closeAndFocus() { this.close(true) }
  toggled(event) { if (event.newState === "closed") this.close() }
  select(event) { if (event.target.closest('[role="menuitem"]')) this.close(true) }

  triggerKey(event) {
    if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      this.open(event.key === "ArrowUp")
    }
  }

  menuKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.close(true)
    } else if (event.key === "Tab") {
      this.close(true)
    } else if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      event.preventDefault()
      const items = this.items()
      const current = items.indexOf(document.activeElement)
      const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1
        : (current + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length
      items[next]?.focus({ preventScroll: true })
    }
  }

  items() { return [...this.menuTarget.querySelectorAll('[role="menuitem"]')] }
}
