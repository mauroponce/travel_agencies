const { test, expect } = require("@playwright/test")
const base = `http://localhost:${process.env.E2E_PORT || "3100"}`
test.use({ actionTimeout: 10000 })

async function tripFactory(page) {
  // Give each scenario its own owner/workspace instead of competing with the
  // existing import/sharing tests for the shared demo workspace's write lock.
  const auth = base.replace("localhost", "auth.localhost")
  const identity = await (await page.request.get(`${auth}/test/pro-lifecycle/prepare`)).json()
  await page.goto(`${base}/test/sign-in?email=${encodeURIComponent(identity.email)}&purpose=agent_onboarding`)
  await page.getByLabel("Nombre", { exact: true }).fill("Asesor de la tabla")
  await page.getByLabel("Link público", { exact: true }).fill(`tabla-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`)
  await page.getByLabel("WhatsApp con código de país").fill("5491155551234")
  await page.getByRole("button", { name: "Crear mi espacio" }).click()
  await expect(page.getByRole("heading", { name: "Todo listo para tu próximo viaje" })).toBeVisible()
  await page.goto(`${base}/asesor/empresas/nuevo`)
  await page.getByLabel("Nombre del proveedor").fill("Proveedor de la tabla")
  await page.getByRole("button", { name: "Guardar proveedor" }).click()
  await expect(page.getByRole("heading", { name: "Proveedor de la tabla", exact: true })).toBeVisible()
  await page.goto(`${base}/asesor/viajes/nuevo`)
  const supplier = await page.getByLabel("Proveedor", { exact: true }).locator('option:not([value=""])').first().getAttribute("value")
  const token = await page.locator('meta[name="csrf-token"]').getAttribute("content")
  const headers = { "X-CSRF-Token": token }
  return async (title, status = "published", incomplete = false) => {
    const form = { "agent_trip_revision[agent_supplier_id]": supplier, commit_action: status === "published" || status === "unpublished" ? "publish" : "draft" }
    if (!incomplete) Object.assign(form, {
      "agent_trip_revision[title]": title,
      "agent_trip_revision[destination]": "Río Negro",
      "agent_trip_revision[departs_on]": "2030-11-20",
      "agent_trip_revision[duration_days]": "8",
      "agent_trip_revision[duration_nights]": "0",
      "agent_trip_revision[price]": "700",
      "agent_trip_revision[currency]": "USD",
      "agent_trip_revision[price_unit]": "per_group"
    })
    else form["agent_trip_revision[title]"] = title
    const response = await page.request.post(`${base}/asesor/viajes`, { form, headers, maxRedirects: 0 })
    expect(response.status()).toBe(302)
    const url = response.headers().location
    if (status === "unpublished" || status === "archived") {
      const action = status === "unpublished" ? "despublicar" : "archivar"
      expect((await page.request.post(`${url}/${action}`, { headers, maxRedirects: 0 })).status()).toBe(303)
    }
    return url
  }
}

test("three real tabs paginate filtered rows and remain usable on desktop and mobile", async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const create = await tripFactory(page)
  const prefix = `Tabla ${testInfo.project.name} ${Date.now()}`
  for (let index = 0; index < 21; index++) await create(`${prefix} ${String(index).padStart(2, "0")}`)
  await create(`${prefix} borrador`, "draft")
  await create(`${prefix} despublicado`, "unpublished")
  await create(`${prefix} archivado`, "archived")
  await page.goto(`${base}/asesor/viajes?q=${encodeURIComponent(prefix)}`)
  await expect(page.getByRole("tab")).toHaveCount(3)
  await expect(page.getByRole("tab", { name: "Publicados 21" })).toHaveAttribute("aria-selected", "true")
  await expect(page.getByRole("tab", { name: "Borradores 2" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Archivados 1" })).toBeVisible()
  await expect(page.locator("tbody tr")).toHaveCount(20)
  await expect(page.locator("tbody tr").first()).toContainText(`${prefix} 20`)
  await expect(page.locator("tbody tr").first()).toContainText("Por grupo")
  await expect(page.locator("tbody tr").first()).toContainText("0 noches")
  await expect(page.locator(".agent-trip-page-summary")).toHaveText("Mostrando 1–20 de 21 viajes")
  await page.locator(".agent-trip-extra-filters > summary").click()
  await page.getByLabel("Moneda", { exact: true }).selectOption("USD")
  await page.getByRole("textbox", { name: "Salida desde", exact: true }).fill("01/11/2030")
  await page.getByRole("textbox", { name: "Salida hasta", exact: true }).fill("30/11/2030")
  await page.getByRole("button", { name: "Aplicar filtros", exact: true }).click()
  await expect(page).toHaveURL(/currency=USD/)
  await page.getByRole("link", { name: "Página siguiente", exact: true }).click()
  await expect(page).toHaveURL(/page=2/)
  await expect(page.locator("tbody tr")).toHaveCount(1)
  const params = new URL(page.url()).searchParams
  expect(params.get("q")).toBe(prefix)
  expect(params.get("currency")).toBe("USD")
  expect(params.get("from")).toBe("2030-11-01")
  expect(params.get("page")).toBe("2")
  await page.getByRole("tab", { name: "Borradores 2" }).click()
  await expect(page.getByRole("tab", { name: "Borradores 2" })).toHaveAttribute("aria-selected", "true")
  expect(new URL(page.url()).searchParams.has("page")).toBe(false)
  await expect(page.locator("tbody .agent-trip-state")).toHaveText(["Borrador", "Borrador"])
  await page.locator(".agent-trip-result-bar").getByRole("link", { name: "Limpiar filtros" }).click()
  await expect(page).toHaveURL(url => url.searchParams.get("tab") === "drafts" && !url.searchParams.has("q"))
  expect(new URL(page.url()).searchParams.get("tab")).toBe("drafts")
  expect(new URL(page.url()).searchParams.has("q")).toBe(false)
  await page.goto(`${base}/asesor/viajes?q=${encodeURIComponent(prefix)}`)
  const toggle = page.locator("tbody tr").last().getByRole("button", { name: /^Acciones de/ })
  await toggle.click()
  const menu = page.getByRole("menu").filter({ visible: true })
  await expect(menu).toBeVisible()
  const box = await menu.boundingBox()
  expect(box.y).toBeGreaterThanOrEqual(0)
  expect(box.y + box.height).toBeLessThanOrEqual(await page.evaluate(() => innerHeight))
  expect(await menu.evaluate(element => {
    const last = element.querySelector('[role="menuitem"]:last-child') || element.querySelector('[role="menuitem"]')
    const box = last.getBoundingClientRect()
    return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
  })).toBe(true)
  await page.screenshot({ path: testInfo.outputPath("mis-viajes-menu.png"), fullPage: true })
  await page.keyboard.press("Escape")
  await expect(toggle).toBeFocused()
  await expect(toggle).toHaveAttribute("aria-expanded", "false")
  await toggle.press("ArrowDown")
  await expect(page.getByRole("menuitem", { name: "Ver detalle", exact: true }).filter({ visible: true })).toBeFocused()
  await page.keyboard.press("End")
  await expect(page.getByRole("menuitem", { name: "Archivar viaje", exact: true }).filter({ visible: true })).toBeFocused()
  await page.getByRole("heading", { name: "Mis viajes", exact: true }).click()
  await expect(menu).not.toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath("mis-viajes-listado.png"), fullPage: true })
})

test("context actions copy real links validate publication and move records between tabs", async ({ page }, testInfo) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async text => { window.copiedTripUrl = text } } })
  })
  const create = await tripFactory(page)
  const prefix = `Acciones ${testInfo.project.name} ${Date.now()}`
  await create(`${prefix} publicado`)
  await create(`${prefix} incompleto`, "draft", true)
  await page.goto(`${base}/asesor/viajes?q=${encodeURIComponent(prefix)}`)
  const row = page.locator("tbody tr").filter({ hasText: `${prefix} publicado` })
  await row.getByRole("button", { name: /^Acciones de/ }).click()
  const publicUrl = await page.getByRole("menuitem", { name: "Ver ficha pública", exact: true }).filter({ visible: true }).getAttribute("href")
  await page.getByRole("menuitem", { name: "Copiar enlace", exact: true }).filter({ visible: true }).click()
  await expect.poll(() => page.evaluate(() => window.copiedTripUrl)).toBe(publicUrl)
  expect((await page.request.get(publicUrl)).status()).toBe(200)
  await page.evaluate(() => Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined }))
  await row.getByRole("button", { name: /^Acciones de/ }).click()
  await page.getByRole("menuitem", { name: "Copiar enlace", exact: true }).filter({ visible: true }).click()
  await expect(page.getByLabel("Texto para copiar manualmente")).toHaveValue(publicUrl)
  await expect(page.getByLabel("Texto para copiar manualmente")).toBeFocused()
  await row.getByRole("button", { name: /^Acciones de/ }).click()
  page.once("dialog", dialog => dialog.dismiss())
  await page.getByRole("menuitem", { name: "Despublicar", exact: true }).filter({ visible: true }).click()
  await expect(row).toBeVisible()
  await row.getByRole("button", { name: /^Acciones de/ }).click()
  page.once("dialog", dialog => dialog.accept())
  await page.getByRole("menuitem", { name: "Despublicar", exact: true }).filter({ visible: true }).click()
  await expect(page.getByRole("tab", { name: "Publicados 0" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "Mis viajes", exact: true })).toBeFocused()
  await page.getByRole("tab", { name: "Borradores 2" }).click()
  const incomplete = page.locator("tbody tr").filter({ hasText: `${prefix} incompleto` })
  await incomplete.getByRole("button", { name: /^Acciones de/ }).click()
  await page.getByRole("menuitem", { name: "Publicar viaje", exact: true }).filter({ visible: true }).click()
  await expect(page.getByRole("status").filter({ hasText: "es obligatorio para publicar" })).toBeVisible()
  await expect(page.getByRole("heading", { name: "Mis viajes", exact: true })).toBeFocused()
  await expect(incomplete).toBeVisible()
  const unpublished = page.locator("tbody tr").filter({ hasText: `${prefix} publicado` })
  await unpublished.getByRole("button", { name: /^Acciones de/ }).click()
  page.once("dialog", dialog => dialog.accept())
  await page.getByRole("menuitem", { name: "Archivar viaje", exact: true }).filter({ visible: true }).click()
  await page.getByRole("tab", { name: "Archivados 1" }).click()
  await expect(page.getByRole("tab", { name: "Archivados 1" })).toHaveAttribute("aria-selected", "true")
  await expect(page.locator("tbody tr")).toContainText(`${prefix} publicado`)
  await page.locator("tbody tr").getByRole("button", { name: /^Acciones de/ }).click()
  await expect(page.getByRole("menuitem", { name: "Editar viaje", exact: true }).filter({ visible: true })).toBeVisible()
  await page.getByRole("menuitem", { name: "Publicar viaje", exact: true }).filter({ visible: true }).click()
  await expect(page.getByRole("tab", { name: "Publicados 1" })).toBeVisible()
  await expect(page.getByRole("tab", { name: "Archivados 0" })).toHaveAttribute("aria-selected", "true")
})
