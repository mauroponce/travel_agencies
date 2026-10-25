const { test, expect } = require("@playwright/test")
const path = require("path")
const port = process.env.E2E_PORT || "3100"
const base = `http://agente.lvh.me:${port}`

async function signIn(page) {
  await page.goto(`${base}/test/sign-in?email=agente%40turistack.local`)
  await expect(page.getByRole("heading", { name: "Todo listo para tu próximo viaje" })).toBeVisible()
}

test("agent has independent onboarding without company invitation", async ({ page }, testInfo) => {
  const slug = `alta-${testInfo.project.name}-${Date.now()}`
  await page.goto(`http://platform.lvh.me:${port}/test/sign-in?email=agente-nuevo-${testInfo.project.name}%40turistack.local&purpose=agent_onboarding`)
  if (await page.getByRole("button", { name: "Crear mi espacio" }).isVisible()) {
    await page.getByLabel("Nombre comercial").fill("Viajes independientes")
    await page.getByLabel("Nombre público").fill("Lucía")
    await page.getByLabel("WhatsApp con código de país").fill("5491155551234")
    await page.getByLabel("Subdominio", { exact: false }).fill(slug)
    await page.getByRole("button", { name: "Crear mi espacio" }).click()
  }
  await expect(page.getByRole("link", { name: "Ingresar a mi espacio" })).toBeVisible()
})

test("agent provider management and manual catalog comparison work on every device", async ({ page }, testInfo) => {
  await signIn(page)
  if (testInfo.project.name.startsWith("desktop")) {
    await page.getByRole("button", { name: "Contraer menú lateral" }).click()
    await expect(page.getByRole("button", { name: "Expandir menú lateral" })).toHaveAttribute("aria-expanded", "false")
    await expect(page.locator(".agent-shell")).toHaveClass(/agent-sidebar-collapsed/)
    await expect(page.locator("#main-sidebar")).toHaveCSS("width", "80px")
    await page.getByRole("button", { name: "Expandir menú lateral" }).click()
  }
  await page.goto(`${base}/agente/empresas/new`)
  const name = `Operador ${testInfo.project.name}`
  await page.getByLabel("Nombre de la empresa").fill(name)
  await page.getByLabel("Comisión acordada").fill("15% privado")
  await page.getByRole("button", { name: "Guardar empresa" }).click()
  await expect(page.getByRole("heading", { name })).toBeVisible()
  await page.getByRole("link", { name: "Editar empresa" }).click()
  await page.getByLabel("Estado", { exact: true }).selectOption("paused")
  await page.getByRole("button", { name: "Guardar empresa" }).click()
  await expect(page.getByText("Pausada", { exact: true })).toBeVisible()
  await page.goto(`${base}/agente/viajes/new`)
  await page.getByLabel("Empresa proveedora").selectOption({ label: "Proveedor demo" })
  await page.getByLabel("Título del viaje").fill(`Mendoza manual ${testInfo.project.name}`)
  await page.getByLabel("Destino", { exact: true }).fill("Mendoza")
  await page.getByLabel("Fecha de salida").fill("2027-08-10")
  await page.getByLabel("Precio final del proveedor").fill("550000")
  await page.getByLabel("Moneda", { exact: true }).selectOption("ARS")
  await page.getByLabel("Unidad del precio").selectOption("per_person")
  await page.getByRole("button", { name: "Guardar y publicar" }).click()
  await expect(page.getByRole("heading", { name: `Mendoza manual ${testInfo.project.name}` })).toBeVisible()
  await page.goto(`${base}/agente/viajes`)
  await page.getByRole("checkbox").nth(0).check()
  await page.getByRole("checkbox").nth(1).check()
  await page.getByRole("button", { name: "Comparar seleccionados" }).click()
  await expect(page.getByRole("heading", { name: "Comparar viajes", exact: true })).toBeVisible()
  await expect(page.getByRole("table")).toBeVisible()
  const scroll = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)
  expect(scroll).toBe(false)
  if (testInfo.project.name.startsWith("mobile")) {
    await page.getByRole("button", { name: "Abrir menú" }).click()
    await expect(page.getByRole("link", { name: "Importar con IA", exact: true })).toBeVisible()
    await page.keyboard.press("Escape")
  }
})

test("Gemini import review creates a supplier without losing corrections and publishes publicly", async ({ page, browser }, testInfo) => {
  await signIn(page)
  await page.goto(`${base}/agente/importaciones`)
  await page.getByLabel("Archivo a importar").setInputFiles(path.join(__dirname, "../fixtures/files/agent.png"))
  await page.getByRole("button", { name: "Procesar con IA" }).click()
  await expect(page.getByRole("heading", { name: "Revisá las fichas extraídas" })).toBeVisible()
  await expect(page.getByRole("link", { name: "Revisar ficha" })).toHaveCount(2)
  await page.getByRole("link", { name: "Revisar ficha" }).first().click()
  const title = `Córdoba revisada ${testInfo.project.name}`
  await page.getByLabel("Título", { exact: true }).fill(title)
  await page.getByText("Crear empresa sin perder la revisión").click()
  const supplier = `Proveedor importado ${testInfo.project.name}`
  await page.getByLabel("Nombre de la nueva empresa").fill(supplier)
  await page.getByRole("button", { name: "Crear empresa y conservar revisión" }).click()
  await expect(page.getByLabel("Título", { exact: true })).toHaveValue(title)
  await expect(page.getByLabel("Empresa proveedora")).toHaveValue(/.+/)
  await page.getByRole("button", { name: "Guardar y publicar" }).click()
  await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible()
  const publicContext = await browser.newContext()
  const visitor = await publicContext.newPage()
  await visitor.goto(base)
  await visitor.getByRole("link", { name: title, exact: true }).click()
  await expect(visitor.getByRole("heading", { name: title, exact: true })).toBeVisible()
  await expect(visitor.getByRole("link", { name: "Consultar por WhatsApp" })).toHaveAttribute("href", /^https:\/\/wa\.me\/5491155550303\?text=/)
  await publicContext.close()
  await page.goto(`${base}/agente/mi-web`)
  await expect(page.frameLocator('iframe[title="Vista previa del catálogo"]').getByRole("heading", { name: "Viajes para descubrir" })).toBeVisible()
  await page.getByRole("button", { name: "Celular", exact: true }).click()
  await page.goto(`${base}/agente/buscador`)
  await page.getByLabel("¿Qué viaje necesita tu cliente?").fill("Córdoba por menos de $600000 por persona")
  await page.getByRole("button", { name: "Buscar viajes", exact: true }).click()
  await expect(page.getByRole("heading", { name: "Criterios interpretados" })).toBeVisible()
  await expect(page.getByRole("link", { name: title, exact: true })).toBeVisible()
  await page.getByText("Por qué aparece", { exact: true }).first().click()
  await expect(page.getByText("Destino registrado: Córdoba", { exact: true }).first()).toBeVisible()
  await page.getByRole("link", { name: "Editar filtros en el catálogo" }).click()
  await expect(page.getByLabel("Destino", { exact: true })).toHaveValue("Córdoba")
})
