#!/usr/bin/env bash
# caveman: cut the next release from one merged PR. no human picks a number:
# the PR title says what kind of change it was, this script does the rest.
# the release workflow runs it on every merge to main, then commits and tags.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/release.sh --title <pr title> [--body <file>] [--url <pr url>] [--date YYYY-MM-DD]

writes the next VERSION and its CHANGELOG.md entry, and prints the version.
commits, tags and pushes nothing - the release workflow does that.

the bump comes from the PR title, conventional-commit style:
  feat!: ... / fix(x)!: ... / "BREAKING CHANGE" in the body   -> major
  feat: ... / feat(x): ...                                     -> minor
  anything else                                                -> patch

lines in the body that start with "Action needed:" go into the entry. a
major release without one gets a pointer to the PR instead, so a client is
never told "required" without being told where to read why.

if VERSION is not tagged yet - someone set it by hand in the PR - that
version is released as is and nothing is bumped.
USAGE
}

TITLE=""
BODY=""
URL=""
DATE="$(date -u +%Y-%m-%d)"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --title) shift; TITLE="${1:-}" ;;
    --body)  shift; BODY="${1:-}" ;;
    --url)   shift; URL="${1:-}" ;;
    --date)  shift; DATE="${1:-}" ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done
[ -n "$TITLE" ] || { echo "error: --title is required" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=factory_common.sh
. "$ROOT/scripts/factory_common.sh"
cd "$ROOT"

CUR="$(factory_engine_version "$ROOT")"
[ -n "$CUR" ] || { echo "error: VERSION is missing or not X.Y.Z" >&2; exit 1; }
BODY_TEXT=""
[ -z "$BODY" ] || BODY_TEXT="$(cat "$BODY")"

KIND="patch"
if printf '%s\n' "$TITLE" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:' ||
   printf '%s\n' "$BODY_TEXT" | grep -q 'BREAKING CHANGE'; then KIND="major"
elif printf '%s\n' "$TITLE" | grep -qE '^feat(\([^)]*\))?:'; then KIND="minor"
fi

if git rev-parse -q --verify "refs/tags/v$CUR" >/dev/null; then
  IFS=. read -r MA MI PA <<<"$CUR"
  case "$KIND" in
    major) NEXT="$((MA+1)).0.0" ;;
    minor) NEXT="$MA.$((MI+1)).0" ;;
    patch) NEXT="$MA.$MI.$((PA+1))" ;;
  esac
else
  NEXT="$CUR"   # caveman: set by hand and not out yet - honour it
fi

# caveman: an entry for this version already written by hand wins.
TOP="$(sed -n 's/^## \([0-9][0-9.]*\) .*/\1/p' CHANGELOG.md | head -1)"
if [ "$TOP" != "$NEXT" ]; then
  SUBJECT="$(printf '%s\n' "$TITLE" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?!?: *//')"
  ACTION="$(printf '%s\n' "$BODY_TEXT" | tr -d '\r' | grep -E '^Action needed:' || true)"
  if [ -z "$ACTION" ] && [ "$KIND" = "major" ]; then
    ACTION="Action needed: breaking change, read ${URL:-the merged PR} before updating."
  fi
  ENTRY="$(mktemp)"
  {
    printf '## %s - %s\n\n' "$NEXT" "$DATE"
    printf -- '- %s%s\n' "$SUBJECT" "${URL:+ ($URL)}"
    [ -z "$ACTION" ] || printf '\n%s\n' "$ACTION"
    printf '\n'
  } > "$ENTRY"
  # caveman: newest first - the entry goes in front of the first release heading.
  awk -v entry="$ENTRY" '
    !done && /^## [0-9]/ { while ((getline l < entry) > 0) print l; done = 1 }
    { print }
    END { if (!done) { while ((getline l < entry) > 0) print l } }' CHANGELOG.md > CHANGELOG.md.new
  mv CHANGELOG.md.new CHANGELOG.md
  rm -f "$ENTRY"
fi

printf '%s\n' "$NEXT" > VERSION
printf '%s\n' "$NEXT"
