const CACHE = "tenant-<%= Current.company.id %>-v2"
const STATIC = ["/icon.png", "/icon.svg"]

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
  const target = new URL(message.url || "/dashboard", location.origin)
  const safeUrl = target.origin === location.origin ? target.href : new URL("/dashboard", location.origin).href
  event.waitUntil(self.registration.showNotification(message.title || "<%= j Current.company.name %>", { body: message.body, icon: "/icon.png", data: { url: safeUrl } }))
})
self.addEventListener("notificationclick", event => { event.notification.close(); event.waitUntil(clients.openWindow(event.notification.data.url)) })
