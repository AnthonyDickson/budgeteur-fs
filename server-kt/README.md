# Kotlin server PoC

An exploratory port of the server to Kotlin in a functional-first style. It
covers the infrastructure and two slices: `GET /api/status` and Tag CRUD
(`/api/tags`). It is not a replacement yet; the gaps are listed below.

## Running

From the dev shell (`nix develop`, which now includes JDK 21 and Gradle):

| Command                                | Purpose                   |
| -------------------------------------- | ------------------------- |
| `just kt-test`                         | Run the tests             |
| `gradle installDist` (in `server-kt/`) | Build `build/install/...` |

The server reads `BUDGETEUR_DATABASE` (SQLite file path), `OIDC_AUTHORITY`,
optional `OIDC_VALID_AUDIENCES` (comma separated), `PORT` (default 5000) and
`BUDGETEUR_ENVIRONMENT`. Missing or invalid settings are all reported at once
and the server exits.

## Stack

| Concern         | F# server                        | Kotlin PoC                                     |
| --------------- | -------------------------------- | ---------------------------------------------- |
| HTTP            | Oxpecker on ASP.NET Core         | Ktor 3 on Netty                                |
| Errors          | `Result` + `taskResult`          | Arrow `Either` + `Raise` DSL (`either { }`)    |
| Validation      | FsToolkit applicative            | Arrow `zipOrAccumulate`                        |
| JSON            | Thoth auto coders                | kotlinx.serialization                          |
| Data access     | SqlHydra (generated from schema) | JDBC with small helpers, hand-written SQL      |
| Migrations      | DbUp                             | DbUp-compatible runner over the same SQL files |
| Auth            | Cookie + OIDC, JWT bearer        | JWT bearer only                                |
| Request logging | Wide event per request (Serilog) | Wide event per request (Ktor plugin + Logback) |
| Tests           | Expecto + TestServer             | kotlin.test (JUnit 5) + Ktor `testApplication` |

## Design notes

- **Same database.** Both servers read the migration scripts in
  `server/src/Budgeteur/Data/Migrations` (Gradle copies them into the jar) and
  share DbUp's `SchemaVersions` journal and script names. GUIDs are stored as
  uppercase TEXT, as Microsoft.Data.Sqlite writes them. A copy of the dev
  database opened by the Kotlin server applied no migrations and decoded the
  existing tags.
- **Slices.** Same layout as the F# server: `feature/<name>/` with one file per
  operation, and `domain/`, `data/` and `shared/` as the shared modules. Each
  operation is an `object` with its SQL as private functions over a `Connection`
  and a `Route` extension that registers the handler.
- **Handlers.** A handler is a block in Arrow's `Raise<DomainError>` context, so
  `bind()` and `raise` read like `let!` and `return! Error` in `taskResult`.
  `Endpoint.handle` maps the outcome, and any exception, to the response.
- **Validation without the exception.** Domain constructors fail with a plain
  `String`, so the request parser accumulates field errors as strings and wraps
  them in one `ValidationFailed`. This removes the case that
  `DomainError.joinValidationErrors` in the F# server has to `failwith` on.
- **Refined types.** `TagName` is a `@JvmInline value class` with a private
  constructor, the equivalent of a single-case union with a private case.
  Payload-free unions (`TagColor`, `TagKind`) are enums; unions with data are
  sealed interfaces (`DomainError`).
- **Dependencies as data.** `Dependencies` holds the database, clock and auth
  setup. `Main.kt` builds the real one; the test host swaps in an in-memory
  database and a header-driven fake auth provider.

## Gaps

- Cookie/OIDC login and logout for the SPA, and the dev-only TLS bypass for the
  provider's self-signed certificate. Bearer tokens are implemented; acceptance
  of a valid token has not been tested end to end.
- OpenAPI document and Scalar UI. Ktor's options are its OpenAPI generation
  plugin or a library such as Kompendium; neither was evaluated.
- Request body size limit, forwarded headers, data protection, static files and
  the SPA fallback.
- Type-checked SQL. SqlHydra generates types from the schema; the closest JVM
  match is jOOQ code generation from the migration scripts (its DDL database),
  which was not tried. Hand-written SQL is the largest step down from the F#
  server.
- `Money`, dates and the rest of the domain.

## Findings

- **Fit.** Arrow covers what FsToolkit does, and the `Raise` DSL is closer to
  direct style than computation expressions. Exhaustive `when` over sealed types
  gives the same totality checks as F# matches.
- **Size.** The Tag slice with its domain and codec is 372 lines against 755 in
  F#. Most of the difference is the per-endpoint OpenAPI configuration the PoC
  lacks and the narrower F# line width, so it is not evidence that Kotlin is
  terser.
- **Losses.** No type-checked queries without adding jOOQ; no partial
  application or pipelines, so composition leans on extension functions; Kotlin
  enums and sealed types are wordier than unions for parsing from strings;
  `Raise` relies on exceptions internally, so a broad `catch (Throwable)` inside
  a handler would swallow raised errors.
- **Build.** First Gradle build, with dependency download, takes about a minute;
  incremental test runs about 10 seconds.
