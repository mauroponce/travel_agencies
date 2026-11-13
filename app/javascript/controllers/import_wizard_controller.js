import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const escape = value => String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char])
const icon = name => `<svg class="ai-icon" aria-hidden="true"><use href="#icon-${name}"></use></svg>`
const labels = { title: "Nombre del viaje", destination: "Destino", hotel: "Hotel", meal_plan: "Régimen de comidas", transport: "Transporte", departure_location: "Lugar de salida", duration_days: "Días", duration_nights: "Noches", price: "Precio desde", currency: "Moneda", price_basis: "Base de ocupación y tarifa", included_services: "Servicios incluidos", excluded_services: "Servicios excluidos", conditions: "Tarifas, suplementos y condiciones", departs_on: "Fecha de salida", returns_on: "Fecha de regreso" }
const commonFields = ["title", "destination", "hotel", "duration_days", "duration_nights", "meal_plan", "transport", "departure_location", "included_services", "excluded_services", "conditions"]
const longFields = ["included_services", "excluded_services", "conditions"]
const options = { currency: [["ARS", "Pesos Argentinos"], ["USD", "Dólares"]] }
const dateLabel = date => /^\d{4}-\d{2}-\d{2}$/.test(date || "") ? date.split("-").reverse().join("/") : "Fecha pendiente"

export default class extends Controller {
  static targets = ["dialog", "steps", "preview", "content", "actions", "error", "status"]
  static values = { url: String, resume: String, autoOpen: Boolean }

  connect() {
    if (!this.hasDialogTarget) return
    this.step = 0
    this.items = []
    this.history = []
    this.expanded = new Set()
    this.fareSelections = new Map()
    this.saveQueue = Promise.resolve()
    this.beforeCache = () => { clearTimeout(this.pollTimer); clearTimeout(this.saveTimer); this.dialogTarget.close(); document.body.classList.remove("ai-wizard-open") }
    document.addEventListener("turbo:before-cache", this.beforeCache)
    if (this.resumeValue && this.hasDialogTarget) {
      this.open()
      this.resume(`${this.urlValue.replace(/\.json$/, "")}/${encodeURIComponent(this.resumeValue)}.json`)
    } else if (this.autoOpenValue) {
      this.open()
    }
  }

  disconnect() {
    clearTimeout(this.pollTimer)
    clearTimeout(this.saveTimer)
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    if (this.beforeCache) document.removeEventListener("turbo:before-cache", this.beforeCache)
    document.body.classList.remove("ai-wizard-open")
  }

  open(event) {
    event?.preventDefault()
    this.opener = document.activeElement
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    document.body.classList.add("ai-wizard-open")
    this.render()
    if (this.task && ["pending", "processing"].includes(this.task.status)) this.poll()
    if (!this.task) this.loadHistory()
  }

  async close() {
    if (this.busy) return
    clearTimeout(this.saveTimer)
    if (this.task?.status === "completed" && !this.result) {
      try { await this.save() } catch (error) { this.showError(error); return }
    }
    clearTimeout(this.pollTimer)
    this.dialogTarget.close()
    document.body.classList.remove("ai-wizard-open")
    this.opener?.focus()
    if (this.result) Turbo.visit(this.result.redirect_url)
  }

  cancel(event) { event.preventDefault(); this.close() }
  backdrop(event) {
    if (event.target !== this.dialogTarget) return
    const box = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) this.close()
  }

  async request(url, { method = "GET", body } = {}) {
    const headers = { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
    if (body && !(body instanceof FormData)) { headers["Content-Type"] = "application/json"; body = JSON.stringify(body) }
    const response = await fetch(url, { method, body, headers, credentials: "same-origin" })
    if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("No pudimos completar la solicitud. Revisá tu sesión y los permisos de tu plan.")
    const data = await response.json()
    if (!response.ok) {
      if (data.retained_cover) this.retainedCover = data.retained_cover
      throw new Error(data.error || "No pudimos completar la solicitud. Tus correcciones siguen disponibles.")
    }
    return data
  }

  async loadHistory() {
    try {
      const data = await this.request(this.urlValue)
      this.history = data.imports
      if (!this.task && this.dialogTarget.open) this.render()
    } catch (error) { this.showError(error) }
  }

  async resume(url) {
    await this.run(async () => {
      this.acceptTask(await this.request(url))
      this.step = this.task.status === "completed" ? 1 : 0
      if (["pending", "processing"].includes(this.task.status)) this.poll()
    })
  }

  acceptTask(data) {
    this.task = data
    this.items = data.items
    this.suppliers = data.suppliers
  }

  async upload() {
    if (!this.file && !this.retainedCover) return this.showError(new Error("Seleccioná un flyer para continuar."))
    await this.run(async () => {
      const body = new FormData()
      if (this.file) body.append("source", this.file)
      if (this.retainedCover) body.append("retained_cover", this.retainedCover)
      this.idempotencyKey ||= crypto.randomUUID()
      body.append("idempotency_key", this.idempotencyKey)
      this.acceptTask(await this.request(this.urlValue, { method: "POST", body }))
      this.step = this.task.status === "completed" ? 1 : 0
      if (["pending", "processing"].includes(this.task.status)) this.poll()
    })
  }

  poll() {
    clearTimeout(this.pollTimer)
    this.pollTimer = setTimeout(async () => {
      if (!this.dialogTarget.open || !this.element.isConnected) return
      try {
        this.acceptTask(await this.request(this.task.urls.show))
        if (this.task.status === "completed") this.step = 1
        this.render()
        if (["pending", "processing"].includes(this.task.status)) this.poll()
      } catch (error) { this.showError(error) }
    }, 2000)
  }

  rows() {
    return this.items.map(item => ({ id: item.id, client_key: item.client_key, template_id: item.template_id, values: structuredClone(item.values), overrides: [...item.overrides], selected: item.selected }))
  }

  save() {
    if (this.task?.status !== "completed" || this.result) return this.saveQueue
    clearTimeout(this.saveTimer)
    const rows = this.rows()
    this.saveQueue = this.saveQueue.catch(() => {}).then(async () => {
      const data = await this.request(this.task.urls.review, { method: "PATCH", body: { items: rows } })
      // Keep inputs being edited while the request runs; only merge server metadata.
      this.items.forEach(item => {
        const saved = data.items.find(row => row.id === item.id || (item.client_key && row.client_key === item.client_key))
        if (saved) { item.id = saved.id; item.duplicates = saved.duplicates }
      })
      this.statusTarget.textContent = "Correcciones guardadas · podés retomar después"
    })
    return this.saveQueue
  }

  scheduleSave() {
    this.statusTarget.textContent = "Guardando correcciones…"
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save().catch(error => this.showError(error)), 900)
  }

  async next() {
    if (this.step === 0) return this.upload()
    await this.run(async () => {
      await this.save()
      if (this.step === 2 && !this.selected.length) throw new Error("Seleccioná al menos una salida para crear.")
      this.step += 1
      this.acknowledge = false
    })
  }

  async back() {
    if (this.step === 1) return this.restart()
    await this.run(async () => { await this.save(); this.step = Math.max(1, this.step - 1) })
  }

  async restart() {
    await this.run(async () => {
      await this.save()
      this.task = null
      this.file = null
      this.items = []
      this.idempotencyKey = null
      this.retainedCover = null
      this.step = 0
      this.expanded.clear()
      if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
      await this.loadHistory()
    })
  }

  async confirm() {
    await this.run(async () => {
      await this.save()
      this.result = await this.request(this.task.urls.confirm, { method: "POST", body: { items: this.rows(), acknowledge_duplicates: !!this.acknowledge } })
    })
  }

  async retry() {
    await this.run(async () => {
      this.acceptTask(await this.request(this.task.urls.retry, { method: "POST" }))
      this.poll()
    })
  }

  async run(action) {
    if (this.busy) return
    this.busy = true
    this.errorTarget.hidden = true
    this.updateActions()
    this.dialogTarget.setAttribute("aria-busy", "true")
    try { await action(); this.render() } catch (error) { this.showError(error) } finally {
      this.busy = false
      this.dialogTarget.removeAttribute("aria-busy")
      this.updateActions()
    }
  }

  showError(error) {
    this.errorTarget.textContent = error.message
    this.errorTarget.hidden = false
    this.errorTarget.focus({ preventScroll: true })
    this.statusTarget.textContent = "Revisá el error para continuar"
  }

  input(event) {
    const element = event.target
    if (element.dataset.fareField) return this.fareInput(element)
    if (!element.dataset.field) return
    const field = element.dataset.field
    const item = this.items.find(row => row.id === element.dataset.item)
    if (item) {
      item.values[field] = element.value
      if (!item.overrides.includes(field)) item.overrides.push(field)
      const card = element.closest(".ai-review-row")
      if (field === "title") card.querySelector("[data-row-title]").textContent = element.value || "Viaje sin título"
      if (field === "departs_on") card.querySelector("[data-row-date]").textContent = dateLabel(element.value)
    } else {
      this.items.filter(row => row.program === element.dataset.program && !row.trip_id).forEach(row => {
        if (!row.overrides.includes(field)) row.values[field] = element.value
      })
    }
    this.acknowledge = false
    this.scheduleSave()
  }

  change(event) {
    const element = event.target
    if (element.matches("[data-flyer-file]")) { this.chooseFile(element.files[0]); return }
    if (element.matches("[data-enabled]")) {
      this.items.find(row => row.id === element.dataset.enabled).selected = element.checked
      this.acknowledge = false
      this.render()
      this.contentTarget.querySelector(`[data-enabled="${element.dataset.enabled}"]`)?.focus({ preventScroll: true })
      this.scheduleSave()
    } else if (element.matches("[data-acknowledge]")) this.acknowledge = element.checked
    else if (element.matches("select[data-field], select[data-fare-field]")) this.input(event)
  }

  chooseFile(file) {
    if (!file) return
    if (!["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(file.type) || file.size > 10 * 1024 * 1024) {
      return this.showError(new Error("Usá un JPG, PNG, WebP o PDF de hasta 10 MB."))
    }
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(file)
    this.file = file
    this.idempotencyKey = null
    this.retainedCover = null
    this.renderPreview()
    this.updateActions()
    const name = this.contentTarget.querySelector("[data-file-name]")
    if (name) name.textContent = file.name
  }

  drag(event) { event.preventDefault(); event.currentTarget.classList.add("ai-drag") }
  leave(event) { event.preventDefault(); event.currentTarget.classList.remove("ai-drag") }
  drop(event) { this.leave(event); this.chooseFile(event.dataTransfer.files[0]) }

  async contentClick(event) {
    const button = event.target.closest("button")
    if (!button || this.busy) return
    if (button.dataset.resume) return this.resume(button.dataset.resume)
    if (button.dataset.fareTab) return this.selectFare(button)
    if (button.dataset.expand) {
      const id = button.dataset.expand
      this.expanded.has(id) ? this.expanded.delete(id) : this.expanded.add(id)
      this.render()
      this.contentTarget.querySelector(`[data-expand="${id}"]`)?.focus({ preventScroll: true })
    }
    if (button.dataset.add) {
      const template = this.items.find(item => item.id === button.dataset.add)
      if (this.items.length >= 50) return this.showError(new Error("Se permiten hasta 50 salidas por importación."))
      const key = crypto.randomUUID()
      const row = structuredClone(template)
      Object.assign(row, { id: null, template_id: template.id, client_key: key, selected: true, trip_id: null, duplicates: [], overrides: ["departs_on", "returns_on"], departure_text: null })
      for (const field of [...commonFields, "agent_supplier_id", "fares"]) row.values[field] = structuredClone(this.commonValue(template.program, field))
      this.syncFarePrimary(row.values)
      row.values.departs_on = ""
      row.values.returns_on = ""
      this.items.push(row)
      await this.run(async () => { await this.save(); this.expanded.add(row.id) })
      this.contentTarget.querySelector(`[data-item="${row.id}"][data-field="departs_on"]`)?.focus()
    }
    if (button.dataset.createSupplier) {
      const container = button.closest(".ai-supplier")
      const name = container.querySelector("[data-new-supplier]").value.trim()
      if (!name) return this.showError(new Error("Completá el nombre de la empresa."))
      await this.run(async () => {
        await this.save()
        const data = await this.request(this.task.urls.supplier, { method: "POST", body: { name } })
        if (!this.suppliers.some(supplier => supplier.id === data.supplier.id)) this.suppliers.push(data.supplier)
        this.items.filter(item => item.program === button.dataset.createSupplier && !item.trip_id && !item.overrides.includes("agent_supplier_id")).forEach(item => { item.values.agent_supplier_id = data.supplier.id })
        await this.save()
      })
    }
  }

  get selected() { return this.items.filter(item => item.selected && !item.trip_id) }
  get programs() { return [...new Set(this.items.filter(item => !item.trip_id).map(item => item.program))] }
  supplierName(id) { return this.suppliers?.find(supplier => supplier.id === id)?.name || "Empresa pendiente" }
  commonValue(program, field) { return (this.items.find(item => item.program === program && !item.trip_id && !item.overrides.includes(field)) || this.items.find(item => item.program === program))?.values[field] }

  fareMoney(fare) {
    if (fare.price === null || fare.price === undefined || fare.price === "") return "Precio a confirmar"
    const raw = String(fare.price).replace(/[$\s]/g, "")
    const amount = Number(raw.includes(",") ? raw.replace(/\./g, "").replace(",", ".") : raw)
    return `${fare.currency === "USD" ? "USD" : "$"} ${Number.isFinite(amount) ? amount.toLocaleString("es-AR", { maximumFractionDigits: 2 }) : fare.price}`
  }

  syncFarePrimary(values) {
    const fares = values.fares || []
    const amount = fare => {
      const value = String(fare.price ?? "").trim()
      return Number(value.includes(",") ? value.replace(/\./g, "").replace(",", ".") : value)
    }
    const priced = fares.filter(fare => fare.price !== "" && fare.price != null && Number.isFinite(amount(fare)))
    const comparable = new Set(priced.map(fare => `${fare.currency}:${fare.price_unit}`)).size <= 1
    const primary = comparable ? priced.reduce((best, fare) => !best || amount(fare) < amount(best) ? fare : best, null) : priced[0]
    const main = primary || fares[0]
    if (main) for (const field of ["price", "currency", "price_unit", "price_basis"]) values[field] = main[field]
  }

  fareInput(element) {
    const item = this.items.find(row => row.id === element.dataset.item)
    const rows = item ? [item] : this.items.filter(row => row.program === element.dataset.program && !row.trip_id && !row.overrides.includes("fares"))
    const index = Number(element.dataset.fareIndex)
    rows.forEach(row => {
      row.values.fares[index][element.dataset.fareField] = element.value
      this.syncFarePrimary(row.values)
    })
    if (item && !item.overrides.includes("fares")) item.overrides.push("fares")
    this.acknowledge = false
    this.scheduleSave()
  }

  selectFare(button) {
    this.fareSelections.set(button.dataset.fareTab, Number(button.dataset.fareIndex))
    const item = this.items.find(row => row.id === button.dataset.item)
    const replacement = this.fareTabs(item ? { item } : { program: button.dataset.program })
    const parent = button.closest(".ai-fares")
    parent.outerHTML = replacement
    this.contentTarget.querySelector(`[data-fare-tab="${button.dataset.fareTab}"][aria-selected="true"]`)?.focus({ preventScroll: true })
  }

  fareKey(event) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const tabs = [...event.currentTarget.querySelectorAll('[role="tab"]')]
    const current = tabs.indexOf(event.target)
    const index = event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : (current + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length
    this.selectFare(tabs[index])
  }

  fareTabs({ item, program }) {
    const fares = item ? item.values.fares : this.commonValue(program, "fares")
    if (!fares?.length) return ""
    const scope = item ? `item-${item.id}` : `program-${program}`
    const active = Math.min(this.fareSelections.get(scope) || 0, fares.length - 1)
    const context = item ? `data-item="${item.id}"` : `data-program="${escape(program)}"`
    const prefix = `ai-fare-${this.task.id}-${scope}`
    const name = fare => `${fare.label || "Base doble"}${fare.hotel ? ` · ${fare.hotel}` : ""}`
    const fields = { label: "Nombre de la tarifa", price: "Precio final del proveedor", currency: "Moneda", price_basis: "Base de ocupación y tarifa", list_price: "Precio de lista (opcional)", hotel: "Hotel de esta tarifa (opcional)" }
    return `<section class="ai-fares ai-full" aria-label="Tarifas del programa"><div class="ai-subheading"><h4>Tarifas y bases de ocupación${item?.overrides.includes("fares") ? " · Personalizadas" : ""}</h4></div>${fares.length > 1 ? `<div class="ai-fare-tabs" role="tablist" aria-label="Tipos de tarifa" data-action="keydown->import-wizard#fareKey">${fares.map((fare, index) => `<button type="button" role="tab" id="${prefix}-tab-${index}" aria-controls="${prefix}-panel-${index}" aria-selected="${active === index}" tabindex="${active === index ? 0 : -1}" data-fare-tab="${scope}" data-fare-index="${index}" ${context}>${escape(name(fare))}</button>`).join("")}</div>` : `<h4 class="ai-fare-single">${escape(name(fares[0]))}</h4>`}${fares.map((fare, index) => `<div class="ai-fare-panel" ${fares.length > 1 ? `role="tabpanel" aria-labelledby="${prefix}-tab-${index}"` : 'role="group" aria-label="Tarifa Base doble"'} id="${prefix}-panel-${index}" ${index !== active ? "hidden" : ""}><div class="ai-fields">${Object.entries(fields).map(([field, label]) => {
      const attributes = `data-fare-field="${field}" data-fare-index="${index}" ${context}`
      const control = options[field] ? `<select ${attributes}>${field === "currency" ? "" : '<option value="">No informado</option>'}${options[field].map(([key, title]) => `<option value="${key}" ${key === fare[field] ? "selected" : ""}>${title}</option>`).join("")}</select>` : `<input type="text" ${attributes} value="${escape(fare[field])}" ${["price", "list_price"].includes(field) ? 'inputmode="decimal"' : ""} placeholder="${field === "price_basis" ? "Base doble" : "No informado"}">`
      return `<label class="ai-field ${field === "price_basis" ? "ai-full" : ""}"><span>${label}</span>${control}</label>`
    }).join("")}</div></div>`).join("")}<p class="ai-help">Si el flyer no indica la base, usamos Base doble. Cada salida conserva todas sus opciones tarifarias.</p></section>`
  }

  fareSummary(fares = []) {
    return `<span class="ai-fare-summary">${fares.map(fare => `<span><b>${escape(fare.label || "Base doble")}${fare.hotel ? ` · ${escape(fare.hotel)}` : ""}</b>${escape(this.fareMoney(fare))}</span>`).join("")}</span>`
  }

  field(field, value, { item, program } = {}) {
    const attributes = `data-field="${field}" ${item ? `data-item="${escape(item.id)}"` : `data-program="${escape(program)}"`}`
    let input
    if (options[field]) input = `<select ${attributes}><option value="">No informado</option>${options[field].map(([key, label]) => `<option value="${key}" ${key === value ? "selected" : ""}>${label}</option>`).join("")}</select>`
    else if (longFields.includes(field)) input = `<textarea ${attributes} rows="3" placeholder="No informado">${escape(value)}</textarea>`
    else {
      const type = field.endsWith("_on") ? "date" : field.startsWith("duration_") ? "number" : "text"
      input = `<input ${attributes} type="${type}" value="${escape(value)}" placeholder="No informado" ${field === "price" ? 'inputmode="decimal"' : ""} ${type === "number" ? `min="${field === "duration_days" ? 1 : 0}" step="1"` : ""}>`
    }
    return `<label class="ai-field ${longFields.includes(field) || field === "price_basis" ? "ai-full" : ""}"><span>${labels[field]}${item?.overrides.includes(field) ? ' <small class="ai-personalized">Personalizado</small>' : ""}</span>${input}</label>`
  }

  supplierSelect(value, attributes) {
    return `<select data-field="agent_supplier_id" ${attributes} aria-label="Empresa organizadora"><option value="">Seleccionar empresa</option>${(this.suppliers || []).map(supplier => `<option value="${supplier.id}" ${supplier.id === value ? "selected" : ""}>${escape(supplier.name)}${supplier.status === "paused" ? " (pausada)" : ""}</option>`).join("")}</select>`
  }

  supplierPicker(program) {
    const item = this.items.find(row => row.program === program)
    const selected = this.commonValue(program, "agent_supplier_id")
    return `<section class="ai-supplier ai-full"><label class="ai-field"><span>Empresa organizadora</span>${this.supplierSelect(selected, `data-program="${escape(program)}"`)}</label><p class="ai-supplier-status">Detectado por IA: <b>${escape(item.supplier_name || "No informado")}</b>. ${selected ? `Seleccionada: ${escape(this.supplierName(selected))}.` : item.supplier_candidates?.length > 1 ? "Hay varias coincidencias. Elegí la empresa correcta." : "Seleccioná una empresa o creala a continuación."}</p><details class="ai-full"><summary>Crear empresa sin perder la revisión</summary><div class="ai-new-supplier"><label class="ai-field"><span>Nombre de la nueva empresa</span><input data-new-supplier value="${escape(item.supplier_name)}" maxlength="200"></label><button type="button" class="btn" data-create-supplier="${escape(program)}">Crear empresa</button></div><small>Si ya existe una coincidencia confiable, se usa esa empresa.</small></details></section>`
  }

  heading(title, text, symbol = "spark") { return `<div class="ai-step-heading"><div><h3 tabindex="-1">${title}</h3><p>${text}</p></div><span class="ai-circle">${icon(symbol)}</span></div>` }

  render() {
    if (!this.dialogTarget.open) return
    const view = `${this.task?.id || "upload"}:${this.step}:${!!this.result}`
    const changed = this.lastView !== view
    this.lastView = view
    this.stepsTarget.innerHTML = ["Cargar flyer", "Información", "Viajes y fechas", "Confirmar"].map((label, index) => `<li ${index === this.step ? 'aria-current="step"' : ""} class="${index < this.step || this.result ? "ai-done" : ""}"><span>${index < this.step || this.result ? "✓" : index + 1}</span><b>${label}</b></li>`).join("")
    this.renderPreview()
    this.contentTarget.innerHTML = this.result ? this.successContent() : this.step === 0 ? this.uploadContent() : this.step === 1 ? this.sharedContent() : this.step === 2 ? this.departuresContent() : this.confirmContent()
    if (changed) {
      this.contentTarget.scrollTop = 0
      this.contentTarget.querySelector("h3")?.focus({ preventScroll: true })
    }
    this.updateActions()
  }

  renderPreview() {
    const url = this.task ? this.task.preview_url || (this.task.mime?.startsWith("image/") ? this.task.source_url : null) : this.file?.type === "application/pdf" ? null : this.objectUrl
    const name = this.task?.filename || this.file?.name
    this.previewTarget.innerHTML = `<div class="ai-preview-heading"><strong>FLYER DE ORIGEN</strong><span>REFERENCIA</span></div><div class="ai-flyer">${url ? `<img src="${escape(url)}" alt="Flyer original privado">` : `<div class="ai-preview-empty">${icon("file")}<p>${name ? "La vista previa estará disponible al procesar" : "Tu flyer aparecerá acá"}</p></div>`}</div><p class="ai-preview-filename">${escape(name || "JPG, PNG, WebP o PDF")}</p>${this.task ? `<a href="${escape(this.task.source_url)}" target="_blank" rel="noopener">Abrir original privado ↗</a>` : ""}${this.task?.status === "error" ? '<button class="btn ai-add" data-action="import-wizard#restart">Cargar otro flyer</button>' : ""}<div class="ai-rail-note"><b>Un flyer, varios viajes</b><p>Los detalles del programa se comparten; cada fecha se convierte en una ficha independiente.</p><span>${icon("calendar")}${this.items.length ? `${this.items.length} salidas detectadas` : "Una ficha por cada salida"}</span><span>${icon("users")}Empresa y datos editables</span><span>${icon("file")}El original siempre se conserva</span></div>`
  }

  uploadContent() {
    if (this.task && ["pending", "processing"].includes(this.task.status)) return `${this.heading("Estamos leyendo tu flyer", "La IA está extrayendo programas, empresas, fechas y tarifas.")}<div class="ai-processing" role="status"><span class="agent-spinner"></span><h4>${this.task.status === "pending" ? "Esperando el procesamiento" : "Procesando con Gemini"}</h4><p>Podés cerrar el asistente y volver más tarde. La importación continúa en segundo plano.</p></div>`
    if (this.task?.status === "error") return `${this.heading("No pudimos procesar el flyer", "Conservamos el original para que puedas reintentar.")}<p class="ai-notice">${escape(this.task.error)}</p><button class="btn" data-action="import-wizard#retry">Reintentar procesamiento</button>`
    return `${this.heading("Empezá por el flyer", "Subí el archivo de tu empresa proveedora. Vamos a separar todas las fechas de salida.")}<div class="ai-upload" data-action="dragover->import-wizard#drag dragleave->import-wizard#leave drop->import-wizard#drop"><span class="ai-circle">${icon("file")}</span><h4>Arrastrá tu flyer o elegí un archivo</h4><p>Extraemos la información para que puedas revisarla antes de crear tus viajes.</p><input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" aria-label="Archivo a importar" data-flyer-file><strong data-file-name>${escape(this.file?.name || "Ningún archivo seleccionado")}</strong><small>JPG, PNG, WebP o PDF · hasta 10 MB</small></div><div class="ai-notice">${icon("spark")}Cada salida genera un viaje independiente. Las tarifas y bases de ocupación se conservan dentro del mismo programa.</div>${this.history.length ? `<div class="ai-subheading"><h4>Retomar una importación</h4></div><div class="ai-history">${this.history.map(task => `<button type="button" data-resume="${escape(task.url)}"><span>${escape(task.filename)}</span><small>${({ completed: "Revisar", processing: "En proceso", pending: "Pendiente", error: "Reintentar" })[task.status]} →</small></button>`).join("")}</div>` : ""}`
  }

  sharedContent() {
    if (!this.programs.length) return `${this.heading("Esta importación ya tiene sus viajes", "Podés abrir los viajes creados o volver al listado.")}<div class="ai-created">${this.items.filter(item => item.trip_id).map(item => `<a href="/asesor/viajes/${encodeURIComponent(item.trip_id)}">${escape(item.values.title)} · ${dateLabel(item.values.departs_on)} ↗</a>`).join("")}</div>`
    return `${this.heading("Revisá la información extraída", "Corregí los datos compartidos. Después podés personalizar cada salida.")}${this.task.duplicate_files ? '<p class="ai-notice ai-warning">Este archivo ya tiene otras importaciones. Revisá las coincidencias antes de crear viajes.</p>' : ""}${this.programs.map((program, index) => `<section class="ai-program">${this.programs.length > 1 ? `<div class="ai-subheading"><h4>Programa ${index + 1} · ${escape(this.commonValue(program, "destination") || "Destino pendiente")}</h4></div>` : ""}<div class="ai-fields">${this.supplierPicker(program)}${commonFields.filter(field => field !== "conditions").map(field => this.field(field, this.commonValue(program, field), { program })).join("")}${this.fareTabs({ program })}${this.field("conditions", this.commonValue(program, "conditions"), { program })}</div>${this.programWarnings(program)}</section>`).join("")}`
  }

  programWarnings(program) {
    const warnings = [...new Set(this.items.filter(item => item.program === program).flatMap(item => item.warnings || []))]
    return warnings.length ? `<details class="ai-evidence"><summary>Advertencias de la extracción (${warnings.length})</summary>${warnings.map(warning => `<p>${escape(warning)}</p>`).join("")}</details>` : ""
  }

  departuresContent() {
    const past = this.selected.filter(item => item.values.departs_on && item.values.departs_on < this.task.today).length
    return `${this.heading("Un viaje por cada fecha", "Seleccioná las salidas que querés crear y revisá sus datos particulares.", "calendar")}<div class="ai-review-total"><strong>${this.selected.length} viajes seleccionados para crear</strong><span class="ai-draft-badge">Borradores</span></div>${past ? `<p class="ai-notice ai-warning">${past} salida(s) son anteriores a hoy. Conservamos el año cuando el mes coincide con el actual. Podés guardarlas como borradores; la publicación mantiene sus validaciones.</p>` : ""}<div class="ai-review-list">${this.items.map(item => this.departureRow(item)).join("")}</div>${this.programs.map(program => `<button class="btn ai-add" type="button" data-add="${this.items.find(item => item.program === program && !item.trip_id).id}">${icon("plus")}Agregar salida${this.programs.length > 1 ? ` · ${escape(this.commonValue(program, "destination"))}` : ""}</button>`).join("")}`
  }

  departureRow(item) {
    const data = item.values
    const open = this.expanded.has(item.id)
    return `<article class="ai-review-row ${item.selected ? "ai-selected" : ""} ${item.trip_id ? "ai-saved" : ""}"><div class="ai-review-summary"><input type="checkbox" aria-label="Crear salida ${escape(dateLabel(data.departs_on))}" data-enabled="${item.id}" ${item.selected ? "checked" : ""} ${item.trip_id ? "disabled" : ""}><div class="ai-row-main"><strong data-row-title>${escape(data.title || "Viaje sin título")}</strong><small>${escape(this.supplierName(data.agent_supplier_id))}</small><span data-row-date>${dateLabel(data.departs_on)}</span></div><span class="ai-row-price">${escape(this.fareMoney(data))}${data.fares?.length > 1 ? `<small>${data.fares.length} tarifas</small>` : ""}</span>${item.trip_id ? '<span class="ai-draft-badge">Ya creado</span>' : `<button type="button" data-expand="${item.id}" aria-expanded="${open}" class="ai-edit">${open ? "Cerrar" : "Editar"} ↓</button>`}</div>${open && !item.trip_id ? `<div class="ai-review-details"><div class="ai-fields"><label class="ai-field ai-full"><span>Empresa organizadora</span>${this.supplierSelect(data.agent_supplier_id, `data-item="${item.id}"`)}</label>${["title", "departs_on", "returns_on", ...commonFields.filter(field => field !== "title")].map(field => this.field(field, data[field], { item })).join("")}${this.fareTabs({ item })}</div>${item.departure_text ? `<p class="ai-help">Texto original de la salida: ${escape(item.departure_text)}</p>` : ""}<details class="ai-evidence"><summary>Ver evidencia del flyer</summary>${Object.entries(item.evidence || {}).map(([field, quote]) => `<p><b>${escape(labels[field] || field)}:</b> ${escape(quote)}</p>`).join("") || "No informada"}</details></div>` : ""}</article>`
  }

  duplicateItems() {
    const seen = new Set()
    return this.selected.filter(item => {
      const key = [item.values.agent_supplier_id, (item.values.destination || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim(), item.values.departs_on].join("|")
      const repeated = seen.has(key)
      seen.add(key)
      return item.duplicates?.length || repeated
    })
  }

  confirmContent() {
    const conflicts = this.duplicateItems()
    const missing = this.selected.filter(item => (item.values.fares || []).some(fare => !fare.price)).length
    return `${this.heading("Todo listo para crear tus viajes", "Revisá el resumen final. Cada salida se guarda con su propia revisión y el flyer original.", "file")}<div class="ai-review-total"><strong>${this.selected.length} viajes como borradores</strong><span class="ai-draft-badge">Revisión humana</span></div><div class="ai-created">${this.selected.map(item => `<div><div><b>${escape(item.values.title || "Viaje sin título")}</b><small>${escape(this.supplierName(item.values.agent_supplier_id))} · ${escape(item.values.destination)}<br>${escape(item.values.hotel || "Hotel no informado")} · ${escape(item.values.duration_days || "?")} días / ${escape(item.values.duration_nights ?? "?")} noches · ${escape(item.values.meal_plan || "Comidas no informadas")} · ${escape(item.values.transport || "Transporte no informado")}</small></div><strong>${dateLabel(item.values.departs_on)}</strong><span>${this.fareSummary(item.values.fares)}</span></div>`).join("")}</div>${this.programs.map(program => this.programWarnings(program)).join("")}${missing ? `<p class="ai-notice ai-warning">${missing} viaje(s) necesitan revisión de precio o moneda antes de publicar.</p>` : ""}${conflicts.length ? `<section class="ai-notice ai-warning ai-conflicts"><b>Posibles duplicados</b>${conflicts.map(item => `<p>${escape(item.values.title)} · ${dateLabel(item.values.departs_on)}: ${item.duplicates?.length ? item.duplicates.map(trip => `<a href="/asesor/viajes/${encodeURIComponent(trip.id)}" target="_blank" rel="noopener">Revisar ${escape(trip.title)} ↗</a>`).join(", ") : "Otra salida seleccionada tiene la misma empresa, destino y fecha."}</p>`).join("")}<label><input type="checkbox" data-acknowledge ${this.acknowledge ? "checked" : ""}> Revisé las coincidencias y quiero crear nuevos borradores.</label></section>` : ""}<p class="ai-notice">Nada se publica automáticamente. Podrás completar y publicar cada viaje desde Borradores.</p>`
  }

  successContent() {
    return `<div class="ai-success-icon">✓</div>${this.heading(`${this.result.count} viajes creados correctamente`, "Cada salida tiene su propia ficha. Los encontrás en la pestaña Borradores.")}<div class="ai-notice ai-success">El flyer original quedó asociado a cada viaje.</div><div class="ai-created">${this.result.trips.map(trip => `<a href="${escape(trip.url)}"><span><b>${escape(trip.title)}</b><small>${dateLabel(trip.departs_on)}</small></span><span class="ai-draft-badge">Abrir borrador ↗</span></a>`).join("")}</div>`
  }

  updateActions() {
    const button = (label, action, primary = false, disabled = false) => `<button type="button" class="btn ${primary ? "btn-primary" : ""}" data-action="import-wizard#${action}" ${this.busy || disabled ? "disabled" : ""}>${label}</button>`
    if (this.result) { this.actionsTarget.innerHTML = button("Ver borradores", "close", true); return }
    const processing = this.task && ["pending", "processing"].includes(this.task.status)
    this.actionsTarget.innerHTML = button(processing ? "Cerrar y continuar después" : "Cancelar", "close") + (this.step >= 1 ? button("Atrás", "back") : "") + (this.step === 0 ? !this.task ? button(this.busy ? "Subiendo flyer…" : "Procesar con IA", "next", true, !this.file && !this.retainedCover) : "" : this.step === 3 ? button(this.busy ? "Creando viajes…" : `Crear ${this.selected.length} viajes como borradores`, "confirm", true, !this.selected.length) : button(this.busy ? "Guardando…" : this.step === 1 ? "Revisar viajes y fechas" : "Continuar al resumen", "next", true, !this.programs.length))
  }
}
