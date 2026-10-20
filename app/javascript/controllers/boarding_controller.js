import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { syncUrl: String, companyId: String, departureId: String, userId: String }

  connect() {
    this.flush = () => this.sendPending()
    window.addEventListener("online", this.flush)
    this.renderQueue()
    if (navigator.onLine) this.sendPending()
  }

  disconnect() {
    window.removeEventListener("online", this.flush)
  }

  mark(event) {
    const button = event.currentTarget
    const passenger = button.closest("[data-passenger-id]")
    const command = {
      command_id: this.commandId(),
      passenger_id: passenger.dataset.passengerId,
      desired_status: button.dataset.status,
      base_version: Number(passenger.dataset.version),
      occurred_at: new Date().toISOString(),
      state: "pending"
    }
    const queue = this.readQueue().filter(item => item.passenger_id !== command.passenger_id)
    this.writeQueue([...queue, command])
    this.renderQueue()
    if (navigator.onLine) this.sendPending()
  }

  get storageKey() {
    return `nexoviajes.boarding.queue.${this.companyIdValue}.${this.departureIdValue}.${this.userIdValue}`
  }

  commandId() {
    if (crypto.randomUUID) return crypto.randomUUID()
    const bytes = crypto.getRandomValues(new Uint8Array(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    const hex = [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("")
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
  }

  readQueue() {
    try {
      const queue = JSON.parse(localStorage.getItem(this.storageKey) || "[]")
      return Array.isArray(queue) ? queue : []
    } catch (_error) {
      return []
    }
  }

  writeQueue(queue) {
    localStorage.setItem(this.storageKey, JSON.stringify(queue))
  }

  async sendPending() {
    if (this.sending) {
      this.retryRequested = true
      return
    }
    this.retryRequested = false
    const commands = this.readQueue().filter(command => command.state === "pending")
    if (!commands.length) return

    this.sending = true
    const abortController = new AbortController()
    const requestTimeout = setTimeout(() => abortController.abort(), 5000)
    try {
      const token = document.querySelector("meta[name=csrf-token]")?.content
      const headers = { "Content-Type": "application/json" }
      if (token) headers["X-CSRF-Token"] = token
      const response = await fetch(this.syncUrlValue, {
        method: "POST",
        headers,
        body: JSON.stringify({ commands: commands.map(({ state: _state, ...command }) => command) }),
        signal: abortController.signal
      })
      if (!response.ok) {
        if (![408, 425, 429].includes(response.status) && response.status < 500) this.markCommands(commands, "error")
        return
      }

      const { results } = await response.json()
      const byId = new Map(results.map(result => [result.command_id, result]))
      const nextQueue = this.readQueue().flatMap(command => {
        const result = byId.get(command.command_id)
        if (!result) return [command]
        if (["applied", "duplicate"].includes(result.result)) return []
        return [{ ...command, state: result.result === "conflict" ? "conflict" : "error" }]
      })
      this.writeQueue(nextQueue)
      this.renderQueue()
      if (results.some(result => ["applied", "duplicate"].includes(result.result))) window.location.reload()
    } catch (_error) {
      // The command was persisted before the request and will be retried on reconnect/reload.
    } finally {
      clearTimeout(requestTimeout)
      this.sending = false
      this.renderQueue()
      if (this.retryRequested && navigator.onLine) {
        this.retryRequested = false
        queueMicrotask(() => this.sendPending())
      }
    }
  }

  markCommands(commands, state) {
    const ids = new Set(commands.map(command => command.command_id))
    this.writeQueue(this.readQueue().map(command => ids.has(command.command_id) ? { ...command, state } : command))
  }

  renderQueue() {
    const states = new Map(this.readQueue().map(command => [command.passenger_id, command.state]))
    this.element.querySelectorAll("[data-passenger-id]").forEach(passenger => {
      const status = passenger.querySelector("[data-boarding-status]")
      const state = states.get(passenger.dataset.passengerId)
      passenger.dataset.pending = state ? "true" : "false"
      status.textContent = ({ pending: "Pendiente de sincronizar", conflict: "Conflicto: revisá el estado", error: "Error: tocá un estado para reintentar" })[state] || "Sin cambios pendientes"
      status.dataset.state = state || "synced"
    })
  }
}
