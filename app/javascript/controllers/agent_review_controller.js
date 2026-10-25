import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["trip", "revision"]
  select() { this.revisionTarget.value = this.tripTarget.selectedOptions[0]?.dataset.revision || "" }
}
