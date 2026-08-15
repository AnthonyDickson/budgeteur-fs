# Server Tests

Expecto tests in `server/tests/Budgeteur.Tests/`. Also see
[E2E Tests](e2e-tests.md) for end-to-end Playwright tests.

## Architecture

Uses a `TestApp` module with `HostBuilder` + `TestServer` — the .NET 10
replacement for the deprecated `WebHostBuilder`.

The host contains only what the feature under test needs, declared per-test via
a `TestAppConfig`:

- **In-memory SQLite** (shared-cache mode). A "keeper" connection holds the
  database open for the app's lifetime — each query opens its own connection,
  and the DB would be dropped when the last one closes.
- Routing + Oxpecker middleware.
- **The feature's `Api.endpoints` directly** — e.g. `Transaction.Api.endpoints`,
  not the full `Program.fs` endpoint list. See below.
- A fake `ClaimsPrincipal` with a `sub` claim, so handlers that read the user id
  work without an OIDC round-trip.

### Why feature `Api.endpoints` and not the production wiring

`Program.fs` wraps every feature endpoint with `Auth.requireAuth`, which needs
the full OIDC/JWT setup. Tests call the feature's `Api.endpoints` directly,
bypassing auth entirely. Production adds the auth filter on top of the same
endpoints.

### Fixture lifecycle

`TestApp.create(config)` applies migrations once, then returns a record
(`{ Client, CleanDatabase, Dispose }`). Tests create a fresh app per test
(`use app = newApp ()`), so each test starts from an empty database —
`CleanDatabase` is there for tests that reuse one instance.

## Running Tests

```bash
just server-test
# or
dotnet run --project server/tests/Budgeteur.Tests
```
