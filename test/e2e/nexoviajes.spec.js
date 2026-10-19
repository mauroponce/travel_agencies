const { test, expect } = require("@playwright/test")

test("landing and public trip expose the real responsive experience", async ({ page }) => {
  await page.goto("/")
  await expect(page.getByRole("heading", { name: /Un solo lugar/ })).toBeVisible()
  await expect(page.getByRole("button", { name: /Ingresar con Google/ }).first()).toBeVisible()

  await page.goto("/viajes/sanzo-viajes/mendoza-super-sale")
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
    await page.getByRole("link", { name: /Hoja de ruta/ }).first().click()
    await expect(page.getByRole("heading", { name: /MZA-/ })).toBeVisible()
  }
})
