# Architecture

A full-stack web app: an F#/Oxpecker backend (SQLite + OIDC auth + OpenAPI) and
a Gleam/Lustre SPA frontend (Tailwind CSS v4, Vite). This doc covers the shape
of both halves and how they fit together. See `AGENTS.md` for commands,
workflows, and gotchas; `docs/database.md`, `docs/server-tests.md`, and
`docs/e2e-tests.md` for the details of those areas.

## Backend

### Vertical slices

The server is split across three folders, and `Feature/Transaction/` is the
reference implementation:

- **`Shared/`** — cross-cutting concerns (`Auth.fs`, `Endpoint.fs`, `Json.fs`,
  `ApiError.fs`, `DomainError.fs`, `Money.fs`, `OpenApi.fs`, …).
- **`Domain/`** — one file per domain type (`Transaction.fs`, `Tag.fs`, `Rule.fs`).
- **`Feature/<Name>/`** — one file per HTTP operation (`CreateTransaction.fs`,
  `ReadTransaction.fs`, `ReadAllTransactions.fs`, `UpdateTransaction.fs`,
  `DeleteTransaction.fs`, …), each exposing a `Path` literal and an
  `endpoint (queryContext)` function. `<Name>Codec.fs` holds the `toRow` /
  `fromRow` DB mapping; value invariants live with the type in `Domain/`.

The `QueryContextFactory` (from the generated `Data/Db.fs`) is created once in
`Program.fs` and threaded into each operation's `endpoint` function; there,
endpoints are grouped by HTTP method (`GET` / `POST` / `PUT` / `DELETE`) and
feature lists are wrapped with `Auth.requireAuth`. Routes use
`/api/<resource>` for collections and `/api/<resource>/{id}` for items. IDs are
v7 UUIDs generated server-side — create requests carry no id.

### Domain invariants and wire types

Value invariants are enforced at the type level with **refined types**: a
single-case union with a private case, defined in the same `Domain/` file as the
aggregate that owns the field it refines.

```fsharp
type TagName = private TagName of string

module TagName =
    let create (s : string) : Result<TagName, DomainError> = ...  // validation lives here
    let value (TagName s) : string = s                             // the only way out
```

Rules:

- **The refined type replaces the `Validation` module** — `create` subsumes the
  old `validateAndTrim*` functions, which are removed. Currently: `TagName` for
  `Tag`, `RulePattern` for `Rule`, `TransactionDescription` for `Transaction`.
- **Records stay public.** An invalid record is unconstructable because a
  refined field value cannot be obtained without passing `create`. Do not hide
  the record constructor — F# cannot split constructor privacy from field
  access, and hiding the fields breaks `toRow` and the Thoth reflection encoder
  (`Json.write` serialises public properties only).
- **Field access is via `value`**, at exactly two sanctioned unwrap points per
  slice: `toRow` and the DTO mapping. Outside the owning module, refined values
  are opaque tokens; pattern matching on the case is not possible because it is
  `private`. Structural equality still applies, so tests can assert on refined
  values directly without unwrapping.
- **Placement**: a refined type lives with its sole consumer. Promote it to a
  shared location (e.g. `Domain/Shared.fs`) only when a second consumer appears.

Responses never serialise refined types. Each slice defines a **response DTO**
with primitives only, in its own file (`Feature/Tag/TagResponse.fs`, already
wired in the `.fsproj`):

```fsharp
type TagResponse = { Id : Guid; Name : string }

module TagResponse =
    let fromDomain (t : Tag) : TagResponse = { Id = t.Id; Name = TagName.value t.Name }
```

- DTOs are encode-only (responses); decoding goes through the raw-string
  request DTOs defined inline in the endpoint files.
- Because DTOs contain only primitives, both serialisers work with zero custom
  code: Thoth's `Encode.toStringAuto` for payloads and the STJ-based OpenAPI
  schema generation (`responseBodies` reference `typeof<TagResponse>`).
- **Keep DTO mapping separate from DB mapping.** `TagCodec.fs` (`toRow` /
  `fromRow`) is SqlHydra-coupled and changes with the schema; `TagResponse.fs`
  is pure F# and changes with the API contract — different dependencies and
  different change drivers, so they never merge.
- `fromRow` is the sanctioned trusted bypass for the DB → domain direction:
  rows were validated on write, so `fromRow` does not re-validate.

### Request pipeline and errors

Handlers run through `Endpoint.handler`, which executes a
`Task<Result<unit, DomainError>>` body and maps `DomainError` values to HTTP
responses: validation → `400`, not found → `404`, conflict → `409`, missing
user claims → `401`, everything else → `500`. Each response is a JSON `ApiError`
record (`{ Error; Details; StatusCode; RequestId }`). No exceptions escape
handlers — a global middleware in `Program.fs` catches the unexpected as a last
resort. Handlers compose with FsToolkit's `taskResult` CE.

Database constraints are checked explicitly before writes via
`Data/Constraints.fs`, so common violations surface as `400` `ValidationFailed`
responses rather than the generic `409` conflict fallback — see
[docs/database.md](database.md).

### Auth

Two authentication schemes sit behind a policy scheme that selects the handler
by checking for an `Authorization: Bearer` header:

- **Cookie** — SPA session, authorization code flow.
- **JWT Bearer** (`"bearer"`) — for the Scalar API docs, PKCE flow (dev only).

Either satisfies the `"authenticated"` policy enforced by `requireAuth`. Auth
routes: `/login` (challenge, then redirect to the configured return URL) and
`/logout`.

Cookie defaults outside development: `SecurePolicy=Always`, `SameSite=Lax`,
`HttpOnly=true`, 1-hour sliding expiry. In dev, `RequireHttpsMetadata=false` and
self-signed certs are accepted.

Claims come from the ID token — the userinfo endpoint is not called by default.
Audience validation is off unless `Oidc:ValidAudiences` is set (Authelia access
tokens carry no `aud` claim). `/logout` only clears the local cookie; the
provider session persists (Authelia lacks RP-initiated logout).

### Configuration

Settings are strongly-typed config sections (`Oidc`, `OAuth2`, `Login`,
`Logging`) bound from `appsettings*.json` or environment variables (e.g.
`Oidc__ClientSecret`). Every section is validated with DataAnnotations at
startup — the server refuses to boot and prints every missing or malformed
setting. `OAuth2:*` only drives the Scalar docs' OAuth2 flow, which is served in
development only.

### Database

SQLite with DbUp migrations and SqlHydra type-safe queries. See
[docs/database.md](database.md) for the full picture; the key design points:

- Numbered migration `.sql` files are embedded in the assembly, applied in
  order at startup, tracked in a `SchemaVersions` table. Never modify an
  already-applied migration.
- `Data/Db.fs` is SqlHydra-generated and committed. SqlHydra-compatible type hints
  (`GUID`, `BOOLEAN`, `DATETIME`, `CURRENCY`, …) in migration columns are not
  real SQLite types but drive codegen; the first migration's header comment
  documents the conventions (v7 UUIDs, UTC timestamps, etc.).
- The `toRow` / `fromRow` mapping layer is the control point — DB columns never
  leak to the API.
- `Data/Constraints.fs` holds explicit `require*` checks mirroring the schema's
  integrity constraints, to give friendly `ValidationFailed` errors.
- `Program.fs` enables WAL journal mode and foreign-key enforcement after
  migrations run; SQLite silently ignores foreign keys otherwise.
- `scripts/migrate.fsx` applies migrations without building the server, so a
  schema change can be migrated and `Data/Db.fs` regenerated before the domain code
  is fixed. CI re-runs this and fails if `Data/Db.fs` is out of date.

### Logging

Two layers:

1. **Request-scoped buffered logging** (`RequestLogging.fs`) — handlers append
   structured entries to a per-request log, emitted as a single JSON array in
   the response log, so related entries stay together.
2. **Global Serilog pipeline** — startup logs and unhandled exceptions. Console
   output uses `RenderedCompactJsonFormatter`; file output is opt-in via
   `Logging__FilePath`.

### Status endpoint

`GET /api/status` reports the build version, uptime, and a database
connectivity probe, returning `503` when the database is unreachable. Container
healthchecks depend on it.

## Frontend

Gleam/Lustre SPA. The app is organised as a thin shell plus feature pages, and
all I/O flows through a custom `Effect` type with a single interpreter so
`update` functions stay pure and testable.

### Layered MVU

Two layers: `app.gleam` is the shell (routing, toasts, model persistence,
session expiry) and each feature page (e.g. `transactions/transactions_page.gleam`)
owns its own model, update, and view. The shell delegates to the active page and
maps the page's effects up to its own message type with `effect.map`.

Pages additionally return an `OutMsg` alongside the new model and effect. This is
a child-to-parent channel for requesting shell-level behaviours — currently used
for toast notifications, but the mechanism is generic. A parent's `update` is
therefore the single place where child requests are turned into shell effects.

### Effect system

`update` returns pure data — a description of the side effects to perform. One
interpreter (`effect.run`) executes them against the real browser, wired into
Lustre via `lustre_effect.from`. Because effects are plain values, unit tests
can assert on them without a browser or HTTP mocking.

The `Effect` type in `effect.gleam` is the source of truth for the full list of
variants. Broadly they cover:

- HTTP requests (via `http_effect.send`)
- localStorage load/save
- Navigation: client-side history push/replace, hard redirects
- Browser chrome: document title, native `<dialog>` show/close
- Timers and generic message dispatch
- Batching and no-ops

Thin per-method constructors (`effect.get`, `post`, `put`, `patch`, `delete`)
cover the common HTTP cases. `HttpRequest` also carries a `transform` hook for
per-request customisation (e.g. auth headers).

### HTTP layer

`http_effect.send` returns the raw response body as a string — 2xx as `Ok`,
anything else as `Error(HttpError(status, body))`, and transport failures as
`NetworkError`. Callers decode with the helpers in `response.gleam`.

### API routing (dev vs prod)

The client always requests same-origin URLs (it prefixes paths with
`location.origin`). In dev, Vite proxies the backend paths (`/api`, `/login`,
`/logout`, `/signin-oidc`) to the .NET server — `BACKEND_URL` or
`http://localhost:5000` — and in production the server serves the SPA itself.
This is why no CORS is configured anywhere.

### Guard helpers

`guard.gleam` provides `use`-compatible early-return helpers for `Option` and
`Result`, mirroring `gleam/bool.lazy_guard` (both strict and lazy variants).

### Shell responsibilities

Things the shell does that feature pages should not know about:

- **Routing** — no router library. `effect.init_routing` intercepts clicks on
  internal links and back/forward navigation, delivering each path to `update`
  as a message. Routes are declared in `route.gleam`; unrecognised paths render
  a 404 page.
- **Model persistence** — after every update the whole model is serialised to
  localStorage and restored on startup, so the UI survives page reloads.
- **Session expiry** — HTTP effects are rewritten so that a `401` response
  dispatches `SessionExpired` instead of reaching the page's callback, and the
  app redirects to the login route.

### Client tests

Pure unit tests in `client/test/` using gleeunit. No browser or DOM — tests
call `update` with a `Model` and `Msg`, then assert on the returned `Model` and
inspect the `Effect` payload.

```bash
just client-test
```

### When to add a page

| Condition                               | Pattern              |
| --------------------------------------- | -------------------- |
| Single feature, one concern             | Add to existing page |
| New feature with independent state      | New page module      |
| Feature shares state with existing page | Extend existing page |
| Global state (auth, theme, user prefs)  | Extend shell model   |

## Conventions

- **User scoping** — every server query filters by `UserId`, resolved from the
  `sub` claim. New slices must follow this or they will leak data across users.
- **Money** — amounts are `decimal`, rounded to cents with `Money.roundToCents`
  (`MidpointRounding.AwayFromZero`), and serialised as JSON strings, not
  numbers.
