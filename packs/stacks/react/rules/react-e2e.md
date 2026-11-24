---
paths:
  - "**/e2e/**"
  - "**/*.e2e.ts"
  - "**/playwright.config.ts"
---

# End-to-end tests (Playwright)

- Cover critical flows only: sign in, the main write action for each role, and access denied to a resource the
  user is not linked to. Everything else belongs to unit and integration tests.
- Files are named `*.e2e.ts` so the unit test runner does not collect them.
- Run from the project root through the package script (for example `npm --prefix frontend run e2e`).
  In a cloud image with a pre-installed Chromium, prefix the command with
  `PW_CHROMIUM_PATH=<path to the chromium executable>`.
- Playwright not installed yet? Install it when the first critical flow needs it: `@playwright/test` as a dev
  dependency, a config next to the front end, and the Chromium browser.
- No browser, API or database in the environment: report the end-to-end result as `not run` with the reason.
  **Never fake a result.**
- **Capture mocks:** for every screen, create `e2e/mocks/<screen>.json` with a realistic, synthetic success
  scenario that covers **every** call the screen makes. The design reviewer uses it to capture the screen
  without a backend.
