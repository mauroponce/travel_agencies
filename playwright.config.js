const { defineConfig, devices } = require("@playwright/test")

module.exports = defineConfig({
  testDir: "test/e2e",
  fullyParallel: false,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:3100", trace: "retain-on-failure" },
  webServer: {
    command: "RAILS_ENV=test bin/rails db:prepare db:seed && RAILS_ENV=test bin/rails server -p 3100",
    url: "http://127.0.0.1:3100/up",
    reuseExistingServer: true,
    timeout: 120000
  },
  projects: [
    { name: "desktop-chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-chromium", use: { ...devices["Pixel 7"], browserName: "chromium" } }
  ]
})
