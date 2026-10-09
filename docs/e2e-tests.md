# E2E Tests

Playwright tests running the full stack in Docker Compose with host networking (Authelia → .NET server → Vite client →
Playwright).

```bash
just e2e-test
```

## Setup

### Test isolation (`support/fixtures.ts`)

Every test is independent of the order tests run in and of what runs in parallel. Specs import `test` and `expect` from
`support/fixtures.ts`, not from `@playwright/test`. The fixtures provide two layers of isolation:

- **A user per worker.** The server scopes all data by the `sub` claim, so workers that log in as different users never
  see each other's data, even in a shared database. The worker-scoped `workerStorageState` fixture logs in as
  `e2e-<parallelIndex>` through Authelia and saves the session to `test-results/.auth/<n>.json`. `parallelIndex` is used
  rather than `workerIndex` because a worker that restarts after a failure keeps its `parallelIndex`, so it reuses its
  user and saved session.
- **A reset per test.** The auto `resetUserData` fixture calls `DELETE /api/test/user-data` before each test. This
  dev-only endpoint (registered only in Development) deletes the current user's rows from every table with a `UserId`
  column, discovered from the schema, so new tables are covered without changes. Tests in the same worker, and retries,
  start from no data.

Each test also gets a fresh browser context, so localStorage starts empty.

The users `e2e-0` … `e2e-3` are defined in `authelia/users.yml` (password `dev-password`). `workers` in
`playwright.config.ts` must not exceed the number of users (`userCount` in `support/fixtures.ts`); to raise it, add
users to both.

### Login

`logIn` in `support/fixtures.ts` drives the real OIDC flow once per worker:

1. Navigate to app → SPA 401 → OIDC redirect → Authelia login
2. Fill MUI form using click + pressSequentially
3. Handle consent screen (first login per user only)
4. Wait for redirect back to app, save storage state

### Database

Server uses `/tmp/budgeteur_e2e.db` (ephemeral, cleared on each startup via `rm -f` before `dotnet watch run`). Fresh DB
every run.

## Configuration

`playwright.config.ts`: `fullyParallel: true` with `workers: 4`, `ignoreHTTPSErrors: true` (self-signed certs),
`screenshot: 'on'`, `trace: 'on-first-retry'`. `retries: 1` captures a trace for a failure, and `failOnFlakyTests: true`
fails the run when a test only passes on retry, so flakiness is not hidden.

To check for order or parallelism dependencies, run the suite repeatedly without retries:

```bash
docker compose -f docker/docker-compose.e2e.yml run --rm e2e \
  sh -c "npm install && npx playwright test --retries=0 --repeat-each=4"
```

## Conventions

- Tests must capture screenshots of the test subject.
- Tests must not depend on data from other tests: create what a test needs within it.
