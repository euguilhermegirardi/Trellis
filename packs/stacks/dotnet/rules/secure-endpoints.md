---
paths:
  - "backend/**/*.cs"
---

# Secure endpoints

Defaults for any service that holds sensitive data. Pair with the project's own access matrix.

## Order of checks for a resource owned by a parent (project, tenant, account)

1. Resolve the parent id from the route and return **404** if it does not exist.
2. Authorize the caller against that parent through one shared service
   (`EnsureAccessAsync(parentId, user)`). Translate its denial to **403** (`Results.Forbid()`).
3. Query with the parent and owner filters in SQL.
4. Validate the request body (**400**).
5. Check state and uniqueness (**409**).
6. Touch external systems (object storage, email) **last**, so a rejected request leaves nothing behind.

## Roles and DTOs

- Authorize by policy per endpoint group (for example `AdminOrMaster`, `MasterOnly`), never by an ad-hoc
  role comparison inside the handler.
- A read-only audience gets **its own reduced DTO**. Fields they must never see (cost, margin, internal
  notes) do not exist on that type, so they cannot leak by mapping mistake.
- Writes by a restricted audience are limited to the specific actions the specification names.

## Uploads and downloads

- Every upload goes through one validator: size limit, extension, declared MIME type **and** magic bytes.
- Downloads go through the authenticated API, never a public bucket URL.
- Object keys are built by the server from ids and a random name; the client's file name is stored as
  metadata only.

## Configuration and secrets

- Secrets come from environment variables or an untracked development settings file. The committed
  settings file holds logging and non-secret defaults only.
- CORS allows the exact front-end origin from configuration. Never `AllowAnyOrigin`.

## Tests

A change to an access rule comes with a test that runs the real HTTP pipeline (for example
`WebApplicationFactory`) and asserts 401, 403 and 404 for the wrong caller, not only the happy path.
