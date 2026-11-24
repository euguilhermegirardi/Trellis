---
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/test/**"
---

# React testing rules

Conventions for unit and integration tests written with Vitest, Testing Library and a network mocking
layer such as MSW. Adjust the helper names to your project; the principles are what matter.

## Setup

- Render pages through one shared helper (for example `renderApp(path, role?)`) that wires the router,
  the auth provider and a query client with `retry: false`. A `role` argument seeds a fake session;
  no role means signed out.
- Mock the network with MSW and register handlers per test with `server.use(...)`. Configure the server
  with `onUnhandledRequest: 'error'` so **every request a page makes needs a handler**, including tests
  that only assert on a heading.
- Mirror the real API shapes in handlers: pagination envelope, enum casing, date format and the error
  body (include the request id on 5xx responses). A handler that returns a convenient shape hides bugs.
- Use synthetic data only. Never put real credentials or personal data in fixtures.
- Clear `sessionStorage` and `localStorage` in a global `afterEach`.

## Queries and interactions

- Query by role, label or text (`getByRole`, `getByLabelText`) and drive the UI with `userEvent`.
  Never select by CSS class or assert on implementation details.
- Wait with `findBy*` or `waitFor`. Never use `setTimeout` or a `sleep` to "give it time".

## What every screen covers

- Loading, empty, error (with the request id on server errors) and success states.
- For screens with access restrictions, a role test in both directions: a restricted user sees no
  action or data reserved for others, and a privileged user cannot enter a route that is not theirs.

## Writing tests that do not depend on timing

A test that passes on a fast machine and fails on a slow one almost always assumes a mocked response
arrives before a synchronous check. Set a generous `asyncUtilTimeout` (around 5 s) and wait for in-flight
requests in a global `afterEach`; the rest is up to each test.

- **Never use a singular `getByRole('status' | 'alert')` where more than one can exist.** A loading
  skeleton is also a `status`, and an inline confirmation can be an `alert`. `findBy*` resolves on the first
  match, and a following assertion is not retried. Wait for the final state instead:
  `findByText('exact text')`, or
  `await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(text))`.
  To inspect one of several, use `getAllByRole`.
- After awaiting one element, anything that comes from **another request** (counters, summaries, a
  refetched list) needs its own `waitFor`. The same applies to
  `expect(calls).toHaveLength(n)` and `toHaveFocus()` right after an async action.
- `findAllByRole('listitem' | 'row')` also matches items in the sidebar or header. Wait for the named
  container (`findByRole('list', { name })`, `findByRole('table')`) and scope with `within`.
- To hold a response, use a gate (a `new Promise` plus a `release()` function) and release it before
  the test ends. Do not use timers.
- Large loops (hundreds of items): run `fireEvent` inside a single `act(() => { ... })` so React batches
  the renders. Use `userEvent` in a loop only for a handful of iterations. Do not raise the test timeout
  to hide the cost.

## Full lists and limit tests

Each unscoped `getByRole` or `getByLabelText` walks the whole DOM (visibility is computed per node
and accessible names for every button), so with hundreds of rows a single query can take about a second
on a CI box and far longer on a slow laptop.

- Scope queries with `within(row)`, find the row via `getByTitle(...).closest('tr')`, pass
  `hidden: true` when visibility is not the point, count with `querySelectorAll`, and prefer `fireEvent`
  (or `userEvent.setup({ pointerEventsCheck: 0, delay: null })`).
- Put limit tests in **their own file** (for example `*Limit.test.tsx`) and stub heavy dependencies there,
  such as icon libraries, without dropping assertions.
- Target under 10 s per test on a saturated CPU and a third of that on an idle one.
- If the slowness comes from the component itself (hundreds of rows re-rendering), that is a production
  finding: report it, do not hide it.

## Proving a test is robust

Run it with injected latency: temporarily wrap the MSW `http.*` helpers so every response awaits
`delay(150–300)` (do not commit this), or saturate the CPU with `nice`. A test that only passes
without latency is fragile.
