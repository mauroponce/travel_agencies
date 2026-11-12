const { test, expect } = require("@playwright/test")

test.beforeEach(async ({ page, baseURL }) => {
  const platform = new URL(baseURL)
  platform.hostname = "localhost"
  await page.goto(platform.href)
})

test("platform landing describes the real Pro scope and manual subscription", async ({ page }) => {
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Tu marca, tus viajes,tus clientes.")
  const signIn = page.getByRole("button", { name: "Ingresar con Google", exact: true }).first()
  await expect(signIn).toBeVisible()
  await expect(signIn.locator("..")).toHaveAttribute("action", "/auth/start")
  await expect(signIn.locator("..")).toHaveAttribute("method", "post")
  await expect(page.getByRole("heading", { name: "Turistack Pro · USD 19.00 por mes" })).toBeVisible()
  await expect(page.getByText(/sin débito automático/).first()).toBeVisible()
  await expect(page.getByRole("heading", { name: "Clientes y notas privados" })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})

test("landing navigation supports the keyboard on desktop and mobile", async ({ page }, testInfo) => {
  await page.emulateMedia({ reducedMotion: "reduce" })
  if (testInfo.project.name.startsWith("mobile")) {
    const menu = page.getByRole("button", { name: /^(Abrir|Cerrar) menú$/ })
    await menu.click()
    await expect(menu).toHaveAttribute("aria-expanded", "true")
    await page.keyboard.press("Escape")
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()
    await menu.click()
    await page.getByRole("navigation", { name: "Navegación móvil" }).getByRole("link", { name: "Mi plan" }).click()
    await expect(page).toHaveURL(/#plan$/)
    await expect(menu).toHaveAttribute("aria-expanded", "false")
  } else {
    await page.getByRole("navigation", { name: "Navegación principal" }).getByRole("link", { name: "Cómo funciona" }).click()
    await expect(page).toHaveURL(/#tour$/)
  }
})

test("Google registration starts independent agent onboarding from the landing", async ({ page }) => {
  const registration = page.locator(".hero").getByRole("button", { name: "Registrarme con Google", exact: true })
  await expect(registration).toBeVisible()
  await expect(registration.locator("..")).toHaveAttribute("action", "/auth/start?purpose=agent_onboarding")
  await registration.click()
  await expect(page).toHaveURL(/\/auth\/continue\?request_token=/)
  await expect(page.getByRole("heading", { name: "Continuar con Google" })).toBeVisible()
  await expect(page.getByRole("button", { name: "Ingresar con Google", exact: true }).locator("..")).toHaveAttribute("action", "/auth/google_oauth2")
})
