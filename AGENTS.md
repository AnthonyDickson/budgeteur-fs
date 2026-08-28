# AGENTS.md

## Project Overview

A full-stack web app with an Oxpecker F# .NET 10 backend (SQLite + OIDC auth + OpenAPI) and a Gleam/Lustre SPA frontend styled with Tailwind CSS v4 and bundled with Vite.

The domain is a personal finance tracker: accounts, tags (categories), and transactions, with auto-tagging rules on the roadmap. The `Transaction` slice is the reference implementation of the architecture patterns below.

## Essential Commands

```bash
just db-migration name=add_foo  # Scaffold a new migration file
just db-update                  # db-migrate + db-generate (full schema update)
just db-reset                   # Delete DB, re-apply all migrations, regenerate
just server-build         # Build the server
just server-watch         # Run the server (auto-applies DB migrations)
just server-test          # Server Expecto tests
just client-install-deps  # npm install
just client-watch         # Start the client dev server (Vite + Gleam watch)
just client-test          # Client gleeunit tests
just e2e-test             # Playwright E2E tests in Docker
just format               # Format markdown (dprint) + Gleam + F#
just lint                 # Lint F# with fsharplint
```

The justfile is the source of truth for the full target list (`audit`, `outdated`, and the `db-*` family).

Dev environment via Nix: `nix develop` (or `direnv allow`). Before client commands, run `just client-install-deps` to install npm packages.

## Architecture

### Auth (`Auth.fs`)

Uses `Microsoft.AspNetCore.Authentication.OpenIdConnect` with two schemes behind a policy scheme:

- **Cookie** — SPA session, authorization code flow.
- **JWT Bearer** (`"bearer"`) — for the Scalar API docs, PKCE flow.

Either satisfies the `"authenticated"` authorization policy that `requireAuth` enforces on protected endpoints. Auth routes: `/login` (challenge, then redirect to the configured return URL) and `/logout`.

Cookie defaults outside development: `SecurePolicy=Always`, `SameSite=Lax`, `HttpOnly=true`, 1-hour sliding expiry. In dev, `RequireHttpsMetadata=false` and self-signed certs are accepted.

Config via `Oidc:Authority`, `Oidc:ClientId`, `Oidc:ClientSecret`, `Oidc:CallbackPath`, optional `Oidc:ValidAudiences`, and `Login:ReturnUrl`. The `OAuth2:*` settings only drive the Scalar docs' OAuth2 flow, which is served **in development only** (see `Program.fs`).

Known limits: claims come from the ID token (the userinfo endpoint is not called by default), and `/logout` only clears the local cookie — the provider session persists (Authelia lacks RP-initiated logout).

### Vertical Slice Architecture (reference: `Feature/Transaction/`)

The server is split across three folders:

- **`Shared/`** — cross-cutting concerns: `Auth.fs`, `Endpoint.fs`, `Json.fs`, `ApiError.fs`, `DomainError.fs`, `Money.fs`, `OpenApi.fs`, `RequestLogging.fs`, `Config.fs`, `Coders.fs`.
- **`Domain/`** — one file per domain type (`Transaction.fs`, `Tag.fs`, `Rule.fs`).
- **`Feature/<Name>/`** — one file per HTTP operation (`CreateTransaction.fs`, `ReadTransaction.fs`, `ReadAllTransactions.fs`, `UpdateTransaction.fs`, `DeleteTransaction.fs`, …), each exposing a `Path` literal and an `endpoint (queryContext)` function. `<Name>Codec.fs` holds the `toRow` / `fromRow` DB mapping and `<Name>Response.fs` the wire DTO; value invariants live with the type in `Domain/` as refined types (private single-case unions with `create` / `value`).

Handlers run through `Endpoint.handler`, which executes a `Task<Result<unit, DomainError>>` body and maps `DomainError` values to HTTP responses (see `Shared/Endpoint.fs`). Routes use `/api/<resource>` for collections and `/api/<resource>/{id}` for items; each endpoint is decorated with OpenAPI metadata via `addOpenApi`. IDs are v7 UUIDs generated server-side — create requests carry no id.

The `QueryContextFactory` (from `Data/Db.fs`) is created once in `Program.fs` and threaded into each operation's `endpoint` function. `Program.fs` groups them by HTTP method (`GET` / `POST` / `PUT` / `DELETE`) and wraps the feature lists with `Auth.requireAuth`.

#### Dependency rules (kernel boundary)

`Domain/`, `Data/`, and `Shared/` together form the shared kernel. Its contract:

- **Dependencies flow one way: `Feature/*` → `Domain/`, `Data/`, `Shared/`.** Nothing in the kernel may depend on a feature slice, and one feature slice must never import another (`open Budgeteur.Feature.<OtherSlice>` is forbidden — enforced by the `lint` target).
- **Ownership test.** Every type and rule has exactly one owner. A concept belongs in the kernel only if changes to it are driven by more than one slice, and it should change less often than its consumers. If a kernel module changes every sprint, it is mis-owned — move it into the slice that drives its changes.
- **Value invariants live with their type in `Domain/`; use-case rules stay in the slice.** Intrinsic validity (non-empty, length limits, rounding) belongs in the domain; orchestration that varies per use case (auth, queries, uniqueness checks, UI flow) belongs in the feature.
- **Slices own their read shapes.** When a feature needs a shape that differs from the shared domain type (e.g. a dashboard aggregate), it defines its own read model inside the feature rather than growing the shared type.

### Database (`Db.fs` + `Data/Constraints.fs` + `Data/Migrations/`)

- **`Db.fs`** — Auto-generated by `dotnet sqlhydra sqlite`. Contains record types, table declarations, and `QueryContextFactory`. Committed to source control — compiles immediately after clone, no code-gen needed. Do not modify directly, use the just targets.
- **`Data/Constraints.fs`** — Hand-written `require*` checks mirroring the schema's integrity constraints, returning friendly `ValidationFailed` errors via `requireAll` / `requireOne` (SQLite doesn't always report which column triggered a violation).
- **`Data/Migrations/`** — Numbered `.sql` files embedded as resources. DbUp runs them in order at startup, tracking applied scripts in a `SchemaVersions` table. Use SqlHydra-compatible type hints (`GUID`, `BOOLEAN`, `DATETIME`, `CURRENCY`, …) in column definitions — these aren't real SQLite types but influence codegen. See [SqlHydra's SqliteDataTypes.fs](https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs). The first migration's header comment documents the column type conventions (UUID v7, UTC timestamps, etc.).
- **`scripts/migrate.fsx`** — Standalone DbUp migration runner that reads SQL files directly from disk. Used by `just db-migrate` to apply migrations without building the server — avoids the chicken-and-egg problem where a schema change breaks the build before `Db.fs` is regenerated.
- **PRAGMAs** — `Program.fs` enables WAL journal mode and foreign-key enforcement after migrations run; SQLite silently ignores foreign keys otherwise.
- **Error handling** — SqlHydra throws on infrastructure failures (dead connection, disk full); handlers map `DomainError` to HTTP responses via `Endpoint.handler`, and a global middleware in `Program.fs` catches any unhandled exception as a last resort.

#### Schema Workflows

**After cloning:**

```bash
cd server && dotnet restore
just server-build    # Db.fs is committed — compiles immediately
just server-watch   # DbUp creates the database + applies migrations at startup
```

**Changing the schema:**

```bash
just db-migration name=add_priority   # scaffolds a new .sql migration
# … write the SQL in the new file …
just db-update                        # apply migrations + regenerate types
# … fix compile errors in the domain module's mapping functions …
just server-build
```

**Starting fresh:**

```bash
just db-reset                         # delete DB, re-apply all migrations, regenerate
```

**Key constraints:**

- Migration files are applied once, in order — never modify an already-run migration. Add a new file for changes.
- `Db.fs` is auto-generated — do not hand-edit. The mapping layer in the feature slices' `*Codec.fs` (`toRow` / `fromRow`) is the control point for DB ↔ API type conversions.
- Connection string is `Data Source=app.sqlite3` (relative, resolves to the server project). Override with an absolute path (e.g. `/data/app.sqlite3`) in production via `ConnectionStrings__Default` env var.

### Logging Architecture

The server uses a dual-layer logging system:

1. **Request-scoped buffered logging** (`RequestLogging.fs`): Collects structured log entries during request processing, then emits them as a single JSON array in the response log. This keeps related log entries together rather than interleaved.
2. **Global Serilog pipeline** (`Serilog.AspNetCore`): Handles startup logs and unhandled exceptions. Console output uses `RenderedCompactJsonFormatter`. File output is opt-in via `Logging__FilePath`.

### Client (Gleam/Lustre SPA)

Two-layer MVU: `app.gleam` is the shell (routing, toasts, model persistence, session expiry) and each feature page (e.g. `transactions/transactions_page.gleam`) owns its model, update, and view. The shell delegates to the active page and maps its effects up with `effect.map`.

- `effect.gleam` — Custom `Effect` type (pure data) + interpreter (`run`) + `map`/`batch`/`none` helpers + thin per-method HTTP constructors (`get`, `post`, `put`, `patch`, `delete`). Feature modules only need to import `effect` for everyday effects.
- `http_effect.gleam` — HTTP transport: `HttpMethod`, `HttpError` (transport vs. status-code errors), and `send` with a `transform` hook for per-request customisation (auth headers).
- `effect_ffi.mjs` — Thin JS wrappers for `window.localStorage`, redirects, dialog controls, and client-side navigation.
- `guard.gleam` — `use`-compatible early-return helpers for `Option`/`Result`.
- `response.gleam` — 2xx body → typed `Result` and `HttpError` → `ApiError` helpers.
- `out_msg.gleam` — child → parent channel; pages return an `OutMsg` alongside model and effect to request shell-level behaviours (currently toasts).

See [docs/architecture.md](docs/architecture.md) for the full design.

### Effect System Design

`update` returns pure data — a description of side effects — and a single `effect.run` interpreter executes them against the real browser, keeping `update` functions testable without mocking. The `Effect` type in `effect.gleam` is the source of truth for the variants; broadly they cover HTTP, localStorage, navigation/history, browser chrome (title, dialogs), timers, message dispatch, batching, and no-ops. The shell adds two cross-cutting behaviours on top of every page's effects: serialising the whole model to localStorage after each update, and rewriting HTTP effects so a `401` response redirects to the login route.

Bridging into Lustre: the shell wraps the custom `Effect` in Lustre's opaque `lustre_effect.Effect` via `lustre_effect.from(fn(dispatch) { effect.run(effect, dispatch) })`.

### Tests

Three layers — see the linked docs for details:

- Server: Expecto (`just server-test`). An in-memory SQLite `TestApp` wires each feature's `GET`/`POST`/`PUT`/`DELETE` endpoint lists directly (same grouping as `Program.fs`, minus auth) — see [docs/server-tests.md](docs/server-tests.md).
- Client: gleeunit (`just client-test`), pure `update` unit tests, no browser — see [docs/architecture.md](docs/architecture.md).
- E2E: Playwright (`just e2e-test`), full stack in Docker Compose with Authelia — see [docs/e2e-tests.md](docs/e2e-tests.md). E2E tests use `data-testid` attributes for selectors — add them to feature page views when new interactive elements are introduced.

### Static Assets

**Client assets** (images, fonts, favicons, PDFs — anything the SPA references) live in `client/public/`. Vite serves them at root in dev and copies them into `dist/` on build. They reach the server via `just copy-client-dist`.

**Server-only assets** (e.g. `robots.txt` that should exist regardless of the client bundle) live in `server/src/Budgeteur/wwwroot/`. Note that `wwwroot/` is gitignored and recreated by `copy-client-dist`, so the source of truth for any persisted file must live elsewhere (or use a build step).

## Conventions

- **User scoping** — every query filters by `UserId`, resolved from the `sub` claim. New slices must follow this or they will leak data across users.
- **Money** — amounts are `decimal`, rounded to cents with `Money.roundToCents` (`MidpointRounding.AwayFromZero`), and serialised as JSON strings, not numbers.

## Code Style & Conventions

### Formatting (fantomas via `.editorconfig`)

- Stroustrup bracket style, spaces before parameters/colons/invocations
- Space after commas and semicolons, not before

### Naming

- Modules: PascalCase, matching filename
- Functions: camelCase
- Types (records, DUs): PascalCase
- `[<RequireQualifiedAccess>]` on modules that expose a type alias

### Error Handling

Handlers return `Result<unit, DomainError>` and `Endpoint.handler` maps each case to a JSON `ApiError` record (`{ Error; Details; StatusCode; RequestId }`) with the appropriate HTTP status code. No exceptions escape handlers.

## Gotchas

- **Lockfile enforced**: After adding/updating NuGet packages, run `dotnet restore --force-evaluate <project>`.
- **Compilation order**: F# compiles server files in the order listed in `.fsproj` — insert new `.fs` files before files that depend on them.
- **SqlHydra query parameters**: Function parameters can't be captured directly in query expressions. Bind them to local `let` values first (e.g. `let idStr = id.ToString()` before using in a `where` clause).
- **Central Package Management**: Versions in `Directory.Packages.props`; project files use bare `<PackageReference Include="..." />`.
- **Client needs `npm install`** before first `just client-watch` or `just client-build`.
- **Request body limit** — Kestrel caps request bodies at 64 KB (`Program.fs`); relevant when wiring the CSV import.
