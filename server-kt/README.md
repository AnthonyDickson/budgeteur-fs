# Kotlin server PoC

An exploration of what the backend would look like written in Kotlin only, in a
functional-first style. It owns its schema and conventions and shares nothing
with the F# server except the HTTP API shape, which the Gleam client depends on.
It covers the infrastructure and two slices: `GET /api/status` and Tag CRUD
(`/api/tags`).

## Running

From the dev shell (`nix develop`, which includes JDK 21 and Gradle):

| Command                                | Purpose                   |
| -------------------------------------- | ------------------------- |
| `just kt-test`                         | Run the tests             |
| `gradle installDist` (in `server-kt/`) | Build `build/install/...` |

The server reads `BUDGETEUR_DATABASE` (SQLite file path), `OIDC_AUTHORITY`,
optional `OIDC_VALID_AUDIENCES` (comma separated), `PORT` (default 5000) and
`BUDGETEUR_ENVIRONMENT`. It reports every missing or invalid setting at once and
exits. On startup it applies pending migrations.

## Stack

| Concern         | Choice                                                |
| --------------- | ----------------------------------------------------- |
| HTTP            | Ktor 3 on Netty                                       |
| Errors          | Arrow `Either` and the `Raise` DSL (`either { }`)     |
| Validation      | Arrow `zipOrAccumulate`                               |
| JSON            | kotlinx.serialization                                 |
| Database        | SQLite through jOOQ, table code generated from schema |
| Migrations      | Flyway, SQL scripts in `src/main/resources/db/`       |
| Auth            | OIDC JWT bearer (`ktor-server-auth-jwt`)              |
| Request logging | One wide event per request (Ktor plugin + Logback)    |
| Tests           | kotlin.test (JUnit 5) and Ktor `testApplication`      |

## Layout

Vertical slices, as in the F# server:

- `feature/<name>/` holds one file per operation. Each is an `object` with its
  queries as private functions over a jOOQ `DSLContext` and a `Route` extension
  that registers the handler. `TagEndpoints.kt` registers the slice.
- `domain/` is the pure model, `data/` the codecs and constraint checks,
  `shared/` the infrastructure. Slices depend on these, never on each other.
- `App.kt` builds the application from a `Dependencies` value (database, clock,
  auth setup); `Main.kt` is the imperative shell that reads config, migrates and
  starts serving. The test host builds its own `Dependencies` with an in-memory
  database and a fake auth provider driven by an `X-Test-User` header.

## Design notes

- **Handlers.** A handler is a block in Arrow's `Raise<DomainError>` context:
  `bind()` unwraps an `Either` and `raise` fails. `Endpoint.handle` writes every
  failure, and any exception, as a JSON error, so no exception escapes a
  handler. jOOQ wraps driver exceptions, so it looks through the causes to tell
  a constraint violation (409) from other database errors (500).
- **Validation.** Domain constructors fail with a plain `String`. The request
  parser accumulates every field's failure and raises one `ValidationFailed`
  with one line per failure.
- **Refined types.** `TagName` is a `@JvmInline value class` with a private
  constructor, so the only way to build one from input is `TagName.create`.
  Payload-free choices (`TagColor`, `TagKind`) are enums; choices with data are
  sealed interfaces (`DomainError`), matched exhaustively with `when`.
- **Constraint checks.** Handlers check database constraints before writing, as
  `Either<ConstraintError, Unit>` values, and `requireAll` turns the failures
  into one `ValidationFailed`.

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

- Cookie/OIDC login and logout for the SPA, and the dev-only TLS bypass for the
  provider's self-signed certificate. Acceptance of a valid bearer token has not
  been tested end to end.
- OpenAPI document and Scalar UI. Ktor's options are its OpenAPI generation
  plugin or a library such as Kompendium; neither was evaluated.
- Request body size limit, forwarded headers, data protection, static files and
  the SPA fallback.
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
- **Size.** The Tag slice with its domain and codec is 374 lines against 755 in
  F#. Most of the difference is the per-endpoint OpenAPI configuration the PoC
  lacks and the narrower F# line width, so it is not evidence that Kotlin is
  terser.
- **Losses.** No partial application or pipelines, so composition leans on
  extension functions; enums and sealed types are wordier than unions for
  parsing from strings; `Raise` uses exceptions internally, so a broad `catch
  (Throwable)` inside a handler would swallow raised errors.
- **Build.** First Gradle build, with dependency download, takes about a minute;
  incremental test runs about 10 seconds.
