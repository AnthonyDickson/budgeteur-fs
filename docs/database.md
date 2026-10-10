# Database

SQLite with DbUp migrations and SqlHydra type-safe queries. The connection string is `Data Source=app.sqlite3`
(relative, resolves to the server project directory). Override with `ConnectionStrings__Default` in production — use an
absolute path like `/data/app.sqlite3`.

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

The core schema (accounts, categories, transactions, auto-tagging rules, a tagging queue, and user preferences) is
defined in `Data/Migrations/`. The header comment of the first migration documents the codegen hints: `GUID`, `BOOLEAN`,
`DATETIME` and the rest are not real SQLite types, they drive SqlHydra's F# codegen. See
[SqlHydra's SqliteDataTypes.fs](https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs)
for the full list of supported hints.

At startup `Program.fs` enables WAL journal mode after migrations run; WAL is stored in the database file, so it
persists. Foreign keys are a per-connection setting, so `Config.withForeignKeys` adds `Foreign Keys=True` to the
configured connection string and Microsoft.Data.Sqlite turns them on for every connection it opens. The bundled
`e_sqlite3` build also defaults them to on, but the connection string keeps the guarantee independent of build flags;
other SQLite builds silently ignore foreign keys unless asked.

### Date and datetime columns

`DATE` columns hold calendar dates and `DATETIME` columns hold UTC instants. See [Dates and Timestamps](dates.md) for
how each is stored, read, and written.

## Key Constraints

- **Never modify a released migration.** A migration is released once a version tag (created by the Docker Publish
  workflow) contains it; check with `git tag --contains <commit>`. Until then, edit it in place and run `just db-reset`.
  Released migrations run once, in order — add a new file for schema changes.
- **`Db.fs` is auto-generated** by `dotnet sqlhydra sqlite` — record types, table declarations, and
  `QueryContextFactory`. Committed to source control; do not hand-edit. `just db-update` regenerates it from the live
  database.
- **Mapping layer.** Each feature slice's codec module converts between DB row types and its domain type (e.g.
  `TransactionCodec.toRow` / `TransactionCodec.fromRow`). This is the control point — DB columns never leak to the API.
- **Migration paths are part of the schema history.** DbUp keys `SchemaVersions` on the migration's resource name (its
  path under `Data/Migrations/`). Moving or renaming an already-applied migration makes DbUp treat it as new and re-run
  it, which fails on an existing database — run `just db-reset` after such a move.
- **Standalone migrations.** `scripts/migrate.fsx` applies migrations without building the server. This avoids the
  chicken-and-egg problem where a schema change breaks the build before `Db.fs` is regenerated.
- **CI checks generated code.** The `check-db-generated` CI job re-runs the migrations and SqlHydra, then fails if
  `Db.fs` is out of date — run `just db-update` after schema changes and commit the regenerated file.

## Error Handling

SqlHydra throws on infrastructure failures (dead connection, disk full). Handlers run through `Endpoint.handler`, which
maps `DomainError` values to HTTP responses — validation → `400`, not found → `404`, conflict → `409`, everything else →
`500`. A global middleware in `Program.fs` catches any unhandled exception as a last resort.

Database integrity constraints are checked explicitly before writes (`Data/Constraints.fs`): `require*` helpers mirror
the schema's constraints and return a `400` `ValidationFailed` with a friendly message, since SQLite does not always
report which column triggered a violation. Combine them with `requireAll` / `requireOne` so a client sees every failure
in one response. The `409` `Conflict` mapping remains as a safety net for violations the explicit checks cannot catch,
e.g. a concurrent request racing a check-then-write.
