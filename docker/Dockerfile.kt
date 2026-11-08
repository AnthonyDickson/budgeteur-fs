# The production image of the Kotlin PoC (server-kt/), serving the client's
# build as docker/Dockerfile does for the F# server.

# =====Client===== #
FROM node:24 AS client

ARG GLEAM_VERSION=1.18.0

RUN curl -fsSL https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/local/bin

WORKDIR /src/client
COPY client/package*.json ./
RUN npm ci
COPY client ./
RUN npx vite build

# =====Server===== #
FROM gradle:8.14.4-jdk21 AS server

WORKDIR /src/server-kt

# Resolve the dependencies in their own layer, so a source change reuses them.
COPY server-kt/settings.gradle.kts server-kt/build.gradle.kts server-kt/detekt.yml ./
COPY server-kt/gradle ./gradle
RUN gradle --no-daemon --quiet dependencies > /dev/null

COPY server-kt/src ./src
ARG APP_VERSION=0.0.0-local
ARG GIT_SHA=""
RUN gradle --no-daemon --quiet installDist -PappVersion=${APP_VERSION} -PgitSha=${GIT_SHA}

# =====Runtime===== #

# A JRE on Alpine. sqlite-jdbc bundles a musl build of SQLite, and BusyBox's
# wget serves the container healthcheck.
FROM eclipse-temurin:21-jre-alpine AS runtime

# A non-root `app` user, with the F# image's UID. Mount points for the database
# and logs. A fresh named volume copies the ownership of the image directory it
# mounts over, so these must exist and be owned by app, or SQLite cannot create
# the database.
RUN adduser -D -H -u 1654 app \
    && mkdir -p /data /logs \
    && chown app:app /data /logs

EXPOSE 5000

COPY --from=server /src/server-kt/build/install/budgeteur /app/
COPY --from=client /src/client/dist /app/wwwroot/

WORKDIR /app
USER app
ENV PORT=5000 \
    BUDGETEUR_WEB_ROOT=/app/wwwroot
ENTRYPOINT ["/app/bin/budgeteur"]
