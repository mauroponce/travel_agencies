import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  connect() {
    if ("serviceWorker" in navigator) navigator.serviceWorker.register("/service-worker")
    this.captureInstall = event => { event.preventDefault(); this.installPrompt = event }
    window.addEventListener("beforeinstallprompt", this.captureInstall)
  }

  disconnect() { window.removeEventListener("beforeinstallprompt", this.captureInstall) }

  async install(event) {
    if (!this.installPrompt) { event.currentTarget.textContent = "Usá el menú del navegador para agregarla al inicio"; return }
    await this.installPrompt.prompt()
    this.installPrompt = null
  }

  async subscribe(event) {
    event.currentTarget.disabled = true
    try {
      if (!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error("Este navegador no admite Web Push")
      const key = document.querySelector('meta[name="vapid-public-key"]')?.content
      if (!key) throw new Error("Web Push todavía no está configurado en este entorno")
      const permission = await Notification.requestPermission()
      if (permission !== "granted") throw new Error("No se concedió permiso para notificaciones")
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.decodeKey(key) })
      const payload = subscription.toJSON()
      const response = await fetch("/push_subscriptions", {
        method: "POST",
        headers: {"Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content},
        body: JSON.stringify({push_subscription: {endpoint: payload.endpoint, p256dh: payload.keys.p256dh, auth: payload.keys.auth}})
      })
      if (!response.ok) throw new Error("No pudimos registrar este dispositivo")
      event.currentTarget.textContent = "Notificaciones activadas"
    } catch (error) {
      event.currentTarget.disabled = false
      event.currentTarget.textContent = error.message
    }
  }

  decodeKey(value) {
    const padding = "=".repeat((4 - value.length % 4) % 4)
    const raw = atob((value + padding).replace(/-/g, "+").replace(/_/g, "/"))
    return Uint8Array.from([...raw].map(character => character.charCodeAt(0)))
  }
}
