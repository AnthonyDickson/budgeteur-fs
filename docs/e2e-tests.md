# E2E Tests

Playwright tests running the full stack in Docker Compose with host networking
(Authelia → .NET server → Vite client → Playwright).

```bash
just e2e-test
```

## Setup

### Global Auth (`global-setup.ts`)

Logs in once via Authelia before the test suite, saves `auth.json`:

1. Navigate to app → SPA 401 → OIDC redirect → Authelia login
2. Fill MUI form (`dev` / `dev-password`) using click + pressSequentially
3. Handle consent screen (first login only)
4. Wait for redirect back to app, save storage state

### Database

Server uses `/tmp/budgeteur_e2e.db` (ephemeral, cleared on each startup via
`rm -f` before `dotnet watch run`). Fresh DB every run.

### Server state reset

Each test gets a fresh browser context, so localStorage starts empty, but the
database persists across the run. The tagging spec's `beforeEach` calls
`DELETE /api/test/tagging`, a dev-only endpoint (registered only in
Development) that clears the current user's tags and rules.

## Configuration

`playwright.config.ts`: `ignoreHTTPSErrors: true` (self-signed certs),
`screenshot: 'on'`, `trace: 'on-first-retry'`, auth via `storageState`.

## Conventions

- Tests must capture screenshots of the test subject.
