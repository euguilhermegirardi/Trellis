import { defineConfig, devices } from '@playwright/test';

// End-to-end tests for critical flows. Files are named *.e2e.ts so the unit test runner does not collect them.
//
// Environment variables (all optional):
//   PW_BASE_URL         app URL                                   (default http://localhost:5173)
//   PW_WEB_SERVER       command that starts the app               (default "npm run dev")
//   PW_BROWSER=webkit   run WebKit instead of Chromium
//   PW_CHANNEL=chrome   use an installed browser ("chrome" or "msedge") when Playwright cannot download its own
//   PW_CHROMIUM_PATH    path to a specific Chromium executable (for example a cloud image with another revision)
const baseURL = process.env.PW_BASE_URL ?? 'http://localhost:5173';
const browser = process.env.PW_BROWSER ?? 'chromium';
const executablePath = process.env.PW_CHROMIUM_PATH || undefined;
const channel = process.env.PW_CHANNEL || undefined;

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.e2e.ts',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL },
  projects: [
    browser === 'chromium'
      ? { name: 'chromium', use: { ...devices['Desktop Chrome'], channel, launchOptions: { executablePath } } }
      : { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
  webServer: {
    command: process.env.PW_WEB_SERVER ?? 'npm run dev',
    url: baseURL,
    reuseExistingServer: true,
  },
});
