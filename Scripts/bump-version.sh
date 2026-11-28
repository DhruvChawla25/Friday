#!/usr/bin/env bash
# Bump the app version: updates project.yml, CHANGELOG.md and regenerates the project.
# Usage: Scripts/bump-version.sh [--dry-run] X.Y.Z
set -euo pipefail

dry=0
version=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) version="$arg" ;;
  esac
done

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 [--dry-run] X.Y.Z" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
yml="$root/project.yml"
log="$root/CHANGELOG.md"
today="$(date +%Y-%m-%d)"

current="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\} *$/\1/p' "$yml" | head -1)"
build="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9]*\)"\{0,1\} *$/\1/p' "$yml" | head -1)"
[[ -n "$current" && -n "$build" ]] || { echo "could not read version from project.yml" >&2; exit 1; }
if grep -q "^## \[$version\]" "$log"; then
  echo "CHANGELOG.md already has a $version section" >&2
  exit 1
fi
newbuild=$((build + 1))

echo "Version: $current -> $version (build $build -> $newbuild), dated $today"
if [[ $dry -eq 1 ]]; then
  echo "[dry run] no files changed"
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed -e "s/^\( *MARKETING_VERSION: *\).*/\1\"$version\"/" \
  -e "s/^\( *CURRENT_PROJECT_VERSION: *\).*/\1\"$newbuild\"/" "$yml" > "$tmp"
cat "$tmp" > "$yml"

# Give the new version its own dated section under an empty Unreleased, and move the links.
awk -v v="$version" -v d="$today" -v prev="$current" '
  /^## \[Unreleased\]/ { print; print ""; print "## [" v "] - " d; next }
  /^\[Unreleased\]:/ {
    print "[Unreleased]: https://github.com/DhruvChawla25/Friday/compare/v" v "...HEAD"
    print "[" v "]: https://github.com/DhruvChawla25/Friday/compare/v" prev "...v" v
    next
  }
  { print }
' "$log" > "$tmp"
cat "$tmp" > "$log"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$root" && xcodegen generate)
fi

cat <<NEXT

Done. Next steps:
  1. Review CHANGELOG.md and tidy the $version notes.
  2. Commit ("Release $version") and open a pull request.
  3. After it merges, tag v$version on main and publish the release.
NEXT
