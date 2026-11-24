# React presets

Configuration files for a React + TypeScript + Vite front end. Copy what you need and adjust the globs.

| Preset | Copy to | Purpose |
|---|---|---|
| `oxlintrc.json` | `<frontend>/.oxlintrc.json` | Lint rules with the reason beside each, plus import-direction boundaries between layers |
| `prettierrc.json` | `.prettierrc.json` | Formatting (120 columns, single quotes, trailing commas) |
| `prettierignore` | `.prettierignore` | Keeps generated output and lock files out of formatting |
| `playwright.config.ts` | `<frontend>/playwright.config.ts` | End-to-end setup driven by environment variables |

The lint preset assumes `src/modules`, `src/layouts`, `src/routes` and a shared base (`components`, `utils`,
`services`, `interfaces`, `hooks`) and the `@/` import alias. If your layout differs, rename the globs in the
`overrides`; the rules themselves stay.
