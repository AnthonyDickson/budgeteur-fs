# E2E Tests

Playwright tests in `tests/e2e/`, run against the full stack in Docker Compose (Authelia, server, Vite, Playwright) with
`just e2e-test`. E2E is the only layer that exercises the client and server together; see
[testing-strategy](testing-strategy.md) for what belongs here.

## Isolation

Every test is independent of the order tests run in and of what runs in parallel. Specs import `test` and `expect` from
the suite's fixtures module, not from `@playwright/test`, to get two layers of isolation:

- **A user per worker.** The server scopes all data by user, so workers logged in as different users never see each
  other's data in the shared database. Each worker logs in once through the real OIDC flow and reuses the session.
- **A reset per test.** Before each test, a development-only endpoint deletes the current user's rows from every table
  with a user column. Tables are discovered from the schema, so new tables are covered without changes. Tests in the
  same worker, and retries, start from no data.

Each test also gets a fresh browser context, so localStorage starts empty. The server database is recreated on each run.

The E2E users are defined in `authelia/users.yml`. The worker count must not exceed the number of users; to raise it,
add users to both the Authelia config and the fixtures.

## Flakiness

A failing test is retried once to capture a trace, and the run fails if any test passes only on retry, so flakiness is
reported rather than hidden. To check for order or parallelism dependencies, run the suite repeatedly without retries:

```bash
docker compose -f docker/docker-compose.e2e.yml run --rm e2e \
  sh -c "npm install && npx playwright test --retries=0 --repeat-each=4"
```

## Conventions

- Tests capture screenshots of the test subject.
- Tests create the data they need; they never depend on data from other tests.
- Selectors use `data-testid` attributes. Add them to page views when introducing interactive elements.
