import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { syncUrl: String }
  connect() { this.flush = () => this.send(this.readQueue()); window.addEventListener("online", this.flush); if (navigator.onLine) this.flush() }
  disconnect() { window.removeEventListener("online", this.flush) }
  async mark(event) {
    const button = event.currentTarget
    const passenger = button.closest("[data-passenger-id]")
    const command = { command_id: crypto.randomUUID(), passenger_id: passenger.dataset.passengerId, desired_status: button.dataset.status, base_version: Number(passenger.dataset.version), occurred_at: new Date().toISOString() }
    if (!navigator.onLine) { this.enqueue(command); passenger.dataset.pending = "true"; button.textContent = "Pendiente de sincronizar"; return }
    await this.send([command])
  }
  readQueue() { return JSON.parse(sessionStorage.getItem("nexoviajes.boarding.queue") || "[]") }
  enqueue(command) { sessionStorage.setItem("nexoviajes.boarding.queue", JSON.stringify([...this.readQueue(), command])) }
  async send(commands) {
    if (!commands.length) return
    const token = document.querySelector("meta[name=csrf-token]").content
    const response = await fetch(this.syncUrlValue, { method: "POST", headers: {"Content-Type": "application/json", "X-CSRF-Token": token}, body: JSON.stringify({commands}) }); if (!response.ok) return
    const { results } = await response.json(); const completed = new Set(results.filter(result => ["applied", "duplicate"].includes(result.result)).map(result => result.command_id))
    sessionStorage.setItem("nexoviajes.boarding.queue", JSON.stringify(this.readQueue().filter(command => !completed.has(command.command_id)))); window.location.reload()
  }
}
