---
paths:
  - "backend/**/*.cs"
  - "backend/**/*.csproj"
---

# .NET backend conventions

Adjust the folder glob above to your solution layout. These are defaults for a Minimal API service.

## Architecture

- Minimal APIs with Clean Architecture layers: Domain, Application, Infrastructure, Api. Dependencies point
  inward; the Api layer wires endpoints and nothing else.
- Data access with Dapper and plain SQL behind the Repository pattern (no EF Core unless the project says
  otherwise).
- A write that touches several tables uses one `IDbConnection` and one `IDbTransaction`.
- DTOs are `sealed record`. Money is `decimal`, never `double`. Validation uses FluentValidation.
- Logs use message templates (`Log.Information("Created {Id}", id)`), never string interpolation.
  Pass a `CancellationToken` wherever the API allows.

## HTTP contract

Keep one contract for every endpoint so clients can rely on it:

| Situation | Status | Body |
|---|---|---|
| Paged list | 200 | `{ totalItems, pageIndex, pageSize, items }` (`pageIndex` is zero-based) |
| Created | 201 | the created resource (or its location) |
| Success without content | 204 | none |
| Success the client needs data from | 200 | the resource |
| Invalid input | 400 | validation problem details |
| Not authenticated | 401 | none |
| Authenticated but not allowed | 403 | none |
| Not found | 404 | none |
| Invalid state transition or duplicate | 409 | problem details |
| Unexpected error | 500 | `{ requestId, message }` (never a stack trace) |

State machines are written down next to the entity (for example `draft -> published`), and an invalid
transition returns 409.

## Pitfalls to remember

- **Configuration:** `IConfiguration` already reads environment variables (`Jwt__Secret`,
  `ConnectionStrings__Postgres`, ...). Do not call `Environment.GetEnvironmentVariable` by hand.
- **Claims in class libraries:** use `FindFirst(...)?.Value`; `FindFirstValue` needs the ASP.NET Core
  framework reference.
- **Dates:** `DateOnly` (C#) maps to `DATE` (database); `DateTime` carries time and kind. Convert on
  purpose and test the boundary.
- **S3-compatible object storage (not AWS itself):** the AWS SDK for .NET needs `ForcePathStyle = true`,
  `RequestChecksumCalculation` and `ResponseChecksumValidation` set to `WHEN_REQUIRED`, and
  `DisablePayloadSigning = true` on `PutObjectRequest`. Do not remove these without a test against the real
  provider.
