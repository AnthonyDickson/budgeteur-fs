# Server Tests

Expecto tests in `server/tests/Budgeteur.Tests/`. Also see [E2E Tests](e2e-tests.md) for end-to-end Playwright tests.

## Architecture

Uses a `TestApp` module with `HostBuilder` + `TestServer` — the .NET 10 replacement for the deprecated `WebHostBuilder`.

The host contains only what the feature under test needs, declared per-test via a `TestAppConfig`:

- **In-memory SQLite** (shared-cache mode). A "keeper" connection holds the database open for the app's lifetime — each
  query opens its own connection, and the DB would be dropped when the last one closes.
- Routing + Oxpecker middleware.
- **The feature's endpoint lists directly** — the same `GET` / `POST` / `PUT` / `DELETE` groups as `Program.fs`, minus
  the auth middleware. See below.
- A fake `ClaimsPrincipal` with a `sub` claim, so handlers that read the user id work without an OIDC round-trip.

### Why the endpoint lists and not the production wiring

`Program.fs` wraps every feature's endpoint lists with `Auth.requireAuth`, which needs the full OIDC/JWT setup. Tests
build the same lists (e.g. `TestAppConfig.withTransactions`) and skip the middleware entirely. Production adds the auth
filter on top of the same endpoints.

### Fixture lifecycle

`TestApp.create(config)` applies migrations once, then returns a record (`{ Client, CleanDatabase, Dispose }`). Tests
create a fresh app per test (`use app = newApp ()`), so each test starts from an empty database — `CleanDatabase` is
there for tests that reuse one instance.

## Running Tests

```bash
just server-test
# or
dotnet test server/Budgeteur.slnx
```

This is the only way to run them, locally and in CI, and it is the same mechanism IDE test explorers use.
`YoloDev.Expecto.TestSdk` bridges Expecto to VSTest; it discovers tests by reflecting over `[<Tests>]`-attributed values
in the built assembly, so every test list must carry `[<Tests>]`. There is no explicit test program:
`Microsoft.NET.Test.Sdk` sets `OutputType` to `Exe` and adds its own generated entry point, which must not be disabled
(see below).

Useful options:

```bash
dotnet test server/Budgeteur.slnx --list-tests
dotnet test server/Budgeteur.slnx --filter "FullyQualifiedName~Money"
dotnet test server/Budgeteur.slnx -- Expecto.parallel=false   # Expecto settings, `Expecto.`-prefixed
```

### Don't set `GenerateProgramFile` to `false`

`Microsoft.NET.Test.Sdk` sets `OutputType=Exe` and, unless the project declares its own `Program.fs`, adds a generated
entry point. Suppressing that entry point leaves the F# assembly without one, and Expecto's discovery then reads every
`[<Tests>]` value as `null`, failing the run with:

```
Test is null. Assembly may not be initialized. Consider adding an [<EntryPoint>] or making it a library/classlib.
```
