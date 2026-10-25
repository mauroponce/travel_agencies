import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
export default class extends Controller {
  connect() { this.timer = setTimeout(() => { if (!document.hidden) Turbo.visit(location.href, { action: "replace" }); else this.connect() }, 2500) }
  disconnect() { clearTimeout(this.timer) }
}
