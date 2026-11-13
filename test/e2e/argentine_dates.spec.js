const { test, expect } = require("@playwright/test")

test("operational date and time fields display Argentine dates and submit ISO values", async ({ page }) => {
  await page.goto("/test/sign-in?email=demo%40turistack.local&company=sanzo-viajes&role=admin")
  await page.goto("/salidas/nuevo")
  const departure = page.getByLabel("Salida", { exact: true })
  await expect(departure).toHaveAttribute("placeholder", "DD/MM/AAAA HH:mm")
  await departure.fill("03/02/2030 14:30")
  await expect(page.locator('input[name="departure[departs_at]"]')).toHaveValue("2030-02-03T14:30")
  expect(await departure.evaluate(input => input.checkValidity())).toBe(true)
  await departure.fill("03/02/2030 25:30")
  expect(await departure.evaluate(input => input.checkValidity())).toBe(false)
  await page.locator("#departure_departs_at_picker").evaluate(input => {
    input.value = "2030-02-03T14:30"
    input.dispatchEvent(new Event("change", { bubbles: true }))
  })
  await expect(departure).toHaveValue("03/02/2030 14:30")
  const form = departure.locator("xpath=ancestor::form")
  const submitted = await form.evaluate(form => Array.from(new FormData(form).entries()).filter(([key]) => key === "departure[departs_at]"))
  expect(submitted).toEqual([["departure[departs_at]", "2030-02-03T14:30"]])
})
