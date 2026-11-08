# Kotlin server PoC

An exploration of what the backend would look like written in Kotlin only, in a
functional-first style. It owns its schema and conventions and shares nothing
with the F# server except the HTTP API shape, which the Gleam client depends on.
It covers the infrastructure, the SPA's login and logout, and two slices: `GET
/api/status` and Tag CRUD (`/api/tags`).

## Running

From the dev shell (`nix develop`, which includes JDK 21 and Gradle):

| Command                                | Purpose                   |
| -------------------------------------- | ------------------------- |
| `just kt-test`                         | Run the tests             |
| `just kt-format`                       | Format with ktfmt         |
| `gradle installDist` (in `server-kt/`) | Build `build/install/...` |

The server reads its settings from environment variables. It reports every
missing or invalid setting at once and exits. On startup it applies pending
migrations.

| Variable                     | Purpose                                                         |
| ---------------------------- | --------------------------------------------------------------- |
| `BUDGETEUR_DATABASE`         | SQLite file path                                                |
| `OIDC_AUTHORITY`             | The provider's issuer URL                                       |
| `OIDC_CLIENT_ID`             | The SPA login's client                                          |
| `OIDC_CLIENT_SECRET`         | Its secret                                                      |
| `OIDC_CALLBACK_PATH`         | Optional, default `/signin-oidc`                                |
| `OIDC_VALID_AUDIENCES`       | Optional, comma separated; bearer tokens only                   |
| `OIDC_LOGOUT_URL`            | Optional: the provider's logout page                            |
| `LOGIN_RETURN_URL`           | Absolute URL a login returns to, e.g. `http://localhost:5173/`  |
| `BUDGETEUR_SESSION_KEY_FILE` | Optional: cookie keys, created if missing, so sessions persist  |
| `PORT`                       | Optional, default 5000                                          |
| `BUDGETEUR_ENVIRONMENT`      | `Development` trusts the provider's self-signed TLS certificate |

Against the dev Authelia (`docker compose -f docker/docker-compose.yml up
authelia`), use the values in the F# server's `appsettings.Development.json`.

## Stack

| Concern         | Choice                                                |
| --------------- | ----------------------------------------------------- |
| HTTP            | Ktor 3 on Netty                                       |
| Errors          | Arrow `Either` and the `Raise` DSL (`either { }`)     |
| Validation      | Arrow `zipOrAccumulate`                               |
| JSON            | kotlinx.serialization                                 |
| Database        | SQLite through jOOQ, table code generated from schema |
| Migrations      | Flyway, SQL scripts in `src/main/resources/db/`       |
| SPA login       | OIDC code flow (Nimbus OAuth 2.0 / OIDC SDK)          |
| SPA session     | Encrypted cookie (Ktor Sessions)                      |
| API auth        | OIDC JWT bearer (`ktor-server-auth-jwt`)              |
| Request logging | One wide event per request (Ktor plugin + Logback)    |
| Tests           | kotlin.test (JUnit 5) and Ktor `testApplication`      |

## Layout

Vertical slices, as in the F# server:

- `feature/<name>/` holds one file per operation: its queries as private
  extension functions on jOOQ's `DSLContext`, and a `Route` extension that
  registers the handler. `TagEndpoints.kt` registers the slice. The file is the
  module, so there are no wrapping `object`s.
- `domain/` is the pure model, `data/` the codecs (extension functions between
  generated records and the domain) and constraint checks, `shared/` the
  infrastructure. Slices depend on these, never on each other.
- `App.kt` builds the application from a `Dependencies` value (database, clock,
  OIDC client, cookie keys, bearer setup); `Main.kt` is the imperative shell
  that reads config, migrates and starts serving. The test host builds its own
  `Dependencies` with a database in a temporary file, so locking behaves as in
  production, a fake bearer provider driven by an `X-Test-User` header, and a
  fake OIDC provider that logs in whoever the authorization code names.

## Design notes

- **Raise contexts.** Fallible functions declare their error type as a context
  parameter, `context(_: Raise<E>)`, and return the plain value, so callers
  compose them without wrapping or unwrapping `Either`. Context parameters are
  stable from Kotlin 2.4, and Arrow's `arrow.core.raise.context` package
  provides `raise`, `ensure`, `withError` and `zipOrAccumulate` in this form.
  `Either` appears only at the edges: in tests and in loading config.
- **Handlers.** A handler is a block with a `Raise<DomainError>` context, run by
  the `handle` extension on the call. `DomainError` holds only the failures a
  handler expects (validation, not found), and the handler wrapper writes them
  as JSON errors. Unexpected failures stay exceptions, and Ktor's StatusPages
  plugin writes them as JSON errors. jOOQ wraps driver exceptions, so it looks
  through the causes to tell a constraint violation (409) from other database
  errors (500).
- **JSON.** Ktor's ContentNegotiation plugin reads and writes bodies with
  kotlinx.serialization. A body that does not decode is a validation failure.
- **Validation.** Domain constructors raise a plain `String`. The request parser
  accumulates every field's failure and raises one `ValidationFailed` with one
  line per failure.
- **Refined types.** `TagName` is a `@JvmInline value class` with a private
  constructor, so the only way to build one from input is `TagName.create`.
  Payload-free choices (`TagColor`, `TagKind`) are enums; choices with data are
  sealed interfaces (`DomainError`), matched exhaustively with `when`.
- **Constraint checks.** Handlers check database constraints before writing.
  Each check raises a `ConstraintError`; `requireAll` runs every check and turns
  the failures into one `ValidationFailed`.
- **Transactions.** A handler that checks then writes does both in one
  transaction, and raising inside it rolls the transaction back. Transactions
  begin `IMMEDIATE`, taking SQLite's write lock at the start, so a concurrent
  writer waits and then sees the committed row. With SQLite's default deferred
  transactions the second writer would fail at its write with
  `SQLITE_BUSY_SNAPSHOT`, a 500. Every connection comes from one SQLite data
  source that also sets foreign keys, WAL and the busy timeout. There is no
  pool: opening a SQLite connection is cheap.
- **Authentication.** Authenticated routes accept the SPA's session cookie or a
  bearer token, and both give a `UserPrincipal` holding the `sub` claim. Either
  one failing gives the same JSON 401, which the client turns into a redirect to
  `/login`.
- **Login.** The `auth` slice runs the authorization code flow with PKCE and a
  nonce, as ASP.NET Core's OIDC handler does. `/login` keeps the attempt (state,
  nonce, code verifier, return URL) in a short-lived cookie scoped to the
  callback path. The callback uses the attempt up whether it succeeds or not,
  and then sets the session cookie. The OIDC client is an interface, so the
  slice's tests run the real cookies and redirects against a fake provider. The
  Nimbus client resolves the provider's metadata on first use, so the server
  starts while the provider is down.
- **Sessions.** The session cookie holds the user id and an expiry, encrypted
  and signed by Ktor's `SessionTransportTransformerEncrypt`. The expiry is
  inside the cookie because the cookie's own `Max-Age` is a hint the client can
  ignore. A session lasts an hour; once half of that has passed, the next
  request renews it, matching ASP.NET Core's sliding expiration. The keys come
  from a file, which plays the part of ASP.NET Core's data protection keys.
- **Dev TLS.** In `Development` the server accepts any certificate on outgoing
  HTTPS, for Authelia's self-signed one. It sets both Nimbus's defaults and
  `HttpsURLConnection`'s, process-wide, which is acceptable because the provider
  is the only host the server calls. Nimbus ignores the `HttpsURLConnection`
  defaults.

## Schema and generated code

Migrations are Flyway SQL scripts. Names are snake_case, which is jOOQ's default
convention, so the generated code needs no naming configuration: the table
`tags` becomes `TAGS`, its column `TAGS.USER_ID`, and its record property
`userId`. Ids are declared `UUID`, which jOOQ maps to `java.util.UUID` without a
converter.

At build time Gradle migrates a scratch SQLite file under `build/codegen/` with
Flyway, as the server does at startup, and jOOQ generates Kotlin table and
record classes from it into `build/generated-sources/jooq`. The generated code
is not committed. Gradle regenerates it when a migration changes and skips it
otherwise, so it cannot drift from the schema.

jOOQ can also generate from the scripts alone (`DDLDatabase`): it parses them
and replays them in H2, an in-memory Java database, to read the schema back.
That was tried and rejected. H2 maps `TEXT` to a CLOB it cannot index, so the
index on `tags.user_id` failed, although SQLite accepts it. Working around it
would mean writing SQL that suits two databases, and SQLite-specific features
(`COLLATE NOCASE`, partial indexes, JSON functions) would hit the same problem.

Rows stay raw in the generated code (`TAGS.KIND` is a `String`), and each
slice's codec parses them into the domain. jOOQ could map columns straight to
domain enums, but that would tie generated code to `domain/`.

## Gaps

- Acceptance of a valid bearer token has not been tested end to end. The login
  has, against the dev Authelia with curl, but not through the client or E2E.
- OpenAPI document and Scalar UI. Ktor's options are its OpenAPI generation
  plugin or a library such as Kompendium; neither was evaluated.
- Forwarded headers. The login builds its callback URL from the request, so
  behind a TLS-terminating proxy it would send an `http://` redirect URI until
  Ktor's `XForwardedHeaders` plugin is installed with trusted proxies.
- Request body size limit, static files and the SPA fallback.
- `Money`, dates and the rest of the domain. Owning the schema allows storing
  money as integer cents rather than SQLite's REAL-backed numerics, and dates as
  ISO-8601 text.
- Docker, E2E and CI still build the F# server.

## Findings

- **Fit.** Arrow covers what FsToolkit does, and the `Raise` DSL is closer to
  direct style than computation expressions. Exhaustive `when` over sealed types
  gives the same totality checks as F# matches.
- **Data access.** jOOQ with generated tables matches SqlHydra: typed columns
  and similar query shapes. Owning the schema removed the converter and naming
  config that compatibility needed; codegen is about 60 lines of Gradle.
- **Size.** The Tag slice with its domain and codec is 351 lines against 755 in
  F#. Most of the difference is the per-endpoint OpenAPI configuration the PoC
  lacks and the narrower F# line width, so it is not evidence that Kotlin is
  terser.
- **Auth.** ASP.NET Core provides the cookie and OIDC handlers. Ktor provides
  the encrypted session cookie, but its `oauth` provider is OAuth 2.0 only: it
  does not validate ID tokens or use a nonce, and its default state manager
  generates state without checking it. Nimbus covers the OIDC parts (discovery,
  PKCE, token exchange, ID token validation), and the slice and session code
  around it come to about 300 lines, excluding comments and imports.
- **Losses.** No partial application or pipelines, so composition leans on
  extension functions; enums and sealed types are wordier than unions for
  parsing from strings; `Raise` uses exceptions internally, so a broad `catch
  (Throwable)` inside a handler would swallow raised errors.
- **Build.** First Gradle build, with dependency download, takes about a minute;
  incremental test runs about 10 seconds.
