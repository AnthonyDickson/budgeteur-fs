# Database

SQLite with DbUp migrations and SqlHydra type-safe queries.
The connection string is `Data Source=app.sqlite3` (relative, resolves to the
server project directory). Override with `ConnectionStrings__Default` in
production — use an absolute path like `/data/app.sqlite3`.

## Commands

```bash
just db-migration name=add_foo   # Scaffold a numbered .sql file
just db-migrate                   # Apply pending migrations (standalone script)
just db-generate                  # Regenerate Db.fs from live DB (SqlHydra)
just db-update                    # migrate + generate
just db-reset                     # Delete DB, re-apply all, regenerate
```

## Migration Workflows

### After cloning

No code-gen needed — `Db.fs` is committed. Just build and run:

```bash
just server-build    # Db.fs compiles immediately
just server-watch   # DbUp creates app.sqlite3 + applies migrations at startup
```

### Changing the schema

Add a migration, apply it, regenerate types, fix compile errors:

```bash
just db-migration name=add_priority
# … write the SQL (CREATE TABLE, ALTER TABLE, etc.) …
just db-update
# … fix compile errors in the domain module's mapping functions …
just server-build
```

### Starting fresh

```bash
just db-reset
```

Deletes `app.sqlite3`, re-applies all migrations in order, regenerates `Db.fs`.

## Schema

The core schema (accounts, categories, transactions, auto-tagging rules, a
tagging queue, and user preferences) is defined in `Data/Migrations/`. The header
comment of the first migration documents the column type conventions — the
`GUID`, `BOOLEAN`, `DATETIME` etc. hints are not real SQLite types but drive
SqlHydra's F# codegen. See
[SqlHydra's SqliteDataTypes.fs](https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs)
for the full list of supported hints.

At startup `Program.fs` enables WAL journal mode and foreign-key enforcement via
PRAGMA after migrations run — SQLite silently ignores foreign keys otherwise.

## Key Constraints

- **Never modify an already-applied migration.** They run once, in order. Add a
  new file for schema changes.
- **`Db.fs` is auto-generated** by `dotnet sqlhydra sqlite` — record types,
  table declarations, and `QueryContextFactory`. Committed to source control; do
  not hand-edit. `just db-update` regenerates it from the live database.
- **Mapping layer.** Each domain module converts between DB row types and its
  public API type (e.g. `Transaction.toRow` / `Transaction.fromRow`). This is
  the control point — DB columns never leak to the API.
- **Migration paths are part of the schema history.** DbUp keys `SchemaVersions`
  on the migration's resource name (its path under `Data/Migrations/`). Moving
  or renaming an already-applied migration makes DbUp treat it as new and
  re-run it, which fails on an existing database — run `just db-reset` after
  such a move.
- **Standalone migrations.** `scripts/migrate.fsx` applies migrations without
  building the server. This avoids the chicken-and-egg problem where a schema
  change breaks the build before `Db.fs` is regenerated.
- **CI checks generated code.** The `check-db-generated` CI job re-runs the
  migrations and SqlHydra, then fails if `Db.fs` is out of date — run
  `just db-update` after schema changes and commit the regenerated file.

## Error Handling

SqlHydra throws on infrastructure failures (dead connection, disk full). Handlers
run through `Endpoint.handler`, which maps `DomainError` values to HTTP
responses — validation → `400`, not found → `404`, conflict → `409`, everything
else → `500`. A global middleware in `Program.fs` catches any unhandled
exception as a last resort.
