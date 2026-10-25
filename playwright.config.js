const { defineConfig, devices } = require("@playwright/test")

const port = process.env.E2E_PORT || "3100"
const agentEnv = "AGENT_ENABLED=true AGENT_E2E_FIXTURES=true GEMINI_API_KEY=test-key"

module.exports = defineConfig({
  testDir: "test/e2e",
  fullyParallel: false,
  reporter: "list",
  use: { baseURL: `http://sanzo-viajes.lvh.me:${port}`, trace: "retain-on-failure" },
  webServer: {
    command: `RAILS_ENV=test ${agentEnv} PLATFORM_BASE_DOMAIN=lvh.me APP_PORT=${port} bin/rails db:reset && RAILS_ENV=test ${agentEnv} PLATFORM_BASE_DOMAIN=lvh.me APP_PORT=${port} bin/rails server -p ${port}`,
    url: `http://127.0.0.1:${port}/up`,
    reuseExistingServer: false,
    timeout: 120000
  },
  projects: [
    { name: "desktop-chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-chromium", use: { ...devices["Pixel 7"], browserName: "chromium" } }
  ]
})
