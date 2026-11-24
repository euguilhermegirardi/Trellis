---
name: new-endpoint
description: Checklist for creating or completing a .NET endpoint or module (Minimal API, Clean Architecture, Dapper) with validation, parent-scoped access and tests. Use when implementing a backend gap.
---

# New endpoint (.NET)

1. **Read:** the specification of the feature and a finished neighboring endpoint as the model.
2. **Schema** (only if needed): a new numbered script. Never edit applied scripts. Use existing database enums;
   otherwise a `CHECK` constraint or a lookup table.
3. **Domain:** the entity or enum.
4. **Application:**
   - `sealed record` DTOs, request and response apart; a distinct DTO for a restricted audience when the model has
     internal fields.
   - Validator with cross-field rules (for example end >= start).
   - Interface in `Abstractions`; a service that takes a `CancellationToken` and logs with message templates.
5. **Infrastructure:** a Dapper repository with plain SQL and named parameters; explicit enum casts;
   `IDbConnection` plus `IDbTransaction` for multi-table writes. **Every visibility filter lives in SQL**: owner,
   parent **and status** (for example a restricted audience sees only `published`:
   `AND status = 'published'::status_enum`). Do not fetch everything and filter in the service; add a dedicated
   repository method.
6. **Api:**
   - Parent-scoped → the shared authorization call; its denial returns `Results.Forbid()`. This applies to
     **every** endpoint that takes an id of something owned by a parent, **including admin-only ones**: look the
     record up, take its parent id, then authorize.
   - Internal modules behind the right policy; user management and audit behind the strictest one.
   - Status codes as in the HTTP contract rule; lists use the paging envelope with a zero-based `pageIndex`.
7. **DI:** register the interface and its implementation.
8. **Tests** (security test project): validator (valid and invalid); access rule (a caller of another parent gets
   403); an illegal state transition gets 409; and what the restricted audience must **not** see (a draft returns
   404 or is absent from the list; an internal field is absent from the JSON). If the repository changed, update
   its fake.
9. **Verify:** build and run the tests. If the toolchain is missing, say so; do not claim success.
10. **Document:** remove the gap from the plan's list, mark the unblocked screen, and hand the front end the final
    contract (route, request, response, status codes).
11. Run the pre-commit check before committing.
