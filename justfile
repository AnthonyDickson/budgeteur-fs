RUNTIME := env_var_or_default("RUNTIME", "linux-x64")
PUBLISH_DIR := env_var_or_default("PUBLISH_DIR", "server/src/Budgeteur/bin/Release/publish")
VERSION := env_var_or_default("VERSION", "0.0.0-local")
GIT_SHA := env_var_or_default("GIT_SHA", "")

run:
	docker compose -f docker/docker-compose.yml up
	docker compose -f docker/docker-compose.yml down

# Run dotnet restore on the server solution
server-restore:
	cd server && dotnet restore

# Build the server
server-build:
	dotnet build server/src/Budgeteur/Budgeteur.fsproj

# Run the server (auto-applies DB migrations)
server-watch:
	ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS="${ASPNETCORE_URLS:-http://0.0.0.0:5000}" dotnet watch run --project server/src/Budgeteur --no-hot-reload

# Expecto tests (through the Expecto test adapter, same as IDE test explorers)
server-test:
	dotnet test server/Budgeteur.slnx

# Kotlin port PoC, see server-kt/README.md
kt-format:
	cd server-kt && gradle --no-daemon ktfmtFormat

kt-e2e-test:
	docker compose -f docker/docker-compose.e2e-kt.yml up --abort-on-container-exit --exit-code-from e2e --remove-orphans
	docker compose -f docker/docker-compose.e2e-kt.yml down

kt-test:
	cd server-kt && gradle --no-daemon test

# detekt, with type resolution (see server-kt/detekt.yml)
kt-lint:
	cd server-kt && gradle --no-daemon detektMain detektTest

# Pin the dev shell's kotlin-lsp to JetBrains' latest release; builds expire about a month after release.
update-kotlin-lsp:
	nix/packages/kotlin-lsp/update.sh

# npm install
client-install-deps:
	cd client && npm install

# gleeunit tests
client-test:
	cd client && gleam test

# Start the client dev server (Vite + Gleam watch)
client-watch:
	cd client && npx vite

# Development client bundle
client-build:
	cd client && npx vite build --mode development

# Production client bundle
client-build-prod:
	cd client && npx vite build

# Copy client dist into server wwwroot/
copy-client-dist: client-build-prod
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
	docker compose -f docker/docker-compose.e2e.yml up --abort-on-container-exit --exit-code-from e2e --remove-orphans
	docker compose -f docker/docker-compose.e2e.yml down

# Format with dprint (see dprint.json) + gleam format + fantomas + ktfmt
format: kt-format
	dprint fmt
	gleam format
	cd server && dotnet fantomas .

# Lint with fsharplint, and the Kotlin PoC with detekt
lint: check-architecture check-strings kt-lint
	cd server && dotnet fsharplint lint Budgeteur.slnx

# Reject a `\` line continuation inside a triple-quoted F# string, which keeps the backslash and the next line's
# indentation rather than joining the lines
check-strings:
	#!/usr/bin/env bash
	set -euo pipefail
	find server/src server/tests server/scripts \( -name '*.fs' -o -name '*.fsx' \) -not -path '*/bin/*' -not -path '*/obj/*' -print0 \
		| xargs -0 awk '
			FNR == 1 { inside = 0 }
			{
				if (gsub(/"""/, "&") % 2 == 1) inside = !inside
				if (inside && $0 ~ /\\[[:space:]]*$/) {
					printf "%s:%d: \\ does not continue a line in a \"\"\" string\n", FILENAME, FNR
					bad = 1
				}
			}
			END { exit bad }
		'

# Enforce the architecture rules that no compiler or formatter can: slice and shared module boundaries
check-architecture:
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

	# Shared modules (Shared/Domain/Data) must not depend on any feature
	while IFS= read -r file; do
		if grep -qE 'open Budgeteur\.Feature\.' "$file"; then
			echo "Shared module depends on a feature: $file"
			fail=1
		fi
	done < <(find server/src/Budgeteur/{Shared,Domain,Data} -name '*.fs' -type f)

	# The same rules for the Kotlin PoC. Kotlin names another package through an import or a
	# fully qualified name, so match both, and skip the file's own package line.
	kt="server-kt/src/main/kotlin/budgeteur"
	while IFS= read -r file; do
		slice="$(basename "$(dirname "$file")")"
		deps="$(grep -v '^package ' "$file" | grep -oE 'budgeteur\.feature\.[a-z]+' | sed 's/budgeteur\.feature\.//' | sort -u || true)"
		while read -r dep; do
			if [[ -n "$dep" && "$dep" != "$slice" ]]; then
				echo "Cross-slice dependency: $file uses budgeteur.feature.$dep"
				fail=1
			fi
		done <<< "$deps"
	done < <(find "$kt/feature" -name '*.kt' -type f)

	while IFS= read -r file; do
		if grep -v '^package ' "$file" | grep -qE 'budgeteur\.feature\.'; then
			echo "Shared package depends on a feature: $file"
			fail=1
		fi
	done < <(find "$kt"/{shared,domain,data} -name '*.kt' -type f)

	if [[ $fail -ne 0 ]]; then
		echo "Architecture violations found (see above)"
		exit 1
	fi

# Anonymise a raw bank export (kept in the gitignored raw-exports/) into a test fixture, e.g.
# just anonymise-csv raw-exports/kiwibank.csv server/tests/Budgeteur.Tests/Import/Fixtures/Kiwibank.csv
anonymise-csv input output:
	dotnet fsi server/scripts/anonymise.fsx "{{input}}" "{{output}}" raw-exports/anonymise.key

# Audit the project dependencies for known vulnerabilities
audit:
	cd client && npm audit
	cd server && dotnet list package --vulnerable
	cd server-kt && gradle --no-daemon -q cyclonedxDirectBom
	osv-scanner scan --lockfile server-kt/build/reports/cyclonedx-direct/bom.json

# List the outdated packages in the project
outdated:
	cd client && gleam deps outdated
	# use `-` to ignore the exit code npm so outdated packages don't stop the next command from being run by just
	-cd client && npm outdated
	cd server && dotnet list package --outdated
	# Pre-releases are offered only in place of a pre-release (see server-kt/build.gradle.kts)
	cd server-kt && gradle --no-daemon dependencyUpdates

# Update all dependencies in the project to their latest versions
update:
	cd client && gleam update
	cd client && npm update
	cd server && dotnet package update
	cd server && dotnet tool update --all
	# Rewrites server-kt/gradle/libs.versions.toml; versions marked @pin stay
	cd server-kt && gradle --no-daemon versionCatalogUpdate

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

# Capture the README's screenshots from mock data in the E2E stack, into docs/images
readme-screenshots:
	#!/usr/bin/env bash
	set -euo pipefail
	trap 'docker compose -f docker/docker-compose.e2e.yml down' EXIT
	docker compose -f docker/docker-compose.e2e.yml run --rm e2e \
		sh -c "npm install && npx playwright test --config readme.config.ts --reporter=line"
	mkdir -p docs/images
	cp tests/e2e/test-results/readme/*.png docs/images/
