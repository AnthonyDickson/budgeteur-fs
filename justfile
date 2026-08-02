RUNTIME := env_var_or_default("RUNTIME", "linux-x64")
PUBLISH_DIR := env_var_or_default("PUBLISH_DIR", "server/src/Budgeteur.Server/bin/Release/publish")

# Build the server
server-build:
	dotnet build server/src/Budgeteur.Server/Budgeteur.Server.fsproj

# Run the server (auto-applies DB migrations)
server-watch:
	ASPNETCORE_ENVIRONMENT=Development dotnet watch run --project server/src/Budgeteur.Server --no-hot-reload

# xUnit tests
server-test:
	dotnet test server/tests/Budgeteur.Server.Tests

# npm install
client-install-deps:
	cd client && npm install

# gleeunit tests
client-test:
	cd client && gleam test

# Start the client dev server (Vite + Gleam watch)
client-watch:
	cd client && npx vite

# Production client bundle
client-build:
	cd client && npx vite build

# Copy client dist into server wwwroot/
copy-client-dist: client-build
	mkdir -p server/src/Budgeteur.Server/wwwroot
	cp -r client/dist/* server/src/Budgeteur.Server/wwwroot/

# Single-file publish (builds client, copies assets, publishes server)
publish: copy-client-dist
	dotnet publish server/src/Budgeteur.Server/Budgeteur.Server.fsproj \
		-c Release -r {{RUNTIME}} -o {{PUBLISH_DIR}} \
		-p:PublishTrimmed=true -p:TrimMode=partial

# Playwright E2E tests in Docker
e2e-test:
	docker compose -f docker-compose.e2e.yml up --abort-on-container-exit --exit-code-from e2e --remove-orphans

# Format with fantomas + gleam format
format:
	dprint fmt
	gleam format
	cd server && dotnet fantomas .

# Lint with fsharplint
lint:
	cd server && dotnet fsharplint lint Budgeteur.slnx

audit:
	cd client && npm audit
	cd server && dotnet list package --vulnerable

outdated:
	cd client && gleam deps outdated
	cd client && npm outdated
	cd server && dotnet list package --outdated

# ── Database ──────────────────────────────────────────────────────────────

# Scaffold a new migration file
db-migration name:
	#!/usr/bin/env bash
	set -euo pipefail
	dir="server/src/Budgeteur.Server/migrations"
	count=$(ls "$dir"/*.sql 2>/dev/null | wc -l)
	num=$(printf "%03d" $((count + 1)))
	file="$dir/${num}_{{name}}.sql"
	echo "-- {{name}}" > "$file"
	echo "Created migration: migrations/$(basename "$file")"

# Apply pending migrations (standalone script)
db-migrate:
	cd server && dotnet fsi scripts/migrate.fsx

# Regenerate Db.fs types from live DB (SqlHydra)
db-generate:
	cd server && dotnet sqlhydra sqlite --project src/Budgeteur.Server/Budgeteur.Server.fsproj

# db-migrate + db-generate (full schema update)
db-update: db-migrate db-generate

# Delete DB, re-apply all migrations, regenerate
db-reset:
	rm -f server/src/Budgeteur.Server/app.sqlite3
	just db-update
