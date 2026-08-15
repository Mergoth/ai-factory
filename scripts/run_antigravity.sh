#!/usr/bin/env bash
# caveman: take slug. find spec + handoff. tell agy do work. save log.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/run_antigravity.sh <slug|handoff-path> [--model M] [--dry-run]

  <slug>          slug of spec. script finds specs/<slug>.md and newest
                  handoffs/<timestamp>-<slug>.md
  <handoff-path>  path to a handoff file. slug read from filename.
  --model M         use model M. must exist in `agy models`.
  --refresh-models  re-fetch the model list, ignoring the cache.
  --dry-run         print the prompt and the agy command, call nothing.

config comes from factory.env in repo root (see factory.env.example).
no model ids are configured - the list comes from `agy models`, cached in
.factory-cache/. if agy fails to run, the script falls back to other models,
preferring a different family.
per-project context in factory/ (context.md, memory.md, adr/, prompt-extra.md)
is passed to the build agent when those files are filled in.
log goes to handoffs/logs-<timestamp>-<slug>.txt
USAGE
}

[ $# -ge 1 ] || { usage; exit 2; }
[ "$1" = "-h" ] || [ "$1" = "--help" ] && { usage; exit 0; }

TARGET="$1"; shift
DRY_RUN=0
MODEL_OVERRIDE=""
REFRESH_MODELS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)        DRY_RUN=1 ;;
    --refresh-models) REFRESH_MODELS=1 ;;
    --model)   shift; MODEL_OVERRIDE="${1:-}"
               [ -n "$MODEL_OVERRIDE" ] || { echo "--model needs a value" >&2; exit 2; } ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

# caveman: work from repo root. all paths relative to it.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

# caveman: config. no model ids live here - they rotate. ask agy instead.
TEST_CMD=""
AGY_TIMEOUT="30m"
AGY_FALLBACKS="2"            # how many other models to try if agy breaks.
MODELS_TTL_MIN="720"         # how long the cached model list stays fresh.
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

# caveman: project brain. factory/ is yours, factory-engine/ is the harness.
# only mention files that exist, or agy goes looking for ghosts. a file still
# carrying the template marker is not filled in yet - feeding agy blank
# headings is worse than saying nothing.
CONTEXT_BLOCK=""
add_context() { # add_context <abs-path> <why>
  [ -s "$1" ] || return 0
  if grep -q 'factory:template' "$1" 2>/dev/null; then
    echo "note: $(basename "$1") is still the blank template, not sent to agy" >&2
    return 0
  fi
  CONTEXT_BLOCK="$CONTEXT_BLOCK
  $1
      $2"
}
add_context "$REPO_ROOT/factory/context.md" "how this project is built. follow it."
add_context "$REPO_ROOT/factory/memory.md"  "lessons from past runs. do not repeat those mistakes."

ADR_DIR="$REPO_ROOT/factory/adr"
if [ -d "$ADR_DIR" ] && [ -n "$(ls -A "$ADR_DIR" 2>/dev/null)" ]; then
  CONTEXT_BLOCK="$CONTEXT_BLOCK
  $ADR_DIR/
      architecture decisions. binding. if the task needs you to break one,
      stop and say so instead of breaking it quietly."
fi

if [ -n "$CONTEXT_BLOCK" ]; then
  CONTEXT_BLOCK="

Project context - read all of these before you touch code:$CONTEXT_BLOCK"
fi

# caveman: raw per-project orders, pasted in as-is. skip blank template.
EXTRA=""
if [ -s "$REPO_ROOT/factory/prompt-extra.md" ] &&
   ! grep -q 'factory:template' "$REPO_ROOT/factory/prompt-extra.md"; then
  EXTRA="

Extra rules for this project:
$(cat "$REPO_ROOT/factory/prompt-extra.md")"
fi

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
$CONTEXT_BLOCK

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
LEARNED: one line worth remembering next time, or "none"$EXTRA
PROMPT_END
)"

command -v agy >/dev/null 2>&1 || { echo "error: 'agy' not on PATH" >&2; exit 1; }

# caveman: ask agy what models exist today. ids rotate, never hardcode them.
# the fetch is slow (network), so cache it. --refresh-models to force.
CACHE_DIR="$REPO_ROOT/.factory-cache"
CACHE="$CACHE_DIR/models.txt"
mkdir -p "$CACHE_DIR"

if [ "$REFRESH_MODELS" -eq 1 ] || [ -z "$(find "$CACHE" -mmin "-$MODELS_TTL_MIN" 2>/dev/null)" ]; then
  echo "fetching model list from agy..."
  if agy models 2>/dev/null | awk -F'\t' 'NF>1 {print $1}' > "$CACHE.tmp" && [ -s "$CACHE.tmp" ]; then
    mv "$CACHE.tmp" "$CACHE"
  else
    rm -f "$CACHE.tmp"
    [ -s "$CACHE" ] && echo "warn: model fetch failed, using cached list" >&2
  fi
fi

KNOWN="$(cat "$CACHE" 2>/dev/null || true)"
[ -n "$KNOWN" ] || { echo "error: could not read 'agy models'. is agy logged in?" >&2; exit 1; }

# caveman: chosen model first, then others from the live list as fallbacks.
# fallbacks are for agy breaking, so any working model beats no run at all.
TRY=""
if [ -n "$MODEL_OVERRIDE" ]; then
  if printf '%s\n' "$KNOWN" | grep -qxF "$MODEL_OVERRIDE"; then
    TRY="$MODEL_OVERRIDE"
  else
    echo "warn: model '$MODEL_OVERRIDE' not in 'agy models', ignoring it" >&2
    echo "      available today:" >&2
    printf '%s\n' "$KNOWN" | sed 's/^/        /' >&2
  fi
fi

# caveman: no choice given -> first model agy lists. newest, top tier.
[ -n "$TRY" ] || TRY="$(printf '%s\n' "$KNOWN" | head -n 1)"

# caveman: fallbacks from OTHER families first. three flavours of one family
# all die together when that family is down.
family() { printf '%s\n' "${1%%-*}"; }

FAMS="$(family "${TRY%% *}")"
n=0
for pass in other any; do
  for m in $KNOWN; do
    [ "$n" -ge "$AGY_FALLBACKS" ] && break
    case " $TRY " in *" $m "*) continue ;; esac
    f="$(family "$m")"
    if [ "$pass" = "other" ]; then
      case " $FAMS " in *" $f "*) continue ;; esac
    fi
    TRY="$TRY $m"
    FAMS="$FAMS $f"
    n=$((n+1))
  done
done

echo "repo:    $REPO_ROOT"
echo "slug:    $SLUG"
echo "spec:    $SPEC"
echo "handoff: $HANDOFF"
echo "models:  $TRY"
echo "tests:   $TEST_CMD"
echo "log:     $LOG"
echo

FIRST="${TRY%% *}"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- prompt ---"
  printf '%s\n' "$PROMPT"
  echo "--- command ---"
  echo "agy --print <prompt> --add-dir $REPO_ROOT --model $FIRST --print-timeout $AGY_TIMEOUT --dangerously-skip-permissions"
  exit 0
fi

# caveman: header in log so review agent knows what ran.
{
  echo "=== antigravity run ==="
  echo "timestamp: $TS"
  echo "slug:      $SLUG"
  echo "spec:      $SPEC"
  echo "handoff:   $HANDOFF"
  echo "models:    $TRY"
  echo "test_cmd:  $TEST_CMD"
  echo "git_head:  $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "======================="
  echo
} > "$LOG"

# caveman: try each model. nonzero exit = agy itself broke, try next one.
# zero exit = agy ran and reported. tests may still fail - that is the build
# agent's problem, not the model's, so do NOT fall through on it.
AGY_EXIT=1
USED=""
for m in $TRY; do
  echo ">>> model: $m"
  echo "=== attempt with model: $m ===" >> "$LOG"
  set +e
  agy --print "$PROMPT" \
      --add-dir "$REPO_ROOT" \
      --model "$m" \
      --print-timeout "$AGY_TIMEOUT" \
      --dangerously-skip-permissions 2>&1 | tee -a "$LOG"
  AGY_EXIT="${PIPESTATUS[0]}"
  set -e
  USED="$m"
  if [ "$AGY_EXIT" -eq 0 ]; then
    break
  fi
  echo "warn: agy failed with '$m' (exit $AGY_EXIT), trying next model" >&2
  echo "=== model $m failed, exit $AGY_EXIT ===" >> "$LOG"
done

{
  echo
  echo "=== model used: $USED ==="
  echo "=== agy exit code: $AGY_EXIT ==="
} >> "$LOG"

echo
echo "model used: $USED"
echo "agy exit code: $AGY_EXIT"
echo "log saved: $LOG"
if [ "$AGY_EXIT" -ne 0 ]; then
  echo "error: every model in the chain failed to run" >&2
  exit "$AGY_EXIT"
fi
echo "next: run /factory-check $SLUG in Claude Code"
