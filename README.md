[![CI](https://github.com/AnthonyDickson/budgeteur-fs/actions/workflows/ci.yml/badge.svg)](https://github.com/AnthonyDickson/budgeteur-fs/actions/workflows/ci.yml)
[![E2E Tests](https://github.com/AnthonyDickson/budgeteur-fs/actions/workflows/e2e.yml/badge.svg)](https://github.com/AnthonyDickson/budgeteur-fs/actions/workflows/e2e.yml)

# Budgeteur

## About

Budgeteur is a budgeting and personal finance web-app.

This app aims to provide two services:

- Budgeting: Recording your income and expenses, and tracking savings targets.
- Personal Finance: Keeping track of your net worth.

This application is intended to be self-hosted on a home server.

## Why?

I started budgeting with a mobile app, but I quickly ran into three main issues:

1. it required me to enter my income/expenses manually,
1. it only worked on my phone,
1. and it didn't help me with tracking my net worth.

I have tried using a spreadsheet to track my net worth, however I then ran into issues where editing this spreadsheet
from multiple devices lead to old copies overwriting the copy in my cloud storage.

Budgeteur is my attempt at a single, cross-platform application for tracking my budget and net worth. One helpful
feature of Budgeteur is that you can import transactions and track your account balances from CSV files. These CSV can
be exported from the internet banking websites for New Zealand bank accounts (ASB and Kiwibank). This reduces the amount
manual data entry significantly, making it easier to maintain the habit of tracking your budget even when life gets
busy.

## Getting Started

Using Docker:

```bash
docker compose -f docker/docker-compose.yml up
```

Starts three services:

| Service  | Port | Notes                                           |
| -------- | ---- | ----------------------------------------------- |
| Authelia | 9091 | Dev OIDC provider (user `dev` / `dev-password`) |
| Server   | 5000 | .NET backend with API docs at `/scalar/v1`      |
| Client   | 5173 | Vite dev server with hot reload                 |

Open `http://localhost:5173` and log in with `dev` / `dev-password`.

Or natively:

```bash
just server-build    # Build the server
just server-watch    # Run at :5000 (auto-creates SQLite DB + applies migrations)

# In a second terminal:
just client-install-deps # First time only
just client-watch        # Vite dev server at :5173
```

See the [Justfile](./justfile) for all targets.

## How It Works

Budgetetur is a full-stack web app with an F#/Oxpecker backend (SQLite + OIDC auth + OpenAPI) and a Gleam/Lustre SPA
frontend (Tailwind CSS v4, Vite).

- **Backend** — Oxpecker on .NET 10 with OIDC auth (cookie + JWT bearer). Endpoints live in vertical slices (one folder
  per domain). SQLite with DbUp migrations and SqlHydra type-safe queries. OpenAPI spec at `/openapi/v1.json` and
  interactive docs at `/scalar/v1` (dev only). See [Database](docs/database.md).
- **Frontend** — Gleam/Lustre SPA with nested MVU. A custom `Effect` type keeps `update` pure — all I/O (HTTP,
  localStorage, navigation) runs through one interpreter. See [Architecture](docs/architecture.md).
- **Auth** — Dev OIDC via Authelia (`docker compose -f docker/docker-compose.yml up -d`, test user
  `dev`/`dev-password`). See [Production OIDC Setup](docs/prod-oidc-setup.md).
- **Testing** — Expecto server tests, gleeunit client unit tests, Playwright E2E tests via Docker Compose. See
  `docs/server-tests.md`, `docs/architecture.md#client-tests`, and `docs/e2e-tests.md`.
- **Deployment** — Single-file publish (`just publish`) or Docker (`docker build -f docker/Dockerfile .` + `docker
  compose -f docker/docker-compose.prod.yml up -d`). Intended to be hosted behind a reverse proxy. See
  [Deployment](docs/deployment.md).

## Dev Environment

Nix flake provides the toolchain (see `flake.nix`); F# dotnet tools are restored from `server/dotnet-tools.json`. NuGet
Central Package Management — versions in `Directory.Packages.props`.

## Docs

- [Architecture](docs/architecture.md)
- [Functional Programming in Practice](docs/fp-showcase.md)
- [Database](docs/database.md)
- [Deployment](docs/deployment.md)
- [Production OIDC Setup](docs/prod-oidc-setup.md)
- [Server Tests](docs/server-tests.md)
- [E2E Tests](docs/e2e-tests.md)
