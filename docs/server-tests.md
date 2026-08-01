# Server Tests

xUnit tests in `server/tests/__PROJECT_NAME__.Server.Tests/`. Also see
[E2E Tests](e2e-tests.md) for end-to-end Playwright tests.

## Architecture

Uses a custom `TestApp` fixture with `HostBuilder` + `TestServer` — the .NET 10
replacement for the deprecated `WebHostBuilder`.

The host contains only what endpoints need:

- SQLite (temp file, auto-cleaned)
- Routing + Oxpecker middleware
- `Api.endpoints` directly — **not** the full domain module endpoints

### Why `Api.endpoints` not the domain module endpoints

The domain module's top-level `endpoints` wraps every endpoint with `requireAuth`,
which needs the full OIDC/JWT setup. Tests call `Api.endpoints` directly, bypassing
auth entirely. Production calls the domain module's `endpoints` and gets the auth filter.

### Fixture lifecycle

`TestApp` implements `IDisposable` — creates a temp SQLite file, applies
migrations once, deletes on dispose. `IClassFixture<TestApp>` shares one
instance across all tests in a class. Each test calls `fixture.CleanDatabase()`.

## Test Cases

The example domain (todos) covers the following CRUD test patterns:

| Method | Endpoint               | Asserts                     |
| ------ | ---------------------- | --------------------------- |
| GET    | `/api/todos`           | 200, `[]`                   |
| GET    | `/api/todos` (seeded)  | 200, seeded item present    |
| GET    | `/api/todos/{id}`      | 200, matches seeded item    |
| GET    | `/api/todos/{id}`      | 404                         |
| POST   | `/api/todos`           | 201, matches input          |
| PATCH  | `/api/todos/{id}`      | 200, reflects changes       |
| DELETE | `/api/todos/{id}`      | 204, 404 on re-GET          |
| DELETE | `/api/todos/completed` | 204, incomplete-only remain |
