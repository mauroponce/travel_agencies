import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["frame"]
  desktop() { this.frameTarget.style.width = "100%" }
  mobile() { this.frameTarget.style.width = "min(390px, 100%)" }
}
