#!/usr/bin/env bash
set -euo pipefail

# ── Usage ──────────────────────────────────────────────────────────────────
#   ./scripts/rename.sh --to-pascal MyApp --to-kebab my-app
#
# Renames everything in a LustreTodos template clone:
#   - PascalCase:  LustreTodos  → MyApp   (namespaces, class names, .fsproj, .slnx)
#   - kebab-case:  lustre-todos → my-app  (container names, image tags, URLs)
#
# The script is idempotent — run it against an already-renamed project and
# nothing happens (the old strings no longer exist).
# ────────────────────────────────────────────────────────────────────────────

OLD_PASCAL="LustreTodos"
OLD_KEBAB="lustre-todos"
NEW_PASCAL=""
NEW_KEBAB=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --to-pascal) NEW_PASCAL="$2"; shift 2 ;;
        --to-kebab)  NEW_KEBAB="$2";  shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$NEW_PASCAL" || -z "$NEW_KEBAB" ]]; then
    echo "Usage: $0 --to-pascal <PascalCase> --to-kebab <kebab-case>"
    echo "Example: $0 --to-pascal MyApp --to-kebab my-app"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Renaming: ${OLD_PASCAL} → ${NEW_PASCAL}  |  ${OLD_KEBAB} → ${NEW_KEBAB}"

# ── 1. Text replacements (PascalCase + kebab-case) ─────────────────────────
# Exclude binary/build artifacts, node_modules, .git, DB files, lockfiles.
echo "Replacing text in files..."

TEXT_FILES=$(
    find . -type f \
        -not -path '*/.git/*' \
        -not -path '*/.crush/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/build/*' \
        -not -path '*/bin/*' \
        -not -path '*/obj/*' \
        -not -path '*/dist/*' \
        -not -path '*/wwwroot/*' \
        -not -name '*.db' \
        -not -name '*.db-shm' \
        -not -name '*.db-wal' \
        -not -name '*.sqlite3' \
        -not -name '*.exe' \
        -not -name '*.dll' \
        -not -name '*.so' \
        -not -name '*.png' \
        -not -name '*.jpg' \
        -not -name '*.ico' \
        -not -name '*.woff2' \
        -not -name 'package-lock.json' \
        -not -name 'packages.lock.json' \
        -not -name 'rename.sh'
)

for f in $TEXT_FILES; do
    # PascalCase replacement
    if grep -qFI "$OLD_PASCAL" "$f" 2>/dev/null; then
        sed -i "s|${OLD_PASCAL}|${NEW_PASCAL}|g" "$f"
    fi
    # kebab-case replacement
    if grep -qFI "$OLD_KEBAB" "$f" 2>/dev/null; then
        sed -i "s|${OLD_KEBAB}|${NEW_KEBAB}|g" "$f"
    fi
    # Documentation tokens
    if grep -qFI '__PROJECT_NAME__' "$f" 2>/dev/null; then
        sed -i "s|__PROJECT_NAME__|${NEW_PASCAL}|g" "$f"
    fi
    if grep -qFI '__PROJECT_KEBAB__' "$f" 2>/dev/null; then
        sed -i "s|__PROJECT_KEBAB__|${NEW_KEBAB}|g" "$f"
    fi
done

# ── 2. Rename .fsproj and .slnx files ──────────────────────────────────────
echo "Renaming project files..."

while IFS= read -r -d '' f; do
    dir=$(dirname "$f")
    base=$(basename "$f")
    new_base="${base//${OLD_PASCAL}/${NEW_PASCAL}}"
    if [[ "$base" != "$new_base" ]]; then
        mv "$f" "$dir/$new_base"
    fi
done < <(find . -type f \( -name '*.fsproj' -o -name '*.slnx' \) -print0)

# ── 3. Rename directories (deepest-first) ──────────────────────────────────
echo "Renaming directories..."

while IFS= read -r -d '' d; do
    parent=$(dirname "$d")
    base=$(basename "$d")
    new_base="${base//${OLD_PASCAL}/${NEW_PASCAL}}"
    if [[ "$base" != "$new_base" ]]; then
        mv "$d" "$parent/$new_base"
    fi
done < <(find . -type d -name "*${OLD_PASCAL}*" -print0 | sort -rz)

echo "Done. Verify with: git diff --stat"
