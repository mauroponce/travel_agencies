import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["container", "template"]
  add() { const index = this.containerTarget.children.length; this.containerTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_INDEX", index)) }
  remove(event) { event.target.closest("[data-passenger]").remove() }
}
