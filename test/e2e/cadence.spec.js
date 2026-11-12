const { test, expect } = require("@playwright/test")
const port = process.env.E2E_PORT || "3100"
const platform = `http://localhost:${port}`
const agent = `http://agente.lvh.me:${port}`

async function expectCadence(page) {
  // The auth host has its own document/stylesheets after the OAuth redirect.
  await expect(page.locator("html")).toHaveCSS("color-scheme", "light")
  const appearance = await page.evaluate(() => {
    const root = getComputedStyle(document.documentElement)
    return {
      scheme: root.colorScheme,
      font: getComputedStyle(document.body).fontFamily,
      ink: root.getPropertyValue("--cadence-ink").trim(),
      background: root.getPropertyValue("--cadence-bg").trim(),
      overflow: document.documentElement.scrollWidth > innerWidth
    }
  })
  expect(appearance.scheme).toBe("light")
  expect(appearance.font).toContain("Inter")
  expect(appearance.ink).toBe("#0a0a0c")
  expect(appearance.background).toBe("#fafafa")
  expect(appearance.overflow).toBe(false)
}

test("Google access and expired requests share the light Cadence design", async ({ page }, testInfo) => {
  await page.goto(`${platform}/agente/alta`)
  await expectCadence(page)
  await page.getByRole("button", { name: "Ingresar con Google", exact: true }).click()
  await expect(page.getByRole("heading", { name: "Continuar con Google" })).toBeVisible()
  await expectCadence(page)
  const button = page.getByRole("button", { name: "Ingresar con Google", exact: true })
  await expect(button).toHaveCSS("background-color", "rgb(10, 10, 12)")
  await expect(page.locator(".access-card")).toHaveCSS("background-color", "rgb(255, 255, 255)")
  await page.screenshot({ path: testInfo.outputPath("cadence-access.png"), fullPage: true })

  const auth = new URL(page.url()).origin
  await page.route("https://accounts.google.com/**", route => route.fulfill({ contentType: "text/html", body: "<title>Google OAuth test destination</title>" }))
  await button.click()
  await expect(page).toHaveURL(/^https:\/\/accounts\.google\.com\//)
  await page.goto(`${auth}/auth/continue?request_token=expired`)
  await expect(page.getByRole("heading", { name: "Volvé a iniciar sesión" })).toBeVisible()
  await expectCadence(page)
  await expect(page.getByRole("link", { name: "Volver a Turistack" })).toHaveAttribute("href", `${platform}/`)
})

test("administrative screens and forms keep the same Cadence foundation", async ({ page }, testInfo) => {
  await page.goto("/test/sign-in?email=demo%40turistack.local&role=admin")
  for (const path of ["/dashboard", "/ofertas", "/ofertas/new", "/paquetes", "/paquetes/new", "/salidas", "/salidas/new", "/reservas", "/pagos", "/rendiciones", "/comisiones", "/catalogos", "/equipo", "/notificaciones"]) {
    const response = await page.goto(path)
    expect(response.status(), path).toBe(200)
    await expectCadence(page)
    await expect(page.locator("#main-sidebar")).toHaveCSS("background-color", "rgb(255, 255, 255)")
  }
  await page.goto("/ofertas/new")
  await page.screenshot({ path: testInfo.outputPath("cadence-admin-form.png"), fullPage: true })
})

test("agent workspace screens keep the same Cadence foundation", async ({ page }, testInfo) => {
  await page.goto(`${agent}/test/sign-in?email=agente%40turistack.local`)
  for (const path of ["/agente", "/agente/empresas", "/agente/empresas/new", "/agente/viajes", "/agente/viajes/new", "/agente/importaciones", "/agente/mi-web", "/agente/buscador"]) {
    const response = await page.goto(`${agent}${path}`)
    expect(response.status(), path).toBe(200)
    await expectCadence(page)
  }
  await page.goto(`${agent}/agente/viajes/new`)
  await page.screenshot({ path: testInfo.outputPath("cadence-agent-form.png"), fullPage: true })
})

test("public trips catalogs passenger states and errors stay light even with a dark system theme", async ({ page }, testInfo) => {
  await page.emulateMedia({ colorScheme: "dark" })
  for (const path of ["/", "/viajes/mendoza-super-sale", "/formularios/invalid", "/400.html", "/403.html", "/404.html", "/422.html", "/500.html", "/406-unsupported-browser.html"]) {
    await page.goto(path)
    await expectCadence(page)
  }
  await page.goto("/viajes/mendoza-super-sale")
  await expect(page.locator(".public-hero")).toHaveCSS("color", "rgb(10, 10, 12)")
  await page.screenshot({ path: testInfo.outputPath("cadence-public-trip.png"), fullPage: true })
  await page.goto(agent)
  await expectCadence(page)
})
