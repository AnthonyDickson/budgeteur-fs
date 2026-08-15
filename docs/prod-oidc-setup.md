# Production OIDC Setup

> [!IMPORTANT]
> The files under `authelia/`, `docker-compose.yml`, and `appsettings.Development.json`
> are **not used in production**. Configure the server via environment variables.

## Overview

The server uses two OIDC schemes:

| Scheme     | Auth flow                    | Used by                    |
| ---------- | ---------------------------- | -------------------------- |
| Cookie     | Authorization code → session | SPA (browser)              |
| JWT Bearer | Authorization code + PKCE    | Scalar API docs (dev only) |

Either scheme satisfies the `authenticated` policy on protected endpoints.

## Environment Variables

```bash
Oidc__Authority              # Required. OIDC discovery URL
Oidc__ClientId               # Required. SPA client ID (confidential)
Oidc__ClientSecret           # Required. SPA client secret
Oidc__CallbackPath           # Required. Redirect URI path (e.g. /signin-oidc)
Oidc__ValidAudiences         # Optional. Accepted JWT audiences; if unset, audience validation is disabled
Login__ReturnUrl             # Required. Post-login redirect (e.g. https://app.example.com/)
OAuth2__AuthorizationUrl     # Optional. Scalar OAuth2 flow (dev only)
OAuth2__TokenUrl             # Optional. Scalar OAuth2 flow (dev only)
```

The `OAuth2__*` settings configure the OAuth2 flow in the Scalar API docs, which
are only served in development. They are not needed in production. Likewise,
audience validation for the JWT bearer scheme is off by default because Authelia
access tokens carry no `aud` claim — set `Oidc__ValidAudiences` if your provider
emits one.

## 1. Deploy an OIDC Provider

Any standards-compliant OIDC provider works — Authelia, Keycloak, Auth0, Authentik, Entra ID, etc.

### Authelia-specific

Adapt the dev config from `authelia/configuration.yml`:

- **Replace TLS certs** under `server.tls` with real certificates (e.g. Let's Encrypt).
- **Regenerate every secret.** The dev secrets are public. Generate 32-byte hex values:
  ```bash
  openssl rand -hex 32
  ```
  Replace: `session.secret`, `storage.encryption_key`,
  `identity_validation.reset_password.jwt_secret`, `identity_providers.oidc.hmac_secret`.
- **Regenerate the JWKS key pair:**
  ```bash
  openssl genpkey -algorithm RSA -out private.pem -pkeyopt rsa_keygen_bits:2048
  ```
  Paste the private key into `identity_providers.oidc.jwks[].key`.
- Replace the file-based user backend with LDAP (or another production backend).
- Set `session.cookies[].domain` to your production domain.
- Run behind a reverse proxy (nginx, Caddy) that terminates TLS, or configure TLS in Authelia directly.

## 2. Register OIDC Clients

Two clients are needed:

|                       | SPA                                    | Scalar/API                   |
| --------------------- | -------------------------------------- | ---------------------------- |
| **Client type**       | Confidential                           | Public (PKCE)                |
| **Grant types**       | `authorization_code` + `refresh_token` | `authorization_code`         |
| **Response types**    | `code`                                 | `code`                       |
| **Token auth method** | `client_secret_post`                   | `none`                       |
| **Scopes**            | `openid profile email offline_access`  | `openid profile email`       |
| **Redirect URIs**     | `https://<domain>/signin-oidc`         | `https://<domain>/scalar/v1` |

The SPA redirect URI must match `Oidc__CallbackPath`.

## 3. Configure the Server

```bash
export Oidc__Authority=https://auth.example.com
export Oidc__ClientId=budgeteur-fs
export Oidc__ClientSecret=<your-production-secret>
export Oidc__CallbackPath=/signin-oidc
export Login__ReturnUrl=https://app.example.com/
# OAuth2__* is dev-only (Scalar docs) — omit in production
```

Then start:

```bash
dotnet run --project server/src/Budgeteur
```

The server validates its configuration at startup and refuses to boot if any
setting is missing or malformed, printing every failed setting — if it won't
start, read the error output rather than guessing at env vars.

## Cookie Security (Non-Development)

When `ASPNETCORE_ENVIRONMENT` is not `Development`:

- `Cookie.SecurePolicy = Always`
- `Cookie.SameSite = Lax`
- `Cookie.HttpOnly = true`
- `RequireHttpsMetadata = true` for JWT bearer
- Self-signed cert validation is **not** bypassed

Other non-obvious auth behaviours:

- Claims are taken from the ID token — the userinfo endpoint is not called by
  default. Enable `GetClaimsFromUserInfoEndpoint` to get `name`/`email` claims.
- `/logout` only clears the local session cookie; Authelia does not yet support
  RP-initiated logout, so the provider session persists.

## Verify

1. `https://<domain>/login` → redirected to OIDC login
2. Authenticate → redirected back to SPA
3. `GET /api/<resource>` → returns data, not `401`
4. In development only: `https://<domain>/scalar/v1` → OAuth2 flow works

## Troubleshooting

| Symptom                                     | Likely cause                                   |
| ------------------------------------------- | ---------------------------------------------- |
| `401` on login redirect                     | `Oidc__CallbackPath` or redirect URI mismatch  |
| `Correlation failed` error                  | Cookies blocked (third-party / SameSite issue) |
| `invalid_client` from provider              | Wrong client secret or token auth method       |
| JWT bearer returns `401`                    | `RequireHttpsMetadata` + HTTP authority        |
| Self-signed cert rejected                   | Use a real certificate, not the dev one        |
| `Options.Authority` or `.ClientId` is blank | Missing or misnamed environment variable       |
