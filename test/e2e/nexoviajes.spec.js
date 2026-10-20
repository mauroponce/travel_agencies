const { test, expect } = require("@playwright/test")

test("landing and public trip expose the real responsive experience", async ({ page }) => {
  await page.goto("/")
  await expect(page.getByRole("heading", { name: /Un solo lugar/ })).toBeVisible()
  await expect(page.getByRole("button", { name: /Ingresar con Google/ }).first()).toBeVisible()

  await page.goto("/viajes/mendoza-super-sale")
  await expect(page.getByRole("heading", { name: /Mendoza/ })).toBeVisible()
  await expect(page.getByText(/cupos disponibles/)).toBeVisible()
  await expect(page.getByRole("link", { name: /WhatsApp/ })).toHaveAttribute("href", /^https:\/\/wa\.me\//)
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)
  expect(overflow).toBeFalsy()
})

test("authorized profiles render dashboard and mobile operation", async ({ page }, testInfo) => {
  const role = testInfo.project.name.startsWith("mobile") ? "coordinator" : "admin"
  await page.goto(`/test/sign-in?email=demo%40nexoviajes.local&company=sanzo-viajes&role=${role}`)
  if (role === "admin") {
    await expect(page.getByRole("heading", { name: /Buen día/ })).toBeVisible()
    await expect(page.getByText("Sanzó Viajes").first()).toBeVisible()
  } else {
    await expect(page).toHaveURL(/salidas/)
    await page.getByRole("link", { name: "Hoja de ruta", exact: true }).first().click()
    await expect(page.getByRole("heading", { name: /MZA-/ })).toBeVisible()
  }
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
  await page.getByRole("link", { name: "Hoja de ruta", exact: true }).first().click()
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
