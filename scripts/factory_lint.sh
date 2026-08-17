#!/usr/bin/env bash
# caveman: check shape of factory files. no judgement, no tokens, just rules.
# anything a machine can decide, decide here. claude reads what is left.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/factory_lint.sh [slug|--all] [--quiet]

  <slug>      lint brief, spec, handoff and logs for one slug.
              default: the slug of the newest handoff.
  --all       lint every slug that has a handoff.
  --contract  contract only - brief, spec, handoff. skips the logs, so a dead
              round does not read as a broken handoff. this is what the runner
              gates on before spending a round.
  --quiet     findings only, no "ok" lines.

checks shape, not correctness: required sections, a valid Difficulty line, at
least one done criterion, paths that do not exist, check blocks missing a
Status or a Next fix, logs that end mid-run, project brain files still carrying
the template marker.

deterministic, free, no model call. safe to run at any time, including while
agy is running.

exit 0 = no errors (warnings may still be printed)
exit 1 = errors found
exit 2 = usage error
USAGE
}

# caveman: find the engine through this script's own symlink, then load the
# shared bones. this is the only duplicated block in the scripts, and it has to
# be: it is what makes sharing possible at all.
SELF="$0"; while [ -L "$SELF" ]; do L="$(readlink "$SELF")"
  case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
FACTORY_ENGINE="$(cd "$(dirname "$SELF")/.." && pwd -P)"
# shellcheck source=factory_common.sh
. "$FACTORY_ENGINE/scripts/factory_common.sh"

SLUG=""
ALL=0
QUIET=0
CONTRACT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    --all)      ALL=1 ;;
    --quiet)    QUIET=1 ;;
    --contract) CONTRACT_ONLY=1 ;;
    -*)        echo "unknown arg: $1" >&2; usage; exit 2 ;;
    *)         SLUG="$1" ;;
  esac
  shift
done

REPO_ROOT="$(factory_repo_root)" || true
[ -n "$REPO_ROOT" ] || { echo "error: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"
factory_load_env "$REPO_ROOT"

FINDINGS="$(mktemp "${TMPDIR:-/tmp}/factory-lint.XXXXXX")"
trap 'rm -f "$FINDINGS"' EXIT

err()  { printf 'ERROR  %s\n' "$*" >> "$FINDINGS"; }
warn() { printf 'warn   %s\n' "$*" >> "$FINDINGS"; }
ok()   { [ "$QUIET" -eq 1 ] || printf 'ok     %s\n' "$*" >> "$FINDINGS"; }

# caveman: lines between "## heading" and the next "## ".
section() { # section <file> <heading>
  awk -v h="$2" '
    $0 == h { f = 1; next }
    /^## /  { f = 0 }
    f' "$1"
}

need_heading() { # need_heading <file> <heading>
  if grep -qE "^$2 *$" "$1"; then return 0; fi
  err "$1: missing section '$2'"
}

lint_brain() {
  for f in factory/context.md factory/memory.md factory/prompt-extra.md; do
    [ -s "$f" ] || continue
    if factory_is_template "$f"; then
      warn "$f: still has the factory:template marker on line 1, so it is NOT sent to agy"
    fi
  done
  if [ -f factory.env ]; then
    [ -n "$TEST_CMD" ] || err "factory.env: TEST_CMD is empty"
  else
    err "factory.env: missing. copy factory-engine/factory.env.example to factory.env"
  fi
}

lint_brief() { # lint_brief <slug>
  local f="factory/briefs/$1.md"
  [ -f "$f" ] || return 0
  need_heading "$f" "## Problem"
  need_heading "$f" "## Approach"
  need_heading "$f" "## Rejected"
  if grep -qE '^## Rejected *$' "$f"; then
    if [ -z "$(section "$f" "## Rejected" | grep -E '^[-*] +[^ ]' || true)" ]; then
      err "$f: Rejected has no entries. a design with no discarded alternative was a reflex (PRINCIPLES #11)"
    fi
  fi
  ok "$f"
}

lint_spec() { # lint_spec <slug>
  local f="specs/$1.md"
  [ -f "$f" ] || { err "specs/$1.md: missing. agy is told to read it and will not find it"; return 0; }
  need_heading "$f" "## Problem"
  need_heading "$f" "## Solution"
  need_heading "$f" "## Scope"
  ok "$f"
}

lint_handoff() { # lint_handoff <path>
  local f="$1"
  need_heading "$f" "## Goal"
  need_heading "$f" "## Files to touch"
  need_heading "$f" "## Tests to run"
  need_heading "$f" "## Done criteria"

  grep -qE '^Difficulty: *(mechanical|normal|tricky) *$' "$f" ||
    err "$f: no valid 'Difficulty:' line (mechanical | normal | tricky). /factory-build needs it to pick a model"

  local boxes
  boxes="$(grep -cE '^- \[[ xX]\] ' "$f" || true)"
  [ "${boxes:-0}" -ge 1 ] ||
    err "$f: no done criteria. a handoff with nothing to check is not a contract"

  if [ -n "$TEST_CMD" ] && ! grep -qF "$TEST_CMD" "$f"; then
    warn "$f: does not contain TEST_CMD from factory.env ($TEST_CMD)"
  fi

  # caveman: every path named must exist, or say NEW. a made-up path costs a round.
  section "$f" "## Files to touch" | grep -E '^[-*] ' | while IFS= read -r line; do
    case "$line" in *NEW*) continue ;; esac
    local p
    p="$(printf '%s\n' "$line" | sed -n 's/^[-*] *`\([^`]*\)`.*/\1/p')"
    [ -n "$p" ] || continue
    [ -e "$p" ] || printf 'warn   %s: lists `%s`, which does not exist and is not marked NEW\n' "$f" "$p" >> "$FINDINGS"
  done

  # caveman: check blocks are the run history. a malformed one loses a round.
  awk -v f="$f" '
    function flush() {
      if (blk == "") return
      if (!st)                  printf "ERROR  %s: check block %s has no Status: line\n", f, blk
      if (!tst)                 printf "warn   %s: check block %s has no Tests: line\n", f, blk
      if (needsfix && !nextfix) printf "ERROR  %s: check block %s says Needs fix but has no \"### Next fix\" section\n", f, blk
      if (st && !valid)         printf "ERROR  %s: check block %s has an unknown Status (want Success or Needs fix)\n", f, blk
    }
    /^## Check/ {
      flush()
      blk = ($3 == "" ? "<no timestamp>" : $3)
      st = tst = needsfix = nextfix = valid = 0
      next
    }
    blk == "" { next }
    /^Status:/ {
      st = 1
      if ($0 ~ /^Status: *Success *$/)   valid = 1
      if ($0 ~ /^Status: *Needs fix *$/) { valid = 1; needsfix = 1 }
    }
    /^Tests:/        { tst = 1 }
    /^### Next fix/  { nextfix = 1 }
    END { flush() }
  ' "$f" >> "$FINDINGS"

  ok "$f"
}

lint_logs() { # lint_logs <slug>
  local newest n
  n="$(factory_count_logs "$1")"
  [ "$n" -gt 0 ] || return 0
  newest="$(factory_newest_log "$1")"

  # caveman: a truncated run and a clean run look identical from outside.
  # the only honest tells are structural - see PRINCIPLES #3.
  grep -q '^=== agy exit code:' "$newest" ||
    err "$newest: no exit-code footer. the runner was killed mid-round; that round is unfinished"
  grep -q 'RESULT:' "$newest" ||
    err "$newest: no RESULT: block. the run was truncated, whatever the exit code said"
  grep -q 'WALKTHROUGH:' "$newest" ||
    warn "$newest: no WALKTHROUGH: block. nothing to check the diff against"

  local code
  code="$(sed -n 's/^=== agy exit code: \([0-9]*\) ===/\1/p' "$newest" | tail -n 1)"
  [ -z "$code" ] || [ "$code" = "0" ] ||
    warn "$newest: agy exited $code - every model in the chain failed to run"

  ok "$newest ($n round(s) logged)"
}

lint_slug() { # lint_slug <slug>
  local slug="$1" handoff
  handoff="$(factory_newest_handoff "$slug")"
  printf -- '--- %s\n' "$slug" >> "$FINDINGS"
  lint_brief "$slug"
  lint_spec  "$slug"
  if [ -n "$handoff" ]; then
    lint_handoff "$handoff"
  else
    err "handoffs/: no handoff for slug '$slug'"
  fi
  [ "$CONTRACT_ONLY" -eq 1 ] || lint_logs "$slug"
}

lint_brain

if [ "$ALL" -eq 1 ]; then
  SLUGS="$(factory_all_slugs)"
  [ -n "$SLUGS" ] || { echo "no handoffs found in handoffs/"; exit 0; }
  for s in $SLUGS; do lint_slug "$s"; done
else
  if [ -z "$SLUG" ]; then
    SLUG="$(factory_default_slug)" ||
      { echo "no handoffs found in handoffs/"; exit 0; }
    [ -n "$SLUG" ] || { echo "no handoffs found in handoffs/"; exit 0; }
  fi
  lint_slug "$SLUG"
fi

cat "$FINDINGS"
E="$(grep -c '^ERROR' "$FINDINGS" || true)"
W="$(grep -c '^warn' "$FINDINGS" || true)"
echo
echo "$E error(s), $W warning(s)"
[ "$E" -eq 0 ] || exit 1
exit 0
