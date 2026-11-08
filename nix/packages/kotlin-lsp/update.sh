#!/usr/bin/env bash
# Pin the dev shell's `kotlin-lsp` to JetBrains' latest release.
#
# JetBrains builds of kotlin-lsp expire about a month after release, and old
# downloads are deleted, so the pin in `pin.json` beside this script has to move
# every few weeks. This reads the latest GitHub release, takes the SHA-256 of
# each platform's download from the `.sha256` file JetBrains publishes beside
# it, and rewrites the JSON that `default.nix` reads. Run it from the repository
# root (`just update-kotlin-lsp`), then re-enter the dev shell.
set -euo pipefail

pin=nix/packages/kotlin-lsp/pin.json
api=https://api.github.com/repos/Kotlin/kotlin-lsp/releases/latest
cdn=https://download.jetbrains.com/language-server/kotlin-server

release=$(curl -fsSL "$api")
tag=$(printf '%s' "$release" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
published=$(printf '%s' "$release" | sed -n 's/.*"published_at": *"\([^"]*\)".*/\1/p' | head -n 1)
version=${tag#kotlin-lsp/v}

if [[ -z $tag || -z $published || $version == "$tag" ]]; then
    echo "error: unexpected release metadata from $api (tag '$tag')" >&2
    exit 1
fi

# GNU date (Linux) takes -d; BSD date (macOS) needs an explicit input format.
released_epoch=$(date -u -d "$published" +%s 2>/dev/null ||
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$published" +%s)
released=${published%%T*}

current=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$pin")
if [[ $version == "$current" ]]; then
    echo "kotlin-lsp is already pinned to the latest release, $version (released $released)."
    exit 0
fi

# One download per platform: Linux as a tarball, macOS as a zip named `.sit`.
hash_of() {
    local file=$1 hex
    hex=$(curl -fsSL "$cdn/$version/$file.sha256" | cut -c1-64)
    if [[ ! $hex =~ ^[0-9a-f]{64}$ ]]; then
        echo "error: no SHA-256 published for $file" >&2
        exit 1
    fi
    nix hash convert --hash-algo sha256 --to sri "$hex"
}

x86_64_linux=$(hash_of "kotlin-server-$version.tar.gz")
aarch64_linux=$(hash_of "kotlin-server-$version-aarch64.tar.gz")
aarch64_darwin=$(hash_of "kotlin-server-$version-aarch64.sit")

cat > "$pin" <<EOF
{
  "version": "$version",
  "released": "$released",
  "releasedEpoch": $released_epoch,
  "hashes": {
    "x86_64-linux": "$x86_64_linux",
    "aarch64-linux": "$aarch64_linux",
    "aarch64-darwin": "$aarch64_darwin"
  }
}
EOF

echo "kotlin-lsp: $current -> $version (released $released)."
echo "Re-enter the dev shell to download it, then restart your editor's language server."
