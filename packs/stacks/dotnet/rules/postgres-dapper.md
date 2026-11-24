---
paths:
  - "database/**"
  - "backend/**/Infrastructure/**"
---

# PostgreSQL with Dapper

- **Schema changes are new numbered scripts** in `database/schema/` (`007_*.sql`, `008_*.sql`, ...). Never
  edit a script that was already applied anywhere.
- Apply locally with `psql -d <database> -f database/schema/<NNN>_*.sql`.
- **Enums need an explicit cast** in Dapper parameters: `@Status::order_status`, `@Role::user_role`; JSON
  columns need `::jsonb`.
- SQL is plain text with **named parameters**. Never build SQL by string interpolation or concatenation.
- **Filter by owner in SQL as well**, even when the service already checked access (defense in depth):
  `WHERE id = @Id AND owner_id = @OwnerId`.
- Seed data lives outside the repository (git-ignored folder). Nothing with a password hash or real data
  is committed.
- `DATE` maps to `DateOnly` and `timestamptz` to `DateTimeOffset`; avoid `DateTime` with unspecified kind.
- Keep migrations reversible in intent: add columns nullable or with a default first, backfill, then
  tighten the constraint in a later script.
