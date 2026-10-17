# TODO

## Roadmap

- [x] Transaction CRUD
- [x] Tag CRUD
- [x] Tagging rules CRUD
- [x] Balances (Assets, Liabilities) CRUD
- [x] Dashboard MVP
- [x] Auto-tagging
- [x] CSV Imports
- [x] Quick-tagging
- [x] Reports: balance sheets and income statements per period
- [x] Full dashboard w/ charts
- [x] Transaction search
- [x] Mobile support
- [ ] Release
- [ ] Smart auto-tagging via local embeddings + logistic regression/SVM

## Current Tasks

- Release 1.0:
  - Fix the backslash and indentation in validation messages:
    > Could not record value: Validation failed: The as-of date 2026-10-19 is in
    > the future. \ The latest accepted date is 2026-10-18.

    F# triple-quoted strings do not process `\` line continuations.
    - Server: rewrite the three messages as `$"..."` strings with format
      specifiers (`{asOf:O}`): `Domain/AsOfDate.fs`, `Domain/CloseDate.fs`, and
      the out of order error in `Feature/Import/Statement.fs`.
    - Server: drop the `Validation failed:` prefix from `joinValidationErrors`
      in `Shared/DomainError.fs`; the response's `error` field already says
      "Validation Error". Update any tests that assert on it.
    - Lint (optional): a justfile check that fails on a line ending in `\`
      inside a `"""` string.
  - Focus the first field when a form modal opens. `showModal()` focuses the
    first `autofocus` element, else the first focusable one, which is a help
    button in these forms.
    - Client: add `autofocus` to the main field of the value, balance, and close
      modals. `value_form.view` and `balance_form.view` take an `autofocus:
      Bool`, since the item and account create forms embed them and autofocus
      their name field.
    - Client: add `autofocus` to the first field of the transaction and import
      modals, which only get it by being first today.
    - E2E: the record value, record balance, and close modals focus their main
      field.
  - Accept commas in amounts, e.g. "1,234.56".
    - Client: `money.parse_decimal` removes commas, which covers the value,
      balance, transaction, and search amount fields. Lenient: "1,2,3" parses
      as 123. Optionally strip a leading `$` too, for pasted amounts.
    - Tests: gleeunit cases for `parse_decimal`.
  - Show the page name in the browser title, e.g. "Transactions | Budgeteur".
    - Client: `app.gleam` sets the title on `UrlChanged`, from a title per route
      that reuses the nav labels (via `route.section`). Details pages use their
      section, "Balance sheet | Budgeteur"; the not found and signed out pages
      get their own.
  - Log out fully. `/logout` only clears the app cookie, and the provider
    session signs the user straight back in. Authelia 4.39 has no OIDC
    `end_session_endpoint` (authelia/authelia#11660, targeting 4.40), but its
    portal `/logout?rd=<url>` ends the session. It follows `rd` only for https
    URLs within its session cookie domains; otherwise the user stays on its
    login page.
    - Server: optional `Auth:ProviderLogoutUrl` setting. `/logout` clears the
      cookie, then redirects there, or to `/signed-out` when unset. Keep the
      comment on switching to OIDC sign-out once Authelia ships it.
    - Client: `/signed-out` route with a "Signed out" message and a link to
      `/login`; no nav and no API calls (a 401 would redirect to the provider).
      A 401 still redirects to `/login`, so an expired app session with a live
      provider session signs back in without a click.
    - Client: "Log out" link in the header nav and the narrow-screen menu, with
      a `data-testid`.
    - Config: dev and E2E point `ProviderLogoutUrl` at
      `https://127.0.0.1:9091/logout` (`rd` is ignored over http).
    - E2E: logging out lands on the Authelia login page, and opening the app
      asks for a login again; `/signed-out` renders its sign-in link.
    - Docs: architecture.md (auth) and prod-oidc-setup.md (logout), including
      the `rd` example
      `https://auth.example.com/logout?rd=https://budget.example.com/signed-out`
      and its https and cookie domain requirements.
  - Return to the page you were on after logging in. Login always returns to a
    fixed URL (`loginReturnUrl` in Program.fs), so an expired session lands on
    the dashboard.
    - Client: on a 401, redirect to `/login?returnUrl=<current path and query>`.
    - Server: resolve the path against `Login:ReturnUrl`, which is absolute (in
      dev it is the Vite server on another port).
    - Server: `/login` accepts `returnUrl` only when it is a local path (starts
      with a single `/`, not `//` or `/\`), falling back to the default, so it
      cannot be used as an open redirect. Use the same check when already
      authenticated, instead of always redirecting to `/`.
    - Tests: server tests for the local path check; E2E deep link survives a
      login.
  - Add changelog, for now it just say 1.0 initial release and should follow
    https://keepachangelog.com/en/1.1.0/
  - Rewrite the README for users. Model it on the budgeteur-rs README: setup
    steps and usage in the README itself. Do not link the design briefs; they
    are for developers. Write it last, so it describes the released behaviour.
    - Keep: badges, About, and Why. Add a dashboard screenshot.
    - Getting Started: Docker Compose from
      `docker/docker-compose.prod.example.yml`, the OIDC provider it needs (the
      settings to fill in and the client to register, with Authelia as the
      example), the persistent `/data` volume (database and sign-in keys), and a
      caution to serve it over HTTPS behind a reverse proxy.
    - First-time usage: sign in through the provider; signing out (ends the
      provider session too when `ProviderLogoutUrl` is set).
    - Using Budgeteur, in workflow order: import CSV statements (Kiwibank and
      ASB card; duplicates are skipped, transfers between your accounts are
      marked, statement balances are recorded), tags and rules, quick tagging,
      the balance sheet (items and accounts, recording values, closing lines,
      line history), reports, the dashboard, and transaction search.
    - Dates: days follow the browser's local date; dates later than tomorrow
      (UTC) are rejected.
    - Backups and upgrades: back up the `/data` volume; upgrading keeps sessions
      when the keys are on it.
    - Development: move the current Getting Started, How It Works, Dev
      Environment, and Docs sections to the end under one heading (or to a
      separate doc linked from there).

## Backlog

- Except for transaction table and data entry, consider rounding to the nearest
  dollar
- For modals, ensure that focus is returned to the element focused before
  opening the modal. This is needed due to the custom dialog wrapped deleting
  the wrapping DOM element instead of calling `.close()` on the native dialog.
- Scalar docs: refresh tokens for Authelia
- Edit a balance history entry: an Edit button per entry that opens the record
  modal pre-filled with its amount and date. Reverses decision 9 in
  docs/reports.md ("there is no edit action"). Changing the date would add an
  entry rather than move it, so keep the date read-only when editing, or delete
  and record in one transaction on the server.
- Display dates in a friendlier format, e.g. "18 Oct 2026": a `date.display`
  through `Intl.DateTimeFormat("en-NZ")` for the text call sites, keeping ISO
  `date.format` for the API, date inputs, and test ids. Server messages and E2E
  assertions on visible dates would change too.
