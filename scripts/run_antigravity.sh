#!/usr/bin/env bash
# caveman: take slug. find spec + handoff. tell agy do work. save log.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/run_antigravity.sh <slug|handoff-path> [--dry-run]

  <slug>          slug of spec. script finds specs/<slug>.md and newest
                  handoffs/<timestamp>-<slug>.md
  <handoff-path>  path to a handoff file. slug read from filename.
  --dry-run       print the prompt and the agy command, call nothing.

config comes from factory.env in repo root (see factory.env.example).
log goes to handoffs/logs-<timestamp>-<slug>.txt
USAGE
}

[ $# -ge 1 ] || { usage; exit 2; }
[ "$1" = "-h" ] || [ "$1" = "--help" ] && { usage; exit 0; }

TARGET="$1"; shift
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

# caveman: work from repo root. all paths relative to it.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

# caveman: config. defaults if no factory.env.
TEST_CMD=""
AGY_MODEL="claude-sonnet-4-6"
AGY_TIMEOUT="30m"
# shellcheck source=/dev/null
[ -f factory.env ] && . ./factory.env

# caveman: figure out slug and handoff.
if [ -f "$TARGET" ]; then
  HANDOFF="$TARGET"
  BASE="$(basename "$HANDOFF" .md)"
  SLUG="${BASE#*-}"          # strip leading <timestamp>-
else
  SLUG="$TARGET"
  # newest handoff for this slug
  HANDOFF="$(ls -1 handoffs/*-"$SLUG".md 2>/dev/null | sort | tail -n 1 || true)"
  [ -n "$HANDOFF" ] || { echo "error: no handoff found for slug '$SLUG' in handoffs/" >&2; exit 1; }
fi

SPEC="specs/$SLUG.md"
[ -f "$SPEC" ]    || { echo "error: spec not found: $SPEC" >&2; exit 1; }
[ -f "$HANDOFF" ] || { echo "error: handoff not found: $HANDOFF" >&2; exit 1; }
[ -n "$TEST_CMD" ] || { echo "error: TEST_CMD not set. copy factory.env.example to factory.env" >&2; exit 1; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="handoffs/logs-$TS-$SLUG.txt"
mkdir -p handoffs

# caveman: agy does not use shell cwd as workspace. give it absolute paths
# and --add-dir, or it goes hunting across the whole disk and finds nothing.
SPEC_ABS="$REPO_ROOT/$SPEC"
HANDOFF_ABS="$REPO_ROOT/$HANDOFF"

# caveman: one prompt. tell agy read spec, change code, run test.
PROMPT="$(cat <<PROMPT_END
You are the build agent for the repo at:
  $REPO_ROOT

Your terminal does NOT start in that repo - it starts in a scratch directory.
So every terminal command you run must cd there first, like this:
  cd $REPO_ROOT && <your command>

All file paths below are absolute and already exist. Read them directly. Do
not search the filesystem for them - if a read fails, cd to the repo and use
ls, do not go hunting elsewhere.

Read these two files first, in full:
  $SPEC_ABS
  $HANDOFF_ABS

The handoff is the contract. Do exactly this:
1. Change the code so every item under "Done criteria" in the handoff is true.
2. Touch the files listed under "Files to touch". Touch other files only if
   the change genuinely requires it, and say which ones and why.
3. Run the tests with this exact command:
     cd $REPO_ROOT && $TEST_CMD
4. If tests fail, fix the code and run them again. Repeat until they pass or
   you are blocked.
5. Do not commit. Do not push. Do not create branches. Leave changes in the
   working tree.
6. Do not edit anything under specs/ or handoffs/ - those belong to the
   review agent.

End your reply with a short report in this exact shape:

RESULT: PASS or FAIL
TESTS: the last line of test output
CHANGED: one line per file you changed
BLOCKED: anything you could not do, or "none"
PROMPT_END
)"

echo "repo:    $REPO_ROOT"
echo "slug:    $SLUG"
echo "spec:    $SPEC"
echo "handoff: $HANDOFF"
echo "model:   $AGY_MODEL"
echo "tests:   $TEST_CMD"
echo "log:     $LOG"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- prompt ---"
  printf '%s\n' "$PROMPT"
  echo "--- command ---"
  echo "agy --print <prompt> --add-dir $REPO_ROOT --model $AGY_MODEL --print-timeout $AGY_TIMEOUT --dangerously-skip-permissions"
  exit 0
fi

command -v agy >/dev/null 2>&1 || { echo "error: 'agy' not on PATH" >&2; exit 1; }

# caveman: header in log so review agent knows what ran.
{
  echo "=== antigravity run ==="
  echo "timestamp: $TS"
  echo "slug:      $SLUG"
  echo "spec:      $SPEC"
  echo "handoff:   $HANDOFF"
  echo "model:     $AGY_MODEL"
  echo "test_cmd:  $TEST_CMD"
  echo "git_head:  $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "======================="
  echo
} > "$LOG"

set +e
agy --print "$PROMPT" \
    --add-dir "$REPO_ROOT" \
    --model "$AGY_MODEL" \
    --print-timeout "$AGY_TIMEOUT" \
    --dangerously-skip-permissions 2>&1 | tee -a "$LOG"
AGY_EXIT="${PIPESTATUS[0]}"
set -e

{
  echo
  echo "=== agy exit code: $AGY_EXIT ==="
} >> "$LOG"

echo
echo "agy exit code: $AGY_EXIT"
echo "log saved: $LOG"
echo "next: run /factory-check $SLUG in Claude Code"
exit "$AGY_EXIT"
