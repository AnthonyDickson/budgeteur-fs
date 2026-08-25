RUNTIME := env_var_or_default("RUNTIME", "linux-x64")
PUBLISH_DIR := env_var_or_default("PUBLISH_DIR", "server/src/Budgeteur/bin/Release/publish")
VERSION := env_var_or_default("VERSION", "0.0.0-local")
GIT_SHA := env_var_or_default("GIT_SHA", "")

# Build the server
server-build:
	dotnet build server/src/Budgeteur/Budgeteur.fsproj

# Run the server (auto-applies DB migrations)
server-watch:
	ASPNETCORE_ENVIRONMENT=Development dotnet watch run --project server/src/Budgeteur --no-hot-reload

# Expecto tests
server-test:
	dotnet run --project server/tests/Budgeteur.Tests

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
	mkdir -p server/src/Budgeteur/wwwroot
	cp -r client/dist/* server/src/Budgeteur/wwwroot/

# Single-file publish (builds client, copies assets, publishes server)
publish: copy-client-dist
	dotnet publish server/src/Budgeteur/Budgeteur.fsproj \
		-c Release -r {{RUNTIME}} -o {{PUBLISH_DIR}} \
		-p:PublishTrimmed=true -p:TrimMode=partial \
		-p:Version={{VERSION}} -p:SourceRevisionId={{GIT_SHA}}

# Playwright E2E tests in Docker
e2e-test:
	docker compose -f docker-compose.e2e.yml up --abort-on-container-exit --exit-code-from e2e --remove-orphans

# Format with fantomas + gleam format
format:
	dprint fmt
	gleam format
	cd server && dotnet fantomas .

# Lint with fsharplint
lint: check-feature-boundaries
	cd server && dotnet fsharplint lint Budgeteur.slnx

# Fail if kernel code depends on a feature, or a feature imports another feature slice
check-feature-boundaries:
	#!/usr/bin/env bash
	set -euo pipefail
	fail=0

	# Feature files may only open their own slice (or Domain/Data/Shared)
	while IFS= read -r file; do
		slice="$(basename "$(dirname "$file")")"
		opens="$(grep -oE 'open Budgeteur\.Feature\.[A-Za-z]+' "$file" | sed 's/open Budgeteur\.Feature\.//' | sort -u || true)"
		while read -r dep; do
			if [[ -n "$dep" && "$dep" != "$slice" ]]; then
				echo "Cross-slice dependency: $file opens Budgeteur.Feature.$dep"
				fail=1
			fi
		done <<< "$opens"
	done < <(find server/src/Budgeteur/Feature -name '*.fs' -type f)

	# Kernel code (Shared/Domain/Data) must not depend on any feature
	while IFS= read -r file; do
		if grep -qE 'open Budgeteur\.Feature\.' "$file"; then
			echo "Kernel depends on a feature: $file"
			fail=1
		fi
	done < <(find server/src/Budgeteur/{Shared,Domain,Data} -name '*.fs' -type f)

	if [[ $fail -ne 0 ]]; then
		echo "Feature boundary violations found (see above)"
		exit 1
	fi

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
	dir="server/src/Budgeteur/Data/Migrations"
	count=$(ls "$dir"/*.sql 2>/dev/null | wc -l)
	num=$(printf "%03d" $((count + 1)))
	file="$dir/${num}_{{name}}.sql"
	echo "-- {{name}}" > "$file"
	echo "Created migration: Data/Migrations/$(basename "$file")"

# Apply pending migrations (standalone script)
db-migrate:
	cd server && dotnet fsi scripts/migrate.fsx

# Regenerate Db.fs types from live DB (SqlHydra)
db-generate:
	cd server && dotnet sqlhydra sqlite --project src/Budgeteur/Budgeteur.fsproj

# db-migrate + db-generate (full schema update)
db-update: db-migrate db-generate

# Delete DB, re-apply all migrations, regenerate
db-reset:
	rm -f server/src/Budgeteur/app.sqlite3
	just db-update
