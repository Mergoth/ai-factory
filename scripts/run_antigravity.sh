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
  --no-lint         skip the handoff shape check. you are on your own.
  --no-snapshot     skip the pre-round snapshot of uncommitted work.
  --force           run even if a lock says a round is already in flight.

config comes from factory.env in repo root (see factory.env.example).
no model ids are configured - the list comes from `agy models`, cached in
.factory-cache/. if agy fails to run, the script falls back to other models,
preferring a different family.
per-project context in factory/ (context.md, memory.md, adr/, prompt-extra.md,
briefs/<slug>.md) is passed to the build agent when those files are filled in.
log goes to handoffs/logs-<timestamp>-<slug>.txt

before each round it checks the handoff's shape, snapshots every uncommitted
change to .factory-cache/snapshots/, and takes a lock so two rounds cannot run
at once. after a crash, `scripts/factory_state.sh <slug>` says where it stopped.
USAGE
}

[ $# -ge 1 ] || { usage; exit 2; }
[ "$1" = "-h" ] || [ "$1" = "--help" ] && { usage; exit 0; }

TARGET="$1"; shift
DRY_RUN=0
MODEL_OVERRIDE=""
REFRESH_MODELS=0
NO_LINT=0
NO_SNAPSHOT=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)        DRY_RUN=1 ;;
    --no-lint)        NO_LINT=1 ;;
    --no-snapshot)    NO_SNAPSHOT=1 ;;
    --force)          FORCE=1 ;;
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

# caveman: TEST_CMD that does not exist burns a whole paid round on
# "command not found". check the runner is there before calling agy. only when
# the first word is a plain command - anything with env prefixes, pipes or
# shell syntax is left alone rather than guessed at.
TEST_BIN="${TEST_CMD%% *}"
case "$TEST_CMD" in
  *'='*|*'|'*|*'&'*|*';'*|*'('*|*'$'*) ;;   # shell syntax, cannot check it
  *)
    command -v "$TEST_BIN" >/dev/null 2>&1 || {
      echo "error: TEST_CMD starts with '$TEST_BIN', which is not on PATH." >&2
      echo "       fix TEST_CMD in factory.env before spending a round on it." >&2
      exit 1; }
    ;;
esac

# caveman: check the contract's shape before paying for a round against it. a
# handoff with no done criteria buys nothing, and finding that out costs the
# whole round. deterministic, free, and it runs before every call to agy.
LINT="$(dirname "$0")/factory_lint.sh"
if [ "$NO_LINT" -eq 0 ] && [ -x "$LINT" ]; then
  if ! "$LINT" "$SLUG" --contract --quiet; then
    echo >&2
    echo "error: the handoff for '$SLUG' does not hold up. fix it before spending a round." >&2
    echo "       re-check with: bash scripts/factory_lint.sh $SLUG" >&2
    echo "       override with: --no-lint" >&2
    exit 1
  fi
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p handoffs
LOG="handoffs/logs-$TS-$SLUG.txt"
# caveman: the logs ARE the round counter. two rounds in one second would share
# a filename, and the second would eat the first - that is a round nobody can
# see afterwards. wait out the collision rather than renaming: everything else
# finds the newest log by sorting these names.
while [ -e "$LOG" ]; do
  sleep 1
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG="handoffs/logs-$TS-$SLUG.txt"
done

# caveman: agy does not use shell cwd as workspace. give it absolute paths
# and --add-dir, or it goes hunting across the whole disk and finds nothing.
SPEC_ABS="$REPO_ROOT/$SPEC"
HANDOFF_ABS="$REPO_ROOT/$HANDOFF"

# caveman: project brain. factory/ is yours, factory-engine/ is the harness.
# only mention files that exist, or agy goes looking for ghosts. a file still
# carrying the template marker is not filled in yet - feeding agy blank
# headings is worse than saying nothing.
#
# marker is only honoured on LINE 1, where install.sh puts it. matching it
# anywhere made a filled-in file that merely mentions the marker drop itself,
# silently, and the builder then re-decided every convention from scratch.
is_template() { # is_template <abs-path>
  case "$(head -n 1 "$1" 2>/dev/null)" in
    *factory:template*) return 0 ;;
    *) return 1 ;;
  esac
}

CONTEXT_BLOCK=""
add_context() { # add_context <abs-path> <why>
  [ -s "$1" ] || return 0
  if is_template "$1"; then
    # loud, and on stdout: a dropped context file is invisible in the log and
    # costs a whole round of the builder re-inventing this project's rules.
    echo "WARNING: ${1#"$REPO_ROOT"/} still has the factory:template marker on line 1."
    echo "         it was NOT sent to agy. delete that line once you have filled it in."
    return 0
  fi
  CONTEXT_BLOCK="$CONTEXT_BLOCK
  $1
      $2"
}
add_context "$REPO_ROOT/factory/context.md" "how this project is built. follow it."
add_context "$REPO_ROOT/factory/memory.md"  "lessons from past runs. do not repeat those mistakes."
add_context "$REPO_ROOT/factory/briefs/$SLUG.md" "why this is being built, and what was already rejected. do not re-propose a rejected option."

# caveman: only real ADRs count. a dir holding just .gitkeep is not decisions,
# and telling agy "binding architecture" about nothing is a lie it will act on.
ADR_DIR="$REPO_ROOT/factory/adr"
if [ -d "$ADR_DIR" ] && [ -n "$(find "$ADR_DIR" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then
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
   ! is_template "$REPO_ROOT/factory/prompt-extra.md"; then
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

End your reply with a report in this exact shape:

RESULT: PASS or FAIL
TESTS: the last line of test output
CHANGED: one line per file you changed
BLOCKED: anything you could not do, or "none"
LEARNED: one line worth remembering next time, or "none"
WALKTHROUGH:
  how it works: the flow after your change, in order, 3-8 lines. name the real
    functions and files a reader would open.
  why: each choice a reviewer would question, and your reason. include what you
    considered and did not do.
  verify by hand: exact commands a human runs to watch it work. not the test
    suite - something they can see.
  not covered: what you did not test, and what you are unsure about.

The walkthrough is checked against the actual diff. Describe only what you really
changed - an accurate "I could not finish X" beats a confident description of
code that is not there.$EXTRA
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

# caveman: one round per slug at a time. two agy processes editing one tree is
# how a good round gets eaten by a bad one, and a resumed agent cannot tell
# afterwards which write came from where.
LOCK_DIR="$CACHE_DIR/locks"
LOCK="$LOCK_DIR/$SLUG.lock"
mkdir -p "$LOCK_DIR"
if [ -f "$LOCK" ]; then
  LPID="$(sed -n 's/^pid=//p' "$LOCK" | head -n 1)"
  if [ -n "$LPID" ] && kill -0 "$LPID" 2>/dev/null && [ "$FORCE" -eq 0 ]; then
    echo "error: a round for '$SLUG' is already running (pid $LPID)." >&2
    echo "       wait for it, or override with --force if you know it is dead." >&2
    exit 1
  fi
  echo "note: clearing a stale lock from pid ${LPID:-?} - that round died before it finished"
  rm -f "$LOCK"
fi
printf 'pid=%s\nstarted=%s\nslug=%s\nlog=%s\n' "$$" "$TS" "$SLUG" "$LOG" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT INT TERM

# caveman: uncommitted work is the only copy there is. take one before letting
# agy loose, so a bad round can be undone without losing a good one. tracked
# changes AND untracked new files - on a greenfield repo the new files ARE the
# work. ignored files stay out, that is what --exclude-standard means.
SNAP_DIR="$CACHE_DIR/snapshots"
SNAPSHOT=""
if [ "$NO_SNAPSHOT" -eq 0 ]; then
  mkdir -p "$SNAP_DIR"
  # a deleted tracked file is "modified" to git but not tarrable - drop those.
  SNAP_LIST="$SNAP_DIR/.filelist-$SLUG"
  git ls-files -mo --exclude-standard 2>/dev/null | while IFS= read -r p; do
    [ -f "$p" ] && printf '%s\n' "$p"
  done > "$SNAP_LIST" || true
  SNAP_N="$(grep -c . "$SNAP_LIST" || true)"
  if [ "${SNAP_N:-0}" -eq 0 ]; then
    echo "snapshot: nothing uncommitted to save"
    rm -f "$SNAP_LIST"
  elif [ "${SNAP_N:-0}" -gt 2000 ]; then
    echo "warn: $SNAP_N uncommitted files, too many to snapshot. commit or clean first." >&2
    rm -f "$SNAP_LIST"
  else
    SNAPSHOT="$SNAP_DIR/$TS-$SLUG.tar.gz"
    tar czf "$SNAPSHOT" -T "$SNAP_LIST" 2>/dev/null || {
      rm -f "$SNAPSHOT"; SNAPSHOT=""; echo "warn: snapshot failed, continuing without one" >&2; }
    rm -f "$SNAP_LIST"
    [ -z "$SNAPSHOT" ] || echo "snapshot: $SNAP_N file(s) -> $SNAPSHOT"
    # keep the last 10 per slug. recovery data, not an archive.
    (ls -1t "$SNAP_DIR"/*-"$SLUG".tar.gz 2>/dev/null | tail -n +11 | while IFS= read -r old; do
      rm -f "$old"
    done) || true
  fi
fi

# caveman: header in log so review agent knows what ran. round number counts
# the logs on disk, so a fresh agent that lost its memory counts the same round
# an old one was counting.
ROUND=$(( $(ls -1 handoffs/logs-*-"$SLUG".txt 2>/dev/null | wc -l | tr -d ' ' || true) + 1 ))
{
  echo "=== antigravity run ==="
  echo "timestamp: $TS"
  echo "slug:      $SLUG"
  echo "round:     $ROUND"
  echo "spec:      $SPEC"
  echo "handoff:   $HANDOFF"
  echo "models:    $TRY"
  echo "test_cmd:  $TEST_CMD"
  echo "git_head:  $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  echo "snapshot:  ${SNAPSHOT:-none}"
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
echo "round: $ROUND"
echo "model used: $USED"
echo "agy exit code: $AGY_EXIT"
echo "log saved: $LOG"
[ -z "$SNAPSHOT" ] || echo "pre-round snapshot: $SNAPSHOT"
if [ "$AGY_EXIT" -ne 0 ]; then
  echo "error: every model in the chain failed to run" >&2
  echo "       nothing was built. state: bash scripts/factory_state.sh $SLUG" >&2
  exit "$AGY_EXIT"
fi
echo "next: run /factory-check $SLUG in Claude Code"
echo "      lost the thread? bash scripts/factory_state.sh $SLUG"
