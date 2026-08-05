FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg just \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Gleam
ARG GLEAM_VERSION=1.18.0

RUN curl -fsSL https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/local/bin

WORKDIR /src

# Restore dotnet tools and packages
COPY server/dotnet-tools.json server/
RUN cd server && dotnet tool restore

COPY server/Directory.Build.props server/Directory.Packages.props server/
COPY server/Budgeteur.slnx server/
COPY server/src/Budgeteur/Budgeteur.fsproj server/src/Budgeteur/
# The test fsproj file needs to be included due to the solution file referencing
# it despite it not being needed for the built binary.
COPY server/tests/Budgeteur.Tests/Budgeteur.Tests.fsproj server/tests/Budgeteur.Tests/
RUN cd server && dotnet restore

# Install client dependencies
COPY client/package*.json client/
RUN npm ci --prefix client

# Copy everything and publish
COPY ./justfile ./
COPY ./server ./server
COPY ./client ./client
ARG RUNTIME=linux-x64
RUN RUNTIME=${RUNTIME} PUBLISH_DIR=/publish just publish

FROM debian:stable-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libicu76 adduser \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos '' appuser

EXPOSE 5000

COPY --from=build /publish/Budgeteur /app/
COPY --from=build /publish/wwwroot/ /app/wwwroot/
COPY --from=build /publish/Budgeteur.staticwebassets.endpoints.json /app/

WORKDIR /app
USER appuser
ENV ASPNETCORE_URLS=http://0.0.0.0:5000
ENTRYPOINT ["./Budgeteur"]
