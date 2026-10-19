import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { url: String }
  static targets = ["price", "fee", "seats", "label"]
  connect() { this.refresh = this.refresh.bind(this); this.timer = setInterval(this.refresh, 30000); document.addEventListener("visibilitychange", this.refresh) }
  disconnect() { clearInterval(this.timer); document.removeEventListener("visibilitychange", this.refresh) }
  async refresh() {
    if (document.hidden) return
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } }); if (!response.ok) return
    const data = await response.json()
    this.priceTarget.textContent = this.money(data.price_cents); this.feeTarget.textContent = this.money(data.service_fee_cents)
    this.seatsTarget.textContent = data.sold_out ? "Sin cupos disponibles" : `${data.available_seats} cupos disponibles`
    if (this.hasLabelTarget) this.labelTarget.textContent = data.promotion_label || "Precio vigente"
  }
  money(cents) { return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" }).format(cents / 100) }
}
