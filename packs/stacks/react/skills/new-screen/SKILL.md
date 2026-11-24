---
name: new-screen
description: Step-by-step for building one front-end screen or feature in React from the specification - types, data hooks, states, role guard, forms and verification. Use when starting any screen.
---

# New screen (React)

0. **Branch:** create `feat/<screen>` from the up-to-date base branch. Never work on the protected branch.
1. **Scope:** read the living plan (order, pending items, gaps), the screen's section in the specification
   and the front-end instructions. Take an existing finished module as the model. Decide who may access it
   (role), what it reads, and what it writes (a read-only audience writes nothing unless the specification names
   one action).
2. **Contract:** find the endpoints in the server code and the DTOs in the application layer. If an endpoint is
   missing, or a response leaks an internal field to a restricted audience, **stop** and hand the gap to the
   backend agent. Do not invent a contract.
3. **Module** in `src/modules/<module>/` (a module never imports another module):
   - **Types:** `src/interfaces/<domain>.ts` mirrors the DTO (enum casing as the API returns it).
   - **Components:** one per file, with its own props interface, in the order the component rule defines.
   - **`api.ts`:** functions over the shared API client; no stray `fetch`.
   - **`hooks.ts`:** `useQuery` / `useMutation` with stable keys (`['parent', parentId, 'items', page]`); a
     mutation invalidates the keys it affects.
   - **`pages/`:** thin pages, logic in hooks.
   - **Appearance:** the design rule plus the reference capture for the screen (open it with Read before
     composing). Add the navigation entry in the order of the specification.
   - **UI:** shared components first; add a missing primitive from the UI library's CLI rather than rewriting it
     by hand. If the registry is unreachable, stop and record the pending item. Colors only through theme tokens,
     never a hard-coded color.
4. **States:** loading (a skeleton inside `role="status"` with `sr-only` text), empty (a useful message), error
   (request id on a 500; 403 means no permission; 409 shows the transition message) and success.
5. **Route:** register it behind the role guard inside the right layout, plus the navigation entry.
6. **Forms** (write screens): a form library plus a schema validator that mirrors the server's validator; map
   server 400 errors onto the fields.
7. **Restricted audience view:** plain language, no technical terms, only planned or contracted values.
8. **Tests** belong to the tester agent (separate context). Failures come back to you to fix the code, never the
   test. Minimum: the four states plus a role test. Outside a cycle with no subagent available, write the tests and
   say so in the delivery. If the screen calls new endpoints, adjust old tests that render that route (the mock
   server fails on a call without a handler).
9. **Verify:** formatter first, then lint, typecheck and tests.
10. **Plan:** update the living plan (status, gaps, decisions) and generate the log line. If the hook blocks the
    commit, resolve it yourself.
11. Run the pre-commit check and, for screens with a write action or an access restriction, the security reviewer
    (the orchestrator does this inside a cycle).
