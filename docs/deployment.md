# Deployment

## Publishing via Binary

```bash
just publish                    # linux-x64 (default)
RUNTIME=osx-arm64 just publish  # macOS Apple Silicon
```

Builds the client Vite bundle, copies it into `server/src/Budgeteur/wwwroot/`,
then publishes the server as a self-contained single-file binary with trimming.
Output: `server/src/Budgeteur/bin/Release/publish/`

## Publishing via Docker

### Building

```bash
# Build
docker build -t ghcr.io/your-org/budgeteur-fs:latest .
# Login, e.g. with a GitHub Personal Access Token with the `write:packages` permissions
cat $MY_PAT | docker login ghcr.io -u $(gh api user --jq .login) --password-stdin
# Push
docker push ghcr.io/your-org/budgeteur-fs:latest
```

The multi-stage `Dockerfile` installs Node.js and Gleam, builds the client, then
publishes the server into a minimal `debian:stable-slim` runtime image — only
the packages needed for TLS, health checks, and the ICU globalization
assemblies. It runs as a non-root `appuser`.

> [!NOTE]
> When publishing from the CLI, you will need to manually set the "package" (image) to publish and then assign the
> package to your repo. See the page on [Working with the Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
> and [Connecting a repository to a package](https://docs.github.com/en/packages/learn-github-packages/connecting-a-repository-to-a-package)
> Building and pushing the image from a GitHub Workflow will automatically associate the package with the source repo.

### Deploying

```bash
cp docker-compose.prod.example.yml docker-compose.prod.yml
# edit docker-compose.prod.yml with your OIDC settings, then:
docker compose -f docker-compose.prod.yml up -d
```

The example compose file ships with dev OIDC defaults. Override for production:

```bash
Oidc__Authority=https://auth.example.com \
Oidc__ClientId=budgeteur-fs \
Oidc__ClientSecret="$(pass show oidc/budgeteur-fs/client-secret)" \
Oidc__CallbackPath=/signin-oidc \
Login__ReturnUrl=https://app.example.com/ \
  docker compose -f docker-compose.prod.yml up -d
```

> **Note**: `docker-compose.prod.yml` is gitignored. Copy from `docker-compose.prod.example.yml` and customize it.

See [Production OIDC Setup](prod-oidc-setup.md) for the full OIDC configuration guide.

### Database in Production

The server uses SQLite. Override the connection string to use a persistent path:

```bash
ConnectionStrings__Default="Data Source=/data/app.db" \
  docker compose -f docker-compose.prod.yml up -d
```

Use an absolute path — relative paths resolve to the container's working directory,
which is ephemeral.

> [!WARNING]
> The container runs as a non-root `appuser` (UID 1000). Named Docker volumes
> are auto-created with correct permissions, but **bind mounts** (`driver_opts`
> with `o = "bind"`) require the host directory to already exist and be
> writable by UID 1000:
>
> ```bash
> mkdir -p /var/lib/my-app && chown 1000:1000 /var/lib/my-app
> ```
>
> On NixOS, use `systemd.tmpfiles.rules`:
>
> ```nix
> systemd.tmpfiles.rules = [ "d /var/lib/my-app 0755 1000 1000 -" ];
> ```
>
> Failure to do this results in `SQLite Error 14: 'unable to open database file'`.

### Health checks

Container healthchecks probe `GET /api/status`, which reports the build version,
uptime, and a database connectivity probe — returning `503` when the database is
unreachable.

## Static Assets

**Client assets** (images, fonts, favicons — anything the SPA references) live in
`client/public/`. Vite serves them at root in dev and copies them into `dist/`
on build. They reach the server via `just copy-client-dist`.

**Server-only assets** (e.g. `robots.txt`) live in `server/src/Budgeteur/wwwroot/`.
The `wwwroot/` directory is gitignored and populated by `copy-client-dist` during
publish. Persistent server assets should have their source of truth elsewhere
(e.g. a build step that copies them in).

## Hosting

The web server is intended to run behind a reverse proxy such as nginx or Caddy.
No effort is made to make the web server secure to deploy on its own.
