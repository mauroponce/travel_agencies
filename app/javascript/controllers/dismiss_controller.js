import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  connect() { this.timeout = setTimeout(() => this.element.remove(), 4500) }
  disconnect() { clearTimeout(this.timeout) }
}
