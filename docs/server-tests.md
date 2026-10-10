# Server Tests

Expecto tests in `server/tests/Budgeteur.Tests/`, run with `just server-test` (`dotnet test server/Budgeteur.slnx`).
What to test and at which layer is decided by [testing-strategy](testing-strategy.md).

## Test host

Endpoint tests run against a real server host with an in-memory test server, built per test from only what the feature
under test needs:

- **In-memory SQLite** with every migration applied, so tests run the real schema and constraints, are hermetic, and
  need no files or network.
- **The slice's production endpoint lists.** The tests route the same endpoint values the production host uses, so a
  route added to a slice is reachable from tests without editing the host.
- **No auth middleware.** Production wraps endpoints in the auth filter, which needs the full OIDC setup. The test host
  skips it and injects a fake user with a `sub` claim instead. A request can name a different user against the same
  database, which the cross-user scoping tests use.

Each test creates its own app, so it starts from an empty database and tests can run in parallel.

On a `5xx` response the host prints the request's server-side log, so a failing test shows the real error rather than an
opaque body.

## Running

`dotnet test` through the Expecto test adapter is the only runner, locally and in CI, and it is the same mechanism IDE
test explorers use. The adapter discovers tests by reflecting over `[<Tests>]` values, so every test list must carry the
attribute. Expecto settings pass through with an `Expecto.` prefix after `--`; `--filter` and `--list-tests` work as
usual.

The test project has no entry point of its own: the test SDK generates one. Do not disable it (`GenerateProgramFile`);
without an entry point the F# assembly is not initialised and every test is discovered as `null`.
