# Kotlin server PoC

An exploration of what the backend would look like written in Kotlin only, in a
functional-first style. It owns its schema and conventions and shares nothing
with the F# server except the HTTP API shape, which the Gleam client depends on.
It covers the infrastructure, the SPA's login and logout, and two slices: `GET
/api/status` and Tag CRUD (`/api/tags`).

## Running

From the dev shell (`nix develop`, which includes JDK 21 and Gradle):

| Command                                | Purpose                     |
| -------------------------------------- | --------------------------- |
| `just kt-test`                         | Run the tests               |
| `just kt-e2e-test`                     | Run the `@kotlin` E2E specs |
| `just kt-format`                       | Format with ktfmt           |
| `just kt-lint`                         | Lint with detekt            |
| `gradle installDist` (in `server-kt/`) | Build `build/install/...`   |

The dev shell also provides JetBrains'
[`kotlin-lsp`](https://github.com/Kotlin/kotlin-lsp), which the repository's
Helix and Crush configs start with `kotlin-lsp --stdio` from `server-kt/`.
nixpkgs only carries the community `kotlin-language-server`, whose bundled
Kotlin 2.1 compiler cannot read the 2.4 standard library, so
`nix/packages/kotlin-lsp` packages JetBrains' prebuilt release, the flake's only
unfree package. JetBrains builds expire about a month after release and old
downloads are deleted, so `just update-kotlin-lsp` moves the pin in
`nix/packages/kotlin-lsp/pin.json` to the latest release; the shell hook warns
once the pinned build is 25 days old. Its bundled analyser must support the
Kotlin version in `gradle/libs.versions.toml`, so bump the two together; the
catalog pins it, so `just update` leaves it alone.

`just kt-e2e-test` runs `docker/docker-compose.e2e-kt.yml`: the F# E2E stack
with this server in place of the F# one, running only the specs tagged
`@kotlin`, those whose endpoints the PoC has. Tag a spec or test when the PoC
gains its endpoints. The tagging page also loads rules, so `GET /api/rules` is a
stub that returns no rules, and the E2E fixtures' `DELETE /api/test/user-data`
is registered in Development only, as in the F# server.

The server reads its settings from environment variables. It reports every
missing or invalid setting at once and exits. On startup it applies pending
migrations.

| Variable                     | Purpose                                                                    |
| ---------------------------- | -------------------------------------------------------------------------- |
| `BUDGETEUR_DATABASE`         | SQLite file path                                                           |
| `OIDC_AUTHORITY`             | The provider's issuer URL                                                  |
| `OIDC_CLIENT_ID`             | The SPA login's client                                                     |
| `OIDC_CLIENT_SECRET`         | Its secret                                                                 |
| `OIDC_CALLBACK_PATH`         | Optional, default `/signin-oidc`                                           |
| `OIDC_VALID_AUDIENCES`       | Optional, comma separated; bearer tokens only                              |
| `OIDC_LOGOUT_URL`            | Optional: the provider's logout page                                       |
| `LOGIN_RETURN_URL`           | Absolute URL a login returns to, e.g. `http://localhost:5173/`             |
| `BUDGETEUR_SESSION_KEY_FILE` | Optional: cookie keys, created if missing, so sessions persist             |
| `SCALAR_CLIENT_ID`           | Optional: in Development, serves the API docs with this client             |
| `BUDGETEUR_WEB_ROOT`         | Optional: the client's build (`client/dist`), served with the SPA fallback |
| `BUDGETEUR_LOG_FILE`         | Optional: also log to this file, rolled at 10 MB, 10 files kept            |
| `PORT`                       | Optional, default 5000                                                     |
| `BUDGETEUR_ENVIRONMENT`      | `Development` trusts the provider's self-signed TLS certificate            |

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
| API docs        | Ktor's routing OpenAPI generation, Scalar from a CDN  |
| Request logging | One wide event per request (Ktor plugin + Logback)    |
| Log format      | JSON lines (logstash-logback-encoder)                 |
| Tests           | kotlin.test (JUnit 5) and Ktor `testApplication`      |
| Versions        | Gradle version catalog, `gradle/libs.versions.toml`   |
| Lint            | detekt 2 (alpha), overrides in `detekt.yml`           |

## Layout

Vertical slices, as in the F# server:

- `feature/<name>/` holds one file per operation: its queries as private
  extension functions on jOOQ's `DSLContext`, and a `Route` extension that
  registers the handler. `TagEndpoints.kt` registers the slice. The file is the
  module, so there are no wrapping `object`s.
- `domain/` is the pure model, `data/` the codecs (extension functions between
  generated records and the domain) and constraint checks, `shared/` the
  infrastructure. Slices depend on these, never on each other, which `just
  check-architecture` enforces.
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
- **Body limits.** Request bodies are capped at 64 KB, as in the F# server.
  Ktor's `RequestBodyLimit` plugin is route scoped, and the closest install
  wins, so the routing root installs the default and an endpoint that needs more
  (the CSV import, once ported) installs its own limit. A body over the limit is
  a JSON 413. ContentNegotiation wraps the limit's exception in a
  `BadRequestException`, so the body parser unwraps it rather than reporting a
  400.
- **Client files.** With `BUDGETEUR_WEB_ROOT` set, the server serves the
  client's build, and `index.html` for any other path without a file extension,
  as ASP.NET Core's `MapFallbackToFile` does, so the SPA's routes load on a
  refresh. A missing file is a 404, and `/api/...` keeps its JSON 404 because
  literal routes outrank the catch-all. Development leaves it unset, as Vite
  serves the client. Vite's hashed bundles under `assets/` are cached for a
  year; everything else, `index.html` above all, is `no-cache`, so a deploy
  shows at once. The F# server leaves caching to the browser's heuristics.
- **Shutdown.** On a stop signal the server waits up to 30 seconds for calls in
  flight, as the F# server's host does. Ktor's `shutdownGracePeriod` is Netty's
  quiet period instead: the workers stop once idle that long, which cuts off a
  call awaiting the database or the provider, and delays every stop by the full
  period. So the app counts calls in flight and holds Ktor's
  `ApplicationStopPreparing` event until none remain. Ktor raises it before
  closing the listening socket, so a call that arrives meanwhile is served and
  waited for too.
- **Log file.** With `BUDGETEUR_LOG_FILE` set, the log also goes to that file,
  rolled at 10 MB with 10 files kept, about 100 MB, as in the F# server. The
  appender is added in code, since `logback.xml` cannot add one conditionally
  without Janino, and both outputs share `JsonLogEncoder`. Logback checks the
  size once a minute by default, which lets a burst overshoot the limit, so the
  check runs once a second.
- **Forwarded headers.** Behind a proxy that terminates TLS, the login builds
  its callback URL from `X-Forwarded-Proto`, as the F# server does (see
  [deployment](../docs/deployment.md#hosting)). The server trusts
  `X-Forwarded-Proto` and `X-Forwarded-For` only from loopback and private IPv4
  peers, and takes their last value, since earlier values come from the client.
  The proxy must pass the Host header through. Ktor's `XForwardedHeaders` plugin
  was rejected: it cannot check the peer, its default takes the client's first
  value, and when the scheme changes it keeps the connection's port, which would
  put `:80` into an `https://` URL. The replacement plugin is about 40 lines.
- **API docs.** With `SCALAR_CLIENT_ID` set, Development serves the OpenAPI
  document at `/openapi/v1.json` and Scalar at `/scalar/v1`, the paths the F#
  server uses and Authelia's `scalar-docs` client expects. Ktor builds the
  document from the routing tree:
  - Each endpoint documents itself with `describe`, next to its handler.
  - Each operation's security requirement comes from the `authenticate` block
    around it, so `/api/status` needs none.
  - Schemas come from the DTOs' kotlinx.serialization descriptors. Ktor marks
    non-null fields required and reads `JsonSchema` annotations for
    descriptions, formats and length bounds.
  - String fields that hold an enum's name carry `@EnumOf`, which lists the
    enum's constants, as the F# `SchemaHint.Enum` does. They stay strings, so
    the request parser can report a bad value alongside the other fields'
    failures.
  - The bearer scheme is documented as OAuth 2.0 with the provider's endpoints,
    read from its discovery document, so Scalar can log in and send the token.
  - Browser redirects, the docs themselves, the rules stub and the test reset
    are hidden.

  Ktor's `describe` API is marked experimental, so the build opts in. The
  rejected alternatives: `ktor-server-openapi` generates static HTML through
  swagger-codegen, Kompendium has had no release since 2024, and
  smiley4/ktor-openapi duplicates what Ktor now provides.

- **Lint.** detekt runs with type resolution (`detektMain`, `detektTest`). It is
  the 2.0 alpha: 1.23.8, the last stable release, embeds the Kotlin 2.0
  compiler, which predates context parameters. `detekt.yml` holds only the
  overrides of detekt's defaults, each with its reason.
- **Dependencies.** `just outdated` lists newer versions (ben-manes versions
  plugin) and `just update` rewrites the version catalog (version-catalog-update
  plugin). Gradle has no audit of its own, and the OWASP plugin needs an NVD API
  key and a large database, so `just audit` writes a CycloneDX SBOM of the
  runtime classpath and scans it with `osv-scanner`, which the dev shell
  provides.

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

- `Money`, dates and the rest of the domain. Owning the schema allows storing
  money as integer cents rather than SQLite's REAL-backed numerics, and dates as
  ISO-8601 text.
- The rules slice, beyond the stub, and every other slice the client uses.
- The production Docker image and CI still build the F# server only.

## Findings

- **Fit.** Arrow covers what FsToolkit does, and the `Raise` DSL is closer to
  direct style than computation expressions. Exhaustive `when` over sealed types
  gives the same totality checks as F# matches.
- **Data access.** jOOQ with generated tables matches SqlHydra: typed columns
  and similar query shapes. Owning the schema removed the converter and naming
  config that compatibility needed; codegen is about 60 lines of Gradle.
- **Size.** The Tag slice with its domain, codec and OpenAPI descriptions is 480
  lines against 755 in F#, so most of the difference is the narrower F# line
  width rather than evidence that Kotlin is terser. The shared OpenAPI code is
  where Kotlin is smaller: the F# server's schema transformers (376 lines) work
  around `System.Text.Json` not understanding F# types, while Ktor's inference
  reads kotlinx.serialization descriptors, so `ApiDocs.kt` (229 lines, including
  the Scalar page) needs only the `EnumOf` hint.
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
