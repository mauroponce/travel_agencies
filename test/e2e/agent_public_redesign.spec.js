const { test, expect } = require('@playwright/test')
const base = `http://localhost:${process.env.E2E_PORT || '3100'}`

test('public catalog follows the mockup with live filters favorites pagination and a separate profile', async ({ page, browser }, testInfo) => {
  test.setTimeout(120000)
  const identity = await (await page.request.get(`${base.replace('localhost', 'auth.localhost')}/test/pro-lifecycle/prepare`)).json()
  const slug = `publico-${Date.now()}-${testInfo.project.name}`
  await page.goto(`${base}/test/sign-in?email=${encodeURIComponent(identity.email)}&purpose=agent_onboarding`)
  await page.getByLabel('Nombre', { exact: true }).fill('Viajes de Lucía')
  await page.getByLabel('Link público', { exact: true }).fill(slug)
  await page.getByLabel('WhatsApp con código de país').fill('5491155554321')
  await page.getByRole('button', { name: 'Crear mi espacio' }).click()
  await expect(page).toHaveURL(`${base}/asesor`)
  await page.goto(`${base}/asesor/mi-web`)
  await page.getByRole('checkbox', { name: /Sobre mí/ }).check()
  await page.getByLabel('Texto sobre mí').fill('Soy Lucía. Te ayudo a elegir tu próxima escapada y respondo tus consultas personalmente.')
  await page.getByRole('button', { name: 'Guardar cambios', exact: true }).click()
  await expect(page.getByText('Tu página fue actualizada.', { exact: true })).toBeVisible()
  await page.goto(`${base}/asesor/empresas/nuevo`)
  await page.getByLabel('Nombre del proveedor').fill('Empresa del catálogo público')
  await page.getByRole('button', { name: 'Guardar proveedor' }).click()
  await expect(page.getByRole('heading', { name: 'Empresa del catálogo público', exact: true })).toBeVisible()
  await page.goto(`${base}/asesor/viajes/nuevo`)
  const supplier = await page.getByLabel('Proveedor', { exact: true }).locator('option:not([value=""])').first().getAttribute('value')
  const token = await page.locator('meta[name="csrf-token"]').getAttribute('content')
  const destinations = ['Córdoba', 'Mendoza', 'Bariloche', 'Salta', 'Ushuaia', 'Mar del Plata', 'Iguazú', 'Villa Carlos Paz']
  for (let index = 0; index < destinations.length; index++) {
    const response = await page.request.post(`${base}/asesor/viajes`, {
      headers: { 'X-CSRF-Token': token }, maxRedirects: 0,
      form: {
        'agent_trip_revision[agent_supplier_id]': supplier,
        'agent_trip_revision[title]': `Viaje a ${destinations[index]}`,
        'agent_trip_revision[destination]': destinations[index],
        'agent_trip_revision[region]': 'Argentina',
        'agent_trip_revision[departs_on]': `2030-11-${20 + index}`,
        'agent_trip_revision[duration_days]': String([4, 6, 8][index % 3]),
        'agent_trip_revision[transport]': index % 2 ? 'Avión' : 'Bus',
        'agent_trip_revision[price]': String(800000 - index * 50000),
        'agent_trip_revision[currency]': 'ARS',
        'agent_trip_revision[price_unit]': 'per_person', commit_action: 'publish'
      }
    })
    expect(response.status()).toBe(302)
  }
  const context = await browser.newContext({ viewport: page.viewportSize() })
  const visitor = await context.newPage()
  try {
    await visitor.goto(`${base}/${slug}`)
    await expect(visitor.getByRole('heading', { name: '¿A dónde querés viajar?', exact: true })).toBeVisible()
    await expect(visitor.locator('.catalog-heading .count')).toHaveText('8 viajes')
    await expect(visitor.locator('.trip')).toHaveCount(6)
    await expect(visitor.locator('.trip-meta').first()).toContainText('20 nov 2030')
    expect(await visitor.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await visitor.getByRole('button', { name: 'Más filtros', exact: true }).click()
    await visitor.getByLabel('Mes de salida').selectOption('2030-11')
    await visitor.getByLabel('Transporte', { exact: true }).selectOption('Bus')
    await visitor.getByLabel('Duración', { exact: true }).selectOption('4')
    await expect(visitor.locator('.trip')).toHaveCount(2)
    await expect(visitor.locator('.active-chips .chip')).toHaveCount(3)
    await visitor.getByRole('button', { name: 'Limpiar filtros', exact: true }).click()
    await expect(visitor.locator('.trip')).toHaveCount(6)
    const search = visitor.getByRole('combobox', { name: 'Destino', exact: true })
    await search.fill('cordoba')
    await expect(visitor.getByRole('option', { name: 'Córdoba', exact: true })).toBeVisible()
    await expect(visitor.locator('.trip')).toHaveCount(1)
    await expect(search).toBeFocused()
    await expect(visitor.getByRole('option', { name: 'Córdoba', exact: true })).toBeVisible()
    await visitor.getByRole('option', { name: 'Córdoba', exact: true }).click()
    await expect(visitor).toHaveURL(url => url.searchParams.get('destination') === 'Córdoba')
    const heart = visitor.getByRole('button', { name: 'Agregar a favoritos: Viaje a Córdoba', exact: true })
    await heart.click()
    await expect(visitor.getByRole('button', { name: 'Quitar de favoritos: Viaje a Córdoba', exact: true })).toHaveAttribute('aria-pressed', 'true')
    await visitor.reload()
    await expect(visitor.getByRole('button', { name: 'Quitar de favoritos: Viaje a Córdoba', exact: true })).toHaveAttribute('aria-pressed', 'true')
    const contact = new URL(await visitor.locator('.trip-cta').getAttribute('href'))
    expect(contact.pathname).toBe('/5491155554321')
    expect(contact.searchParams.get('text')).toContain(`/${slug}/viajes/`)
    await visitor.getByRole('button', { name: 'Limpiar búsqueda', exact: true }).click()
    await expect(visitor.locator('.trip')).toHaveCount(6)
    await visitor.getByLabel('Ordenar por', { exact: true }).selectOption('price_asc')
    await expect(visitor.locator('.trip').first()).toContainText('Viaje a Villa Carlos Paz')
    await visitor.screenshot({ path: testInfo.outputPath('catalogo-publico.png'), fullPage: true })
    await visitor.getByRole('link', { name: 'Página siguiente', exact: true }).click()
    await expect(visitor.locator('.trip')).toHaveCount(2)
    await expect(visitor.getByRole('button', { name: 'Quitar de favoritos: Viaje a Córdoba', exact: true })).toHaveAttribute('aria-pressed', 'true')
    await visitor.locator('.header-nav').getByRole('link', { name: 'Sobre mí', exact: true }).click()
    await expect(visitor.locator('#sobre-mi')).toBeVisible()
    await expect(visitor.locator('#viajes')).toBeHidden()
    await expect(visitor.locator('.agent-about-text')).toContainText('Soy Lucía.')
    await expect(visitor.locator('.profile-actions .dark-button')).toHaveAttribute('href', 'https://wa.me/5491155554321')
    await visitor.screenshot({ path: testInfo.outputPath('perfil-publico.png'), fullPage: true })
    expect(await visitor.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await visitor.getByRole('link', { name: 'Explorar viajes', exact: true }).click()
    await expect(visitor.locator('#viajes')).toBeVisible()
    await expect(visitor.locator('.trip')).toHaveCount(2)
  } finally { await context.close() }
})
