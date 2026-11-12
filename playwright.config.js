const { defineConfig, devices } = require("@playwright/test")

const port = process.env.E2E_PORT || "3100"
// Each run gets a fresh disposable test database; never reset an existing DB.
const databaseName = process.env.E2E_DB_NAME || `turistack_e2e_${Date.now()}_test`
const testEnv = { ...process.env, RAILS_ENV: "test", AGENT_ENABLED: "true", AGENT_E2E_FIXTURES: "true", GEMINI_API_KEY: "test-key", PLATFORM_HOST: "localhost", AUTH_HOST: "auth.localhost", APP_PROTOCOL: "http", PLATFORM_BASE_DOMAIN: "lvh.me", APP_PORT: port }
if (testEnv.DATABASE_URL) {
  const databaseUrl = new URL(testEnv.DATABASE_URL)
  databaseUrl.pathname = `/${databaseName}`
  testEnv.DATABASE_URL = databaseUrl.toString()
  for (const key of ["DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME"]) delete testEnv[key]
} else {
  testEnv.DB_NAME = databaseName
}

module.exports = defineConfig({
  testDir: "test/e2e",
  fullyParallel: false,
  reporter: "list",
  use: { baseURL: `http://sanzo-viajes.lvh.me:${port}`, trace: "retain-on-failure" },
  webServer: {
    command: `bin/rails db:prepare db:seed && bin/rails server -p ${port}`,
    env: testEnv,
    url: `http://127.0.0.1:${port}/up`,
    reuseExistingServer: false,
    timeout: Number(process.env.E2E_BOOT_TIMEOUT_MS || 120000)
  },
  projects: [
    { name: "desktop-chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-chromium", use: { ...devices["Pixel 7"], browserName: "chromium" } }
  ]
})
