const { test, expect } = require("@playwright/test")

test("landing and public trip expose the real responsive experience", async ({ page }) => {
  await page.goto("/")
  await expect(page.getByRole("heading", { name: /Un solo lugar/ })).toBeVisible()
  await expect(page.getByRole("button", { name: /Ingresar con Google/ }).first()).toBeVisible()

  await page.goto("/viajes/mendoza-super-sale")
  await expect(page.getByRole("heading", { name: /Mendoza/ })).toBeVisible()
  await expect(page.getByText(/cupos disponibles/)).toBeVisible()
  await expect(page.getByRole("link", { name: /WhatsApp/ })).toHaveAttribute("href", /^https:\/\/wa\.me\//)
  const horizontalScroll = await page.evaluate(() => {
    window.scrollTo(100, 0)
    return window.scrollX
  })
  expect(horizontalScroll).toBe(0)
})

test("admin dashboard is responsive and uses real navigation", async ({ page }, testInfo) => {
  if (testInfo.project.name.startsWith("mobile")) await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/test/sign-in?email=demo%40nexoviajes.local&company=sanzo-viajes&role=admin")
  await expect(page.getByRole("heading", { name: /Resumen general/ })).toBeVisible()
  await expect(page.getByText("Sanzó Viajes").first()).toBeVisible()
  await expect(page.getByRole("link", { name: /Nueva oferta/ })).toHaveAttribute("href", "/ofertas/new")
  await expect(page.getByText("Ocupación de próximas salidas")).toBeVisible()
  await page.getByRole("combobox", { name: "Filtrar salidas" }).selectOption("month")
  await expect(page).toHaveURL(/departure_filter=month/)
  await expect(page.getByText(/Mostrando 2 de 2 salidas/)).toBeVisible()
  const horizontalScroll = await page.evaluate(() => {
    window.scrollTo(100, 0)
    return window.scrollX
  })
  expect(horizontalScroll).toBe(0)

  if (testInfo.project.name.startsWith("mobile")) {
    await page.getByRole("button", { name: "Abrir menú" }).click()
    const mobileReservations = page.getByRole("complementary", { name: "Menú principal" }).getByRole("link", { name: "Reservas" })
    await expect(mobileReservations).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(page.locator("#main-sidebar")).toHaveAttribute("aria-hidden", "true")
    await expect(page.getByRole("button", { name: "Abrir menú" })).toHaveAttribute("aria-expanded", "false")
  }
})

test("coordinator keeps the authorized mobile operation flow", async ({ page }) => {
  await page.goto("/test/sign-in?email=demo%40nexoviajes.local&company=sanzo-viajes&role=coordinator")
  await expect(page).toHaveURL(/salidas/)
  await page.locator("a[href$='/operation']").first().click()
  await expect(page.getByRole("heading", { name: /MZA-/ })).toBeVisible()
})

test.describe("boarding offline", () => {
test.use({ serviceWorkers: "block" })

test("boarding queues a command offline without passenger data and syncs on reconnect", async ({ page }) => {
  await page.addInitScript(() => {
    window.__testOnline = true
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => window.__testOnline })
  })
  let syncRequests = 0
  await page.route("**/boarding_events/sync*", async route => {
    syncRequests += 1
    const { commands } = JSON.parse(route.request().postData())
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
      results: commands.map(command => ({ command_id: command.command_id, result: "applied", status: command.desired_status }))
    }) })
  })
  await page.goto("/test/sign-in?email=demo%40nexoviajes.local&company=sanzo-viajes&role=coordinator")
  await page.locator("a[href$='/operation']").first().click()
  await expect(page.getByRole("heading", { name: /MZA-/ })).toBeVisible()

  await page.evaluate(() => { window.__testOnline = false })
  const boardingButton = page.getByRole("button", { name: "Embarcado" }).first()
  await boardingButton.click()
  await expect(boardingButton.locator("xpath=ancestor::*[@data-passenger-id]").getByText("Pendiente de sincronizar")).toBeVisible()

  const stored = await page.evaluate(() => Object.entries(localStorage)
    .filter(([key]) => key.startsWith("nexoviajes.boarding.queue.")))
  expect(stored).toHaveLength(1)
  expect(stored[0][1]).toContain("command_id")
  expect(stored[0][1]).not.toMatch(/full_name|document|dni|nombre/i)

  await page.evaluate(() => { window.__testOnline = true })
  await Promise.all([
    page.waitForNavigation(),
    page.evaluate(() => {
      const element = document.querySelector("[data-controller='boarding']")
      window.Stimulus.getControllerForElementAndIdentifier(element, "boarding").flush()
    })
  ])
  await expect.poll(() => syncRequests).toBeGreaterThan(0)
  await expect.poll(async () => page.evaluate(() => Object.entries(localStorage)
    .filter(([key]) => key.startsWith("nexoviajes.boarding.queue."))
    .every(([, value]) => JSON.parse(value).length === 0)), { timeout: 15_000 }).toBeTruthy()
})
})
