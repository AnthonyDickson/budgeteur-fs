# AGENTS.md

> This file should follow the [AGENTS.md standard](https://agents.md/).

## Project Overview

A full-stack personal finance tracker (accounts, tags, transactions, tagging rules, balance sheet; auto-tagging on the
roadmap).

- **Backend** — Oxpecker F# on .NET 10, SQLite + OIDC auth + OpenAPI (`server/`). Endpoints are organised as vertical
  slices. OpenAPI spec at `/openapi/v1.json`; interactive Scalar docs at `/scalar/v1` (development only).
- **Frontend** — Gleam/Lustre SPA, Tailwind CSS v4, bundled with Vite (`client/`). Nested MVU with a custom effect
  system that keeps `update` pure.

The `Transaction` slice is the reference implementation of the architecture patterns below. Deeper design detail lives
in [docs/architecture.md](docs/architecture.md); database, test, and deployment specifics live in their linked docs. The
balance sheet feature (assets and liabilities) records its domain decisions, rationale, and glossary in
[docs/balance-sheet.md](docs/balance-sheet.md).

## Essential Commands

| Command                    | Purpose                                                    |
| -------------------------- | ---------------------------------------------------------- |
| `just server-build`        | Build the server                                           |
| `just server-watch`        | Run the server at :5000 (auto-applies DB migrations)       |
| `just server-test`         | Server Expecto tests                                       |
| `just client-install-deps` | Install npm packages (first run)                           |
| `just client-watch`        | Client dev server at :5173 (Vite + Gleam watch)            |
| `just client-test`         | Client gleeunit tests                                      |
| `just e2e-test`            | Playwright E2E tests in Docker                             |
| `just format`              | Format markdown (dprint) + Gleam + F#                      |
| `just lint`                | Lint F# with fsharplint + enforce feature-slice boundaries |

Dev environment via Nix: `nix develop` (or `direnv allow`). Run `just client-install-deps` once before any client
command. The justfile is the source of truth for the full target list (`audit`, `outdated`, the `db-*` family).

Quick start either via `docker compose up` (Authelia :9091, server :5000, client :5173; log in with
`dev`/`dev-password`) or natively with `just server-watch` plus `just client-watch` in a second terminal. See
[README.md](README.md) for details.

## Design Principles

Broadly:

- Make the right thing easy: architecture and design should push developers toward correct, clear, concise code.
- Prefer simple, direct code and systemic fixes over workarounds. When code is convoluted, ask whether the design is
  wrong and fix at the right level, so code churn reduces accidental complexity.
- Only add abstractions when there is a clear advantage; avoid over-engineering.

More specifically:

- **Functional programming** — push I/O to the edges, make illegal states unrepresentable, functions as the default
  abstraction, programs as data (the effect system).
- **Domain-Driven Design** (Wlaschin, _Domain Modeling Made Functional_) — start from the pure domain; everything else
  follows.
- **Vertical Slice Architecture** — group code by feature/workflow; some duplication is acceptable, especially when
  establishing new features or when code changes for different reasons; limit blast radius by minimising coupling and
  maximising coherence.
- **Client MVU/TEA** — two-tier shell + page modules; avoid stateful components (nested TEA).
- **Testing** — prefer tests where confidence is low (multi-step/stateful logic, validation, save/error/retry), not
  trivial mappings. Each feature needs at least one test driving the happy path through the real event flow. Only E2E
  tests exercise client-server interactions. Minimise maintenance while maximising confidence.

## Code Review

Reviews push the codebase toward the design principles and are an opportunity to simplify and reduce code. Findings must
be evidence based, reference the offending code, and state severity, likelihood, confidence, recommended fix(es), and
trade-offs.

## Architecture

### Backend vertical slices (reference: `Feature/Transaction/`)

- **`Shared/`** — cross-cutting concerns (`Auth.fs`, `Endpoint.fs`, `Json.fs`, `ApiError.fs`, `DomainError.fs`,
  `Money.fs`, `OpenApi.fs`, `RequestLogging.fs`, `Config.fs`, `Coders.fs`).
- **`Domain/`** — one file per domain type (`Transaction.fs`, `Tag.fs`, `Rule.fs`); value invariants are refined types
  (private single-case unions with `create`/`value`).
- **`Feature/<Name>/`** — one file per HTTP operation (`CreateTransaction.fs`, `ReadTransaction.fs`,
  `ReadAllTransactions.fs`, `UpdateTransaction.fs`, `DeleteTransaction.fs`, …), each exposing a `Path` literal and an
  `endpoint (queryContext)` function. A slice's `Codec.fs` holds the `toRow`/`fromRow` DB mapping and moves to `Data/`
  once a second slice needs it (e.g. `Data/TagCodec.fs`); `<Name>Response.fs` holds the wire DTO.

Handlers run through `Endpoint.handler`, which executes a `Task<Result<unit, DomainError>>` body and composes with
FsToolkit's `taskResult` CE. Routes are `/api/<resource>` (collections) and `/api/<resource>/{id}` (items); every
endpoint carries OpenAPI metadata via `addOpenApi`. IDs are server-generated v7 UUIDs (create requests carry no id). The
`QueryContextFactory` from `Data/Db.fs` is created once in `Program.fs`, threaded into each endpoint, and grouped by
HTTP method behind `Auth.requireAuth`.

#### Dependency rules (kernel boundary)

`Domain/`, `Data/`, and `Shared/` form the shared kernel:

- **One-way dependencies: `Feature/*` → kernel.** The kernel never depends on a slice, and slices never import each
  other (`open Budgeteur.Feature.<OtherSlice>` is forbidden, enforced by `just lint`).
- **Ownership test.** Every type and rule has one owner. A concept belongs in the kernel only if more than one slice
  drives its changes, and it should change less often than its consumers. A kernel module that changes every sprint is
  mis-owned — move it into the slice that drives it.
- **Invariants live with the type in `Domain/`; use-case rules stay in the slice.** Intrinsic validity (non-empty,
  length, rounding) is domain; orchestration (auth, queries, uniqueness, UI flow) is feature.
- **Slices own their read shapes.** A feature needing a different shape (e.g. a dashboard aggregate) defines its own
  read model rather than growing the shared type.

### Request pipeline and errors

`Endpoint.handler` maps each `DomainError` case to an HTTP status: validation → `400`, not found → `404`, conflict →
`409`, missing user claims → `401`, everything else → `500`. Every response is a JSON `ApiError` record (`{ Error;
Details; StatusCode; RequestId }`). No exceptions escape handlers — a global middleware in `Program.fs` catches the
unexpected as a last resort. Database constraints are checked explicitly before writes (see `Data/Constraints.fs`) so
common violations surface as friendly `400` `ValidationFailed` responses; the `409` mapping remains as a safety net for
races.

### Auth & Configuration

Two schemes sit behind a policy scheme selected by the `Authorization: Bearer` header:

- **Cookie** — SPA session, authorization code flow.
- **JWT Bearer** (`"bearer"`) — for the Scalar API docs, PKCE flow (development only).

Either satisfies the `"authenticated"` policy that `requireAuth` enforces on protected endpoints. Routes: `/login`
(challenge, then redirect to the configured return URL) and `/logout`. Outside development cookies use
`SecurePolicy=Always`, `SameSite=Lax`, `HttpOnly=true`, and a 1-hour sliding expiry; in dev `RequireHttpsMetadata=false`
and self-signed certs are accepted.

Settings are strongly-typed sections (`Oidc`, `OAuth2`, `Login`, `Logging`) bound from `appsettings*.json` or
environment variables (e.g. `Oidc__ClientSecret`). Key keys: `Oidc:Authority`, `Oidc:ClientId`, `Oidc:ClientSecret`,
`Oidc:CallbackPath`, optional `Oidc:ValidAudiences`, and `Login:ReturnUrl`. Every section is validated with
DataAnnotations at startup — the server refuses to boot and prints missing or malformed settings. `OAuth2:*` only drives
the Scalar docs' OAuth2 flow, which is served in development only.

Known limits: claims come from the ID token (the userinfo endpoint is not called by default); `/logout` only clears the
local cookie, so the provider session persists (Authelia lacks RP-initiated logout).

### Logging

Dual-layer:

1. **Request-scoped buffered logging** (`RequestLogging.fs`) — handlers append structured entries to a per-request log,
   emitted as a single JSON array in the response log, so related entries stay together rather than interleaved.
2. **Global Serilog pipeline** — startup logs and unhandled exceptions. Console output uses
   `RenderedCompactJsonFormatter`; file output is opt-in via `Logging__FilePath`.

### Database

See [docs/database.md](docs/database.md) for the full picture. Key points:

- `Data/Db.fs` is generated by `dotnet sqlhydra sqlite`, committed to source control, and never hand-edited; use the
  `just db-*` targets. The `toRow`/`fromRow` mapping layer in each slice's codec is the control point — DB columns never
  leak to the API.
- `Data/Migrations/` holds numbered `.sql` files embedded as resources, run once and in order by DbUp at startup,
  tracked in a `SchemaVersions` table. Never modify an already-run migration — add a new file. Renaming or moving an
  applied migration makes DbUp treat it as new and re-run it, which fails on an existing database.
- Migration columns use SqlHydra-compatible type hints (`GUID`, `BOOLEAN`, `DATETIME`, `CURRENCY`, …). These are not
  real SQLite types but drive codegen; the first migration's header comment documents the conventions (v7 UUIDs, UTC
  timestamps, etc.).
- `Data/Constraints.fs` holds hand-written `require*` checks mirroring the schema's integrity constraints, combined with
  `requireAll`/`requireOne` so a client sees every failure in one response (SQLite does not always report which column
  triggered a violation).
- `Program.fs` enables WAL journal mode and foreign-key enforcement after migrations run; SQLite silently ignores
  foreign keys otherwise.
- Connection string: `Data Source=app.sqlite3` (relative to the server project). Override with
  `ConnectionStrings__Default`, using an absolute path (e.g. `/data/app.sqlite3`) in production.

#### Schema workflows

```bash
# After cloning: no code-gen needed — Db.fs is committed. Build and run.
just server-build
just server-watch     # DbUp creates app.sqlite3 + applies migrations at startup

# Changing the schema:
just db-migration name=add_priority   # scaffold a numbered .sql file
# … write the SQL (CREATE TABLE, ALTER TABLE, …) …
just db-update                        # migrate + regenerate Db.fs
# … fix compile errors in the domain module's mapping functions …
just server-build

# Starting fresh:
just db-reset                         # delete the DB, re-apply all, regenerate
```

CI's `check-db-generated` job re-runs migrations and SqlHydra, failing if `Db.fs` is out of date — run `just db-update`
after schema changes and commit the regenerated file.

### Client (Gleam/Lustre SPA)

Two-layer MVU: `app.gleam` is the shell (routing, toasts, session expiry) and each feature page (e.g.
`transaction/transaction_page.gleam`, `tagging_page/tagging_page.gleam`) owns its model, update, and view. The shell
delegates to the active page and maps the page's effects up with `effect.map`. Pages also return an `OutMsg` alongside
model and effect — a child-to-parent channel for shell-level behaviours (currently toasts); the shell's `update` is the
single place child requests become shell effects.

Stateful modals (`transaction_modal`, `tag_modal`, `rule_modal`, delete confirmations) live in the page model, raise
their own `Msg`s (lifted with `element.map`), and return the new modal plus its `Request`s and `Outcome`, which the page
turns into effects and data changes. The underlying state machines are generic: `shared/field.gleam` (tri-state field),
`shared/form_modal.gleam` (create/update reducer), `shared/delete_modal.gleam` (delete confirmation), and
`shared/modal_ui.gleam` (dialog chrome: buttons, banners, error styling). Feature modules alias the shared types and
keep their own entities, forms, and list mutations.

#### Effect system

`update` returns pure data — a description of side effects — and a single `effect.run` interpreter executes them against
the real browser, wired into Lustre via `lustre_effect.from(fn(dispatch) { effect.run(effect, dispatch) })`. Because
effects are plain values, unit tests assert on them without a browser or HTTP mocking. The `Effect` type in
`shared/effect.gleam` is the source of truth; variants cover HTTP requests, localStorage load/save, navigation (history
push/replace, hard redirects), browser chrome (document title, native `<dialog>` show/close), timers, generic message
dispatch, batching, and no-ops. Thin per-method constructors (`effect.get`/`post`/`put`/`patch`/`delete`) cover the
common HTTP cases. Pages own their localStorage persistence: each serialises its own data after updates and restores it
in `init`.

Supporting modules:

- `shared/http_effect.gleam` — `HttpMethod`, `HttpError`, and `send`. Returns the raw body: 2xx as `Ok`, anything else
  as `Error(HttpError(status, body))`, transport failures as `NetworkError`. `HttpRequest` carries a `transform` hook
  for per-request customisation (auth headers).
- `shared/effect_ffi.mjs` — thin JS wrappers for localStorage, redirects, dialog controls, and client-side navigation.
- `shared/guard.gleam` — `use`-compatible early-return helpers for `Option`/`Result` (strict and lazy), mirroring
  `gleam/bool.lazy_guard`.
- `shared/response.gleam` — 2xx body → typed `Result` and `HttpError` → `ApiError` decoding.

The shell also handles, unseen by pages: **routing** (no router library — `effect.init_routing` intercepts internal link
clicks and back/forward navigation, delivering paths to `update`; routes are declared in `shared/route.gleam`, unknown
paths render a 404), **model persistence** (pages persist themselves; the shell does not), and **session expiry** (HTTP
effects are rewritten so a `401` dispatches `SessionExpired` and the app redirects to login, rather than reaching the
page's callback).

The client always requests same-origin URLs (`location.origin` prefixed). In dev, Vite proxies `/api`, `/login`,
`/logout`, and `/signin-oidc` to the backend (`BACKEND_URL` or `http://localhost:5000`); in production the server serves
the SPA itself. This is why no CORS is configured anywhere.

#### When to add a page

| Condition                               | Pattern              |
| --------------------------------------- | -------------------- |
| Single feature, one concern             | Add to existing page |
| New feature with independent state      | New page module      |
| Feature shares state with existing page | Extend existing page |
| Global state (auth, theme, user prefs)  | Extend shell model   |

### Tests

Three layers. Each has a dedicated doc:

- **Server** — Expecto (`just server-test`). An in-memory SQLite `TestApp` (via `HostBuilder` + `TestServer`) wires each
  feature's `GET`/`POST`/`PUT`/`DELETE` endpoint lists directly — the same grouping as `Program.fs`, minus the auth
  middleware that needs the full OIDC/JWT setup — and injects a fake `ClaimsPrincipal` with a `sub` claim. A fresh app
  per test gives an empty database. See [docs/server-tests.md](docs/server-tests.md).
- **Client** — gleeunit (`just client-test`), pure `update` unit tests in `client/test/`: call `update` with a model and
  message, then assert on the returned model and inspect the `Effect` payload. No browser or DOM. See
  [docs/architecture.md](docs/architecture.md).
- **E2E** — Playwright (`just e2e-test`), the full stack in Docker Compose with host networking (Authelia → server →
  Vite → Playwright) and a fresh database per run. Tests log in once in global setup and capture screenshots. Use
  `data-testid` attributes for selectors — add them to feature page views when introducing new interactive elements. See
  [docs/e2e-tests.md](docs/e2e-tests.md).

### Static Assets

- **Client assets** (images, fonts, favicons, PDFs — anything the SPA references) live in `client/public/`. Vite serves
  them at root in dev and copies them into `dist/` on build; they reach the server via `just copy-client-dist`.
- **Server-only assets** (e.g. `robots.txt`) live in `server/src/Budgeteur/wwwroot/`. That directory is gitignored and
  recreated by `copy-client-dist`, so the source of truth for any persisted file must live elsewhere (e.g. a build
  step).

### Deployment

`just publish` builds the client, copies it into `wwwroot/`, and produces a self-contained single-file server binary
(`RUNTIME` selects the target, default `linux-x64`). Docker uses a multi-stage build publishing into a minimal
`debian:stable-slim` image running as non-root `appuser`. The server is intended to run behind a reverse proxy
(nginx/Caddy) — it is not hardened to face the internet directly. Container health checks probe `GET /api/status`, which
reports build version, uptime, and DB connectivity, returning `503` when the database is unreachable. See
[docs/deployment.md](docs/deployment.md).

## Conventions

- **User scoping** — every query filters by `UserId`, resolved from the `sub` claim. New slices must follow this or they
  will leak data across users.
- **Money** — amounts are `decimal`, rounded to cents with `Money.roundToCents` (`MidpointRounding.AwayFromZero`), and
  serialised as JSON strings, not numbers.
- **Secrets** — never log secrets or tokens; source them from environment variables / config sections, not source
  control.

## Code Style

- **Formatting** (fantomas via `.editorconfig`): Stroustrup bracket style; spaces before parameters/colons/invocations;
  space after commas and semicolons, not before.
- **Naming**: PascalCase modules matching filenames; camelCase functions; PascalCase types (records/DUs);
  `[<RequireQualifiedAccess>]` on modules exposing a type alias.
- **Error handling**: handlers return `Result<unit, DomainError>`; `Endpoint.handler` maps each case to a JSON
  `ApiError` with the appropriate status code. No exceptions escape handlers.

## Verification & CI

CI runs server tests, client tests, Gleam/F#/markdown format checks, and the `check-db-generated` job. Before finishing
work, run the relevant tests plus `just lint` and `just format`; after schema changes run `just db-update` and commit
the regenerated `Db.fs`. When a CI check fails, its log message names the local command to reproduce it (e.g. `just
server-test`, `just format`).

## Gotchas

- **Compilation order**: F# compiles server files in the order listed in `.fsproj` — insert new `.fs` files before files
  that depend on them.
- **SqlHydra query parameters**: function parameters can't be captured directly in query expressions. Bind them to local
  `let` values first (e.g. `let idStr = id.ToString()` before using it in a `where` clause).
- **Central Package Management**: versions live in `Directory.Packages.props`; project files use bare `<PackageReference
  Include="..." />`.
- **Client install**: run `npm install` (or `just client-install-deps`) before the first `just
  client-watch`/`client-build`.
- **Request body limit**: Kestrel caps request bodies at 64 KB (`Program.fs`) — relevant when wiring the CSV import.
