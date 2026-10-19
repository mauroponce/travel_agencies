const CACHE = "nexoviajes-v1"
const STATIC = ["/icon.png", "/icon.svg", "/"]

self.addEventListener("install", event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC))))
self.addEventListener("activate", event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))))
self.addEventListener("fetch", event => {
  const request = event.request
  if (request.method !== "GET" || new URL(request.url).origin !== location.origin) return
  if (["style", "script", "image"].includes(request.destination)) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
      const clone = response.clone(); caches.open(CACHE).then(cache => cache.put(request, clone)); return response
    })))
  }
})
self.addEventListener("push", event => {
  const message = event.data?.json() || {}
  event.waitUntil(self.registration.showNotification(message.title || "NexoViajes", { body: message.body, icon: "/icon.png", data: { url: message.url || "/dashboard" } }))
})
self.addEventListener("notificationclick", event => { event.notification.close(); event.waitUntil(clients.openWindow(event.notification.data.url)) })
