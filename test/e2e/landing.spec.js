const { test, expect } = require("@playwright/test")

test.beforeEach(async ({ page, baseURL }) => {
  const platform = new URL(baseURL)
  platform.hostname = "platform.lvh.me"
  await page.goto(platform.href)
})

test("landing connects Google sign-in and demonstrates all three roles", async ({ page }) => {
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Cada viaje, cada venta,en un solo lugar.")
  const signIn = page.getByRole("button", { name: "Ingresar con Google", exact: true }).first()
  await expect(signIn).toBeVisible()
  await expect(signIn.locator("..")).toHaveAttribute("action", "/auth/start")
  await expect(signIn.locator("..")).toHaveAttribute("method", "post")

  const roles = page.getByRole("combobox", { name: "Cambiar perfil de demostración" })
  await roles.selectOption("reseller")
  await expect(page.locator("#appCrumbTitle")).toHaveText("Mis ventas")
  await expect(page.locator("#appRows")).toContainText("TS-1048")
  await roles.selectOption("coordinator")
  await expect(page.locator("#appCrumbTitle")).toHaveText("Mis salidas")
  await expect(page.locator("#appRows")).toContainText("Terminal Varela")
  await roles.selectOption("admin")
  await expect(page.locator("#appCrumbTitle")).toHaveText("Vista general")
  await expect(page.locator("#appRows")).toContainText("38 / 45")

  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
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
    await page.getByRole("navigation", { name: "Navegación móvil" }).getByRole("link", { name: "Para tu equipo" }).click()
    await expect(page).toHaveURL(/#proof$/)
    await expect(menu).toHaveAttribute("aria-expanded", "false")
  } else {
    const thirdStep = page.getByRole("button", { name: "Paso tres: coordiná el viaje", exact: true })
    await thirdStep.focus()
    await thirdStep.press("Enter")
    await expect(thirdStep).toHaveAttribute("aria-pressed", "true")
    await expect(page.locator('[data-vis="2"]')).toHaveAttribute("aria-hidden", "false")
  }
})
