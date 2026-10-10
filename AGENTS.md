# AGENTS.md

> This file should follow the [AGENTS.md standard](https://agents.md/).

## Communication Style

When communicating with the user directly or writing documentation prefer a dry, direct and technical tone. Try to be
clear and concise. Avoid words like: seams, lands, wire (e.g. wire format).

## Project Overview

A self-hosted personal finance tracker: transactions, tags, tagging rules, a balance sheet, and a dashboard. The roadmap
is in [TODO.md](TODO.md).

- **Backend** (`server/`) — F# on .NET 10 with Oxpecker, SQLite, OIDC auth, and OpenAPI. Organised as vertical slices.
- **Frontend** (`client/`) — Gleam/Lustre SPA with Tailwind CSS v4 and Vite. MVU with an effect system that keeps
  `update` pure.

The `Transaction` slice (server) and transaction page (client) are the reference implementations of the patterns in
[docs/architecture.md](docs/architecture.md).

## Documentation

| Doc                                             | Covers                                                         |
| ----------------------------------------------- | -------------------------------------------------------------- |
| [architecture.md](docs/architecture.md)         | Requirements, server and client design, cross-cutting rules    |
| [database.md](docs/database.md)                 | Migrations, generated code, schema conventions, workflows      |
| [dates.md](docs/dates.md)                       | Calendar dates vs instants                                     |
| [openapi.md](docs/openapi.md)                   | How the OpenAPI document describes F# types                    |
| [testing-strategy.md](docs/testing-strategy.md) | What to test, at which layer, and how much                     |
| [server-tests.md](docs/server-tests.md)         | Server test host design                                        |
| [e2e-tests.md](docs/e2e-tests.md)               | E2E isolation and conventions                                  |
| [deployment.md](docs/deployment.md)             | Publishing, Docker, production database, static assets         |
| [prod-oidc-setup.md](docs/prod-oidc-setup.md)   | Configuring an OIDC provider for production                    |
| [balance-sheet.md](docs/balance-sheet.md)       | Balance sheet design brief: decisions, rationale, glossary     |
| [dashboard.md](docs/dashboard.md)               | Dashboard and income statement design brief                    |
| [fp-showcase.md](docs/fp-showcase.md)           | Tour of the codebase's functional programming ideas (tutorial) |

Docs record requirements, design decisions and their rationale, and conventions that the code cannot express. Keep them
at a level that survives refactoring: name concepts and directories, not functions, and avoid code snippets.
Implementation detail belongs in the code and its comments. When a decision changes, update the doc in the same change.

## Essential Commands

| Command                    | Purpose                                               |
| -------------------------- | ----------------------------------------------------- |
| `just server-build`        | Build the server                                      |
| `just server-watch`        | Run the server at :5000 (auto-applies DB migrations)  |
| `just server-test`         | Server Expecto tests (via the test adapter)           |
| `just client-install-deps` | Install npm packages (run once before any client cmd) |
| `just client-watch`        | Client dev server at :5173 (Vite + Gleam watch)       |
| `just client-test`         | Client gleeunit tests                                 |
| `just e2e-test`            | Playwright E2E tests in Docker                        |
| `just db-update`           | Apply migrations and regenerate `Db.fs`               |
| `just format`              | Format markdown (dprint) + Gleam + F#                 |
| `just lint`                | Lint F# with fsharplint + [custom lints](./justfile)  |

Dev environment via Nix: `nix develop` (or `direnv allow`). The justfile is the source of truth for the full target
list. Quick start: `docker compose -f docker/docker-compose.yml up` (log in with `dev`/`dev-password`), or natively
`just server-watch` plus `just client-watch`. See [README.md](README.md).

## Design Principles

Broadly:

- Make the right thing easy: architecture and design should push developers toward correct, clear, concise code.
- Prefer simple, direct code and systemic fixes over workarounds. When code is convoluted, ask whether the design is
  wrong and fix at the right level, so code churn reduces accidental complexity.
- Only add abstractions when there is a clear advantage; avoid over-engineering.

More specifically:

- **Functional programming** — push I/O to the edges, make illegal states unrepresentable, functions as the default
  abstraction, programs as data (the effect system).
- **Domain-Driven Design** (Wlaschin, _Domain Modeling Made Functional_) — start from the pure domain; everything else
  follows. Focus on _strategic_ DDD (ubiquitous language, bounded contexts) over tactical DDD.
- **Vertical Slice Architecture** — group code by feature/workflow; some duplication is acceptable, especially when
  establishing new features or when code changes for different reasons; limit blast radius by minimising coupling and
  maximising coherence.
- **Client MVU/TEA** — two-tier shell + page modules; avoid stateful components (nested TEA).
- **Testing** — prefer tests where confidence is low (multi-step/stateful logic, validation, save/error/retry), not
  trivial mappings. Each feature needs at least one test driving the happy path through the real event flow. Only E2E
  tests exercise client-server interactions. Minimise maintenance while maximising confidence. See
  [docs/testing-strategy.md](docs/testing-strategy.md).

## Code Review

Reviews push the codebase toward the design principles and are an opportunity to simplify and reduce code. Findings must
be evidence based, reference the offending code, and state severity, likelihood, confidence, recommended fix(es), and
trade-offs.

## Rules

Each rule is explained in the linked doc.

- **Slices and the kernel** — server features live in `Feature/<Name>/`, one file per HTTP operation. `Domain/`,
  `Data/`, and `Shared/` form the shared kernel. Features depend on the kernel, never the reverse, and slices never
  import each other (enforced by `just lint`). See [architecture](docs/architecture.md#dependency-rules).
- **User scoping** — every query filters by the user id from the `sub` claim. A slice that skips this leaks data across
  users.
- **Errors** — handlers return `Result<unit, DomainError>`; no exceptions escape them. Database constraints are checked
  before writes so violations return `400`. See [architecture](docs/architecture.md#errors).
- **Money** — amounts are the refined `Money` type, rounded to cents away from zero, serialised as JSON strings, and
  aggregated on the server in `decimal`, never in SQL or on the client. See [architecture](docs/architecture.md#money).
- **Dates** — user and bank-statement days are calendar dates; server-recorded events are UTC instants. See
  [docs/dates.md](docs/dates.md).
- **Migrations** — never modify a released migration; `Data/Db.fs` is generated, committed, and never hand-edited. See
  [docs/database.md](docs/database.md).
- **No cached server data on the client** — localStorage holds user preferences only.
- **E2E selectors** — use `data-testid` attributes; add them when introducing interactive elements.
- **Secrets** — never log secrets or tokens; source them from environment variables or config, not source control.

## Code Style

- **Formatting** (fantomas via `.editorconfig`): Stroustrup bracket style; spaces before parameters/colons/invocations;
  space after commas and semicolons, not before.
- **Naming**: PascalCase modules matching filenames; camelCase functions; PascalCase types (records/DUs);
  `[<RequireQualifiedAccess>]` on modules exposing a type alias.

## Verification & CI

CI runs server tests, client tests, E2E tests, Gleam/F#/markdown format checks, and a check that `Db.fs` matches the
migrations. Before finishing work, run the relevant tests plus `just lint` and `just format`; after schema changes run
`just db-update` and commit the regenerated `Db.fs`. When a CI check fails, its log message names the local command to
reproduce it.

## Gotchas

- **Compilation order**: F# compiles server files in the order listed in `.fsproj` — insert new `.fs` files before files
  that depend on them.
- **SqlHydra query parameters**: function parameters can't be captured directly in query expressions. Bind them to local
  `let` values first.
- **Central Package Management**: versions live in `Directory.Packages.props`; project files use bare `<PackageReference
  Include="..." />`.
- **Request body limit**: Kestrel caps request bodies at 64 KB — relevant for the CSV import.
