import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.events = new AbortController()
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.stacked = window.matchMedia("(max-width: 900px)")
    this.steps = this.findAll(".step")
    this.visuals = this.findAll(".vis")
    this.tour = this.find("#tourWrap")
    this.activeStep = -1

    this.listen(window, "scroll", () => {
      if (this.scrollFrame) return
      this.scrollFrame = requestAnimationFrame(() => {
        this.updateScroll()
        this.scrollFrame = null
      })
    }, { passive: true })
    this.listen(window, "resize", () => this.layout())
    this.listen(document, "keydown", event => {
      if (event.key === "Escape" && this.menuOpen) {
        this.closeMenu()
        this.find("#menuButton").focus()
      }
    })
    this.findAll("#mobileMenu a").forEach(link => this.listen(link, "click", () => this.closeMenu()))
    this.steps.forEach((step, index) => {
      this.listen(step, "click", () => this.chooseStep(index))
      this.listen(step, "keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          this.chooseStep(index)
        }
      })
    })

    this.revealContent()
    if (this.find("#demoRole")) this.paintRole(this.find("#demoRole").value)
    this.layout()
    document.fonts?.ready.then(() => {
      if (this.element.isConnected) this.layout()
    })
  }

  disconnect() {
    this.events.abort()
    this.revealObserver?.disconnect()
    cancelAnimationFrame(this.scrollFrame)
    this.element.classList.remove("landing-enhanced")
    this.closeMenu()
  }

  find(selector) { return this.element.querySelector(selector) }
  findAll(selector) { return Array.from(this.element.querySelectorAll(selector)) }

  listen(element, event, callback, options = {}) {
    element.addEventListener(event, callback, { ...options, signal: this.events.signal })
  }

  revealContent() {
    if (this.reducedMotion || !("IntersectionObserver" in window)) return

    this.revealObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in")
          this.revealObserver.unobserve(entry.target)
        }
      })
    }, { rootMargin: "0px 0px -3% 0px", threshold: 0.01 })
    this.findAll("[data-reveal]").forEach(element => {
      const bounds = element.getBoundingClientRect()
      if (bounds.top < window.innerHeight && bounds.bottom > 0) element.classList.add("is-in")
      this.revealObserver.observe(element)
    })
    this.element.classList.add("landing-enhanced")
  }

  layout() {
    this.findAll("[data-shot]").forEach(shot => {
      const [width, height] = shot.dataset.shot.split("x").map(Number)
      const wrapper = shot.parentElement
      wrapper.style.maxWidth = `${width}px`
      const scale = Math.min(1, wrapper.clientWidth / width)
      shot.style.transform = `scale(${scale})`
      wrapper.style.height = `${Math.round(height * scale)}px`
    })
    this.activeStep = -1
    if (this.stacked.matches) {
      this.steps.forEach(step => step.classList.add("is-active"))
      this.visuals.forEach(visual => {
        visual.classList.add("is-active")
        visual.removeAttribute("aria-hidden")
      })
    }
    this.updateScroll()
  }

  updateScroll() {
    const scroll = window.scrollY
    this.find("#nav").classList.toggle("is-stuck", scroll > 12)
    if (!this.reducedMotion && this.find("#heroStage")) this.find("#heroStage").style.transform = `translate3d(0,${Math.min(scroll * 0.1, 130)}px,0)`

    const links = this.findAll(".nav-links a")
    let active = 0
    links.forEach((link, index) => {
      if (this.find(link.hash).getBoundingClientRect().top <= 150) active = index
    })
    links.forEach((link, index) => link.classList.toggle("is-active", index === active))
    this.updateTour()
  }

  updateTour() {
    if (this.stacked.matches || !this.tour) return
    const bounds = this.tour.getBoundingClientRect()
    const distance = bounds.height - window.innerHeight
    if (distance <= 0) return
    const progress = Math.min(1, Math.max(0, -bounds.top / distance)) * this.steps.length
    const active = Math.min(this.steps.length - 1, Math.floor(progress))
    this.activeStep = active
    this.steps.forEach((step, index) => {
      step.classList.toggle("is-active", index === active)
      step.setAttribute("aria-pressed", String(index === active))
      step.querySelector(".step-bar i").style.width = `${index < active ? 100 : index === active ? Math.min(1, progress - active) * 100 : 0}%`
    })
    this.visuals.forEach((visual, index) => {
      visual.classList.toggle("is-active", index === active)
      visual.setAttribute("aria-hidden", String(index !== active))
    })
  }

  chooseStep(index) {
    if (this.stacked.matches) return
    const top = this.tour.getBoundingClientRect().top + window.scrollY
    const distance = this.tour.offsetHeight - window.innerHeight
    window.scrollTo({ top: top + distance * (index + 0.15) / this.steps.length, behavior: this.reducedMotion ? "instant" : "smooth" })
  }

  toggleMenu() {
    this.setMenu(!this.menuOpen)
  }

  closeMenu() { this.setMenu(false) }

  setMenu(open) {
    this.menuOpen = open
    this.find("#mobileMenu").classList.toggle("is-open", open)
    const button = this.find("#menuButton")
    button.setAttribute("aria-expanded", String(open))
    button.setAttribute("aria-label", open ? "Cerrar menú" : "Abrir menú")
  }

  changeRole(event) { this.paintRole(event.target.value) }

  setText(id, value) { this.find(`#${id}`).textContent = value }

  paintRole(role) {
    const data = DEMO_ROLES[role] || DEMO_ROLES.admin
    this.setText("appCrumbRole", data.crumb)
    this.setText("appCrumbTitle", data.title)
    data.kpis.forEach((kpi, index) => {
      ;["Label", "Value", "Chip"].forEach((part, column) => this.setText(`kpi${index + 1}${part}`, kpi[column]))
    })
    this.setText("appChartTitle", data.chart)
    ;["Metric", "Value", "Prev"].forEach((part, index) => this.setText(`chartTip${part}`, data.tip[index]))
    this.find("#demoChartLine").setAttribute("d", data.path)
    this.setText("appTableTitle", data.table)
    this.setText("appTableBadge", data.badge)
    data.columns.forEach((column, index) => this.setText(`col${index + 1}`, column))
    this.setText("appSidePct", data.pct)
    this.setText("appSideNote", data.side)
    this.find("#appSideBar").style.width = data.pct

    const rows = data.rows.map((values, index) => {
      const row = document.createElement("div")
      row.className = "row"
      const name = document.createElement("span")
      name.className = "rname"
      const dot = document.createElement("i")
      dot.className = `dot c${index % 4 + 1}`
      name.append(dot, document.createTextNode(values[0]))
      row.append(name)
      values.slice(1, 4).forEach((value, column) => {
        const cell = document.createElement("span")
        cell.textContent = value
        if (column === 2) cell.className = "rnum"
        row.append(cell)
      })
      const occupancy = document.createElement("span")
      occupancy.className = "occupancy"
      const label = document.createElement("span")
      label.className = "occupancy-label"
      label.textContent = role === "admin" ? `${values[4]}% ocupado` : `${role === "coordinator" ? "Embarcado" : "Registrado"} ${values[4]}%`
      const bar = document.createElement("span")
      bar.className = "bar"
      const fill = document.createElement("i")
      fill.style.width = `${values[4]}%`
      bar.append(fill)
      occupancy.append(label, bar)
      const status = document.createElement("span")
      status.className = "pill-status"
      if (["Solicitada", "Pendiente", "En curso"].includes(values[5])) status.classList.add("pending")
      status.textContent = values[5]
      row.append(occupancy, status)
      return row
    })
    this.find("#appRows").replaceChildren(...rows)

    const navigation = DEMO_NAVIGATION[role] || DEMO_NAVIGATION.admin
    ;["#appNavigation", "#appNavigationBottom"].forEach((selector, group) => {
      const items = navigation[group].map(([icon, title], index) => {
        const item = document.createElement("li")
        if (group === 0 && index === 0) item.className = "is-active"
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
        svg.classList.add("ic")
        svg.setAttribute("aria-hidden", "true")
        const use = document.createElementNS("http://www.w3.org/2000/svg", "use")
        use.setAttribute("href", `#i-${icon}`)
        svg.append(use)
        item.append(svg, document.createTextNode(title))
        return item
      })
      this.find(selector).replaceChildren(...items)
    })
  }
}

const DEMO_NAVIGATION = {
  admin: [
    [["grid", "Panel general"], ["calendar", "Salidas"], ["suitcase", "Paquetes y ofertas"], ["ticket", "Reservas"], ["users", "Pasajeros"]],
    [["money", "Cobros y rendiciones"], ["layers", "Comisiones"], ["route", "Operación"]]
  ],
  reseller: [
    [["grid", "Mis ventas"], ["suitcase", "Viajes disponibles"], ["ticket", "Mis reservas"], ["users", "Mis pasajeros"]],
    [["money", "Mis cobros"], ["receipt", "Mis rendiciones"], ["layers", "Mis comisiones"]]
  ],
  coordinator: [
    [["grid", "Mis salidas"], ["route", "Hoja de ruta"], ["users", "Lista de pasajeros"], ["check", "Embarque"]],
    [["pin", "Puntos de parada"], ["doc", "Manifiestos"], ["bell", "Notificaciones"]]
  ]
}
// Illustrative data for the public product preview; no customer records are loaded.
const DEMO_ROLES = {
  "admin": {
    "crumb": "Administración",
    "title": "Vista general",
    "kpis": [
      [
        "Salidas activas",
        "4",
        "Próximos viajes"
      ],
      [
        "Pasajeros confirmados",
        "128",
        "Sobre 180 lugares"
      ],
      [
        "Cupos disponibles",
        "52",
        "Calculados por micro"
      ]
    ],
    "chart": "Reservas confirmadas por semana",
    "tip": [
      "Reservas",
      "24",
      "19"
    ],
    "table": "Próximas salidas",
    "badge": "4 salidas",
    "columns": [
      "Destino",
      "Fecha",
      "Micro",
      "Pasajeros",
      "Ocupación",
      "Estado"
    ],
    "pct": "71%",
    "side": "128 de 180 lugares · ejemplo",
    "path": "M0,132 C52,128 78,113 130,109 C182,105 208,117 260,107 C312,97 338,73 390,69 C442,65 468,81 520,63 C572,45 596,35 620,29",
    "rows": [
      [
        "Mendoza · Super Sale",
        "28 oct",
        "Micro 01",
        "38 / 45",
        84,
        "Abierta"
      ],
      [
        "Bariloche y sus lagos",
        "04 nov",
        "Micro 02",
        "29 / 45",
        64,
        "Abierta"
      ],
      [
        "Córdoba serrana",
        "12 nov",
        "Micro 03",
        "34 / 45",
        76,
        "Abierta"
      ],
      [
        "Mar del Plata",
        "19 nov",
        "Micro 04",
        "27 / 45",
        60,
        "Abierta"
      ]
    ]
  },
  "reseller": {
    "crumb": "Revendedor",
    "title": "Mis ventas",
    "kpis": [
      [
        "Reservas registradas",
        "14",
        "En tus viajes"
      ],
      [
        "Pasajeros vendidos",
        "27",
        "Solo tus clientes"
      ],
      [
        "Comisiones devengadas",
        "$ 412.000",
        "Sin liquidar"
      ]
    ],
    "chart": "Mis reservas por semana",
    "tip": [
      "Reservas",
      "8",
      "6"
    ],
    "table": "Mis próximas reservas",
    "badge": "Solo mis ventas",
    "columns": [
      "Viaje",
      "Fecha",
      "Reserva",
      "Pasajeros",
      "Seña registrada",
      "Estado"
    ],
    "pct": "62%",
    "side": "14 reservas · ejemplo",
    "path": "M0,151 C48,144 80,137 130,133 C178,130 210,117 260,113 C309,106 344,118 390,99 C443,93 470,74 520,65 C569,52 602,56 620,39",
    "rows": [
      [
        "Mendoza · Super Sale",
        "28 oct",
        "TS-1048",
        "2 pax",
        100,
        "Confirmada"
      ],
      [
        "Bariloche y sus lagos",
        "04 nov",
        "TS-1051",
        "4 pax",
        70,
        "Confirmada"
      ],
      [
        "Córdoba serrana",
        "12 nov",
        "TS-1055",
        "3 pax",
        100,
        "Confirmada"
      ],
      [
        "Mar del Plata",
        "19 nov",
        "TS-1060",
        "2 pax",
        30,
        "Solicitada"
      ]
    ]
  },
  "coordinator": {
    "crumb": "Coordinación",
    "title": "Mis salidas",
    "kpis": [
      [
        "Salidas asignadas",
        "2",
        "Próximas salidas"
      ],
      [
        "Pasajeros en lista",
        "67",
        "Viajes asignados"
      ],
      [
        "Embarques pendientes",
        "11",
        "Para verificar"
      ]
    ],
    "chart": "Embarques registrados por parada",
    "tip": [
      "Embarques",
      "18",
      "12"
    ],
    "table": "Mis puntos de embarque",
    "badge": "Micro 01",
    "columns": [
      "Parada",
      "Horario",
      "Salida",
      "Pasajeros",
      "Progreso",
      "Estado"
    ],
    "pct": "84%",
    "side": "56 de 67 embarcados · ejemplo",
    "path": "M0,151 C50,145 91,134 130,132 C186,130 201,124 260,109 C306,95 349,95 390,90 C449,79 477,54 520,53 C569,44 604,22 620,17",
    "rows": [
      [
        "Terminal Varela",
        "14:30",
        "MZA-2810",
        "16 pax",
        100,
        "Completada"
      ],
      [
        "Rotonda Llavallol",
        "15:30",
        "MZA-2810",
        "14 pax",
        100,
        "Completada"
      ],
      [
        "Terminal San Justo",
        "16:30",
        "MZA-2810",
        "18 pax",
        88,
        "En curso"
      ],
      [
        "Morón",
        "17:30",
        "MZA-2810",
        "19 pax",
        0,
        "Pendiente"
      ]
    ]
  }
}
