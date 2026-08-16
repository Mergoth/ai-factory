#!/usr/bin/env bash
# caveman: where did the run stop, and what happens next. read from files only.
# nothing here lives in an agent's head, so any agent can pick the run back up.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/factory_state.sh [slug] [--next] [--all]

  <slug>   report on one slug. default: the slug of the newest handoff.
  --next   print only the next action word, for scripting.
  --all    one summary line per slug that has a handoff.

reconstructs the state of a run from the files on disk: how many agy rounds
have been logged, how many were checked, which model ran, whether the last log
is complete, whether a round is running right now, and what the last verdict
was. Then it says what to do next.

next action is one of:
  spec    no handoff exists yet          -> /factory-spec <request>
  fix     the handoff is malformed       -> scripts/factory_lint.sh <slug>
  wait    an agy round is running now    -> do not start a second one
  build   a round is owed                -> scripts/run_antigravity.sh <slug>
  check   a round ran but was not judged -> /factory-check <slug>
  cap     MAX_ROUNDS used, still failing -> a human decides
  done    last check said Success        -> nothing to do

nothing here calls a model, changes a file, or costs anything. safe to run at
any time, including while agy is running.
USAGE
}

SLUG=""
NEXT_ONLY=0
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --next)    NEXT_ONLY=1 ;;
    --all)     ALL=1 ;;
    -*)        echo "unknown arg: $1" >&2; usage; exit 2 ;;
    *)         SLUG="$1" ;;
  esac
  shift
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

MAX_ROUNDS="3"
TEST_CMD=""
# shellcheck source=/dev/null
[ -f factory.env ] && . ./factory.env

LOCK_DIR="$REPO_ROOT/.factory-cache/locks"
SNAP_DIR="$REPO_ROOT/.factory-cache/snapshots"

state_of() { # state_of <slug>; sets the globals below
  SL="$1"
  HANDOFF="$(ls -1 handoffs/*-"$SL".md 2>/dev/null | sort | tail -n 1 || true)"
  # ls fails on a glob with no match, and pipefail turns that into an exit.
  ROUNDS="$(ls -1 handoffs/logs-*-"$SL".txt 2>/dev/null | wc -l | tr -d ' ' || true)"
  LAST_LOG="$(ls -1 handoffs/logs-*-"$SL".txt 2>/dev/null | sort | tail -n 1 || true)"
  CHECKS=0
  LAST_STATUS="none"
  LAST_TESTS=""
  if [ -n "$HANDOFF" ]; then
    CHECKS="$(grep -c '^## Check' "$HANDOFF" || true)"
    LAST_STATUS="$(grep '^Status:' "$HANDOFF" | tail -n 1 | sed 's/^Status: *//' || true)"
    LAST_TESTS="$(grep '^Tests:' "$HANDOFF" | tail -n 1 | sed 's/^Tests: *//' || true)"
    [ -n "$LAST_STATUS" ] || LAST_STATUS="none"
  fi

  MODEL=""; EXITCODE=""; LOG_STATE="none"
  if [ -n "$LAST_LOG" ]; then
    MODEL="$(sed -n 's/^=== model used: \(.*\) ===/\1/p' "$LAST_LOG" | tail -n 1)"
    EXITCODE="$(sed -n 's/^=== agy exit code: \([0-9]*\) ===/\1/p' "$LAST_LOG" | tail -n 1)"
    if [ -z "$EXITCODE" ]; then
      LOG_STATE="killed mid-round (no exit footer)"
    elif ! grep -q 'RESULT:' "$LAST_LOG"; then
      LOG_STATE="truncated (no RESULT: block)"
    elif ! grep -q 'WALKTHROUGH:' "$LAST_LOG"; then
      LOG_STATE="complete, no walkthrough"
    else
      LOG_STATE="complete"
    fi
  fi

  # caveman: a lock whose pid is gone means the round died. that is a finished
  # round with an unfinished log, not a running one - and the difference is the
  # whole point of asking before spending money again.
  LOCK="$LOCK_DIR/$SL.lock"
  RUNNING=0; LOCK_INFO=""
  if [ -f "$LOCK" ]; then
    LPID="$(sed -n 's/^pid=//p' "$LOCK" | head -n 1)"
    LSTART="$(sed -n 's/^started=//p' "$LOCK" | head -n 1)"
    if [ -n "$LPID" ] && kill -0 "$LPID" 2>/dev/null; then
      RUNNING=1
      LOCK_INFO="yes (pid $LPID, started $LSTART)"
    else
      LOCK_INFO="no - stale lock from pid ${LPID:-?} started $LSTART; that round died"
    fi
  else
    LOCK_INFO="no"
  fi

  SNAP="$(ls -1 "$SNAP_DIR"/*-"$SL".tar.gz 2>/dev/null | sort | tail -n 1 || true)"

  # caveman: the state machine. rounds and checks both come off the disk, so a
  # fresh agent counts the same round cap a dead one was counting.
  if [ -z "$HANDOFF" ]; then                       NEXT="spec"
  elif [ "$RUNNING" -eq 1 ]; then                  NEXT="wait"
  elif [ -x "$REPO_ROOT/scripts/factory_lint.sh" ] &&
       ! "$REPO_ROOT/scripts/factory_lint.sh" "$SL" --contract --quiet >/dev/null 2>&1; then
                                                   NEXT="fix"
  elif [ "$ROUNDS" -eq 0 ]; then                   NEXT="build"
  elif [ "$ROUNDS" -gt "$CHECKS" ]; then           NEXT="check"
  elif [ "$LAST_STATUS" = "Success" ]; then        NEXT="done"
  elif [ "$ROUNDS" -ge "$MAX_ROUNDS" ]; then       NEXT="cap"
  else                                             NEXT="build"
  fi
}

resume_cmd() { # resume_cmd <slug> <next>
  case "$2" in
    spec)  echo "/factory-spec <what you want built>" ;;
    fix)   echo "bash scripts/factory_lint.sh $1   # then fix the handoff, do not run agy on it" ;;
    wait)  echo "nothing. an agy round is running - starting a second one double-spends and races the diff" ;;
    build) echo "bash scripts/run_antigravity.sh $1 --model <id from agy models>" ;;
    check) echo "/factory-check $1" ;;
    cap)   echo "nothing automatic. MAX_ROUNDS=$MAX_ROUNDS used and it is still failing - a human decides" ;;
    done)  echo "/factory-reflect $1   # the run is over; the last thing it owes you is a lesson" ;;
  esac
}

report_one() { # report_one <slug>
  state_of "$1"
  printf 'slug:         %s\n' "$SL"
  printf 'handoff:      %s\n' "${HANDOFF:-none}"
  printf 'rounds_run:   %s (max %s)\n' "$ROUNDS" "$MAX_ROUNDS"
  printf 'rounds_check: %s\n' "$CHECKS"
  printf 'running:      %s\n' "$LOCK_INFO"
  printf 'last_log:     %s\n' "${LAST_LOG:-none}"
  printf 'log_state:    %s\n' "$LOG_STATE"
  printf 'last_model:   %s\n' "${MODEL:-none}"
  printf 'agy_exit:     %s\n' "${EXITCODE:-none}"
  printf 'last_status:  %s\n' "$LAST_STATUS"
  printf 'last_tests:   %s\n' "${LAST_TESTS:-none}"
  printf 'tree:         %s file(s) changed since HEAD\n' \
    "$(git status --short 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ -n "$SNAP" ]; then
    printf 'snapshot:     %s\n' "$SNAP"
    printf 'restore:      tar xzf %s -C %s\n' "$SNAP" "$REPO_ROOT"
  else
    printf 'snapshot:     none\n'
  fi
  printf 'next:         %s\n' "$NEXT"
  printf 'resume:       %s\n' "$(resume_cmd "$SL" "$NEXT")"
}

if [ "$ALL" -eq 1 ]; then
  SLUGS="$(ls -1 handoffs/*.md 2>/dev/null | sed -e 's|.*/||' -e 's|\.md$||' -e 's|^[0-9TZ]*-||' | sort -u || true)"
  [ -n "$SLUGS" ] || { echo "no handoffs found in handoffs/"; exit 0; }
  for s in $SLUGS; do
    state_of "$s"
    printf '%-28s rounds %s/%s  checks %s  %-10s -> %s\n' \
      "$s" "$ROUNDS" "$MAX_ROUNDS" "$CHECKS" "$LAST_STATUS" "$NEXT"
  done
  exit 0
fi

if [ -z "$SLUG" ]; then
  newest="$(ls -1 handoffs/*.md 2>/dev/null | sort | tail -n 1 || true)"
  if [ -z "$newest" ]; then
    if [ "$NEXT_ONLY" -eq 1 ]; then echo "spec"; else
      echo "no handoffs found in handoffs/"
      echo "next:         spec"
      echo "resume:       /factory-spec <what you want built>"
    fi
    exit 0
  fi
  base="$(basename "$newest" .md)"
  SLUG="${base#*-}"
fi

if [ "$NEXT_ONLY" -eq 1 ]; then
  state_of "$SLUG"
  echo "$NEXT"
else
  report_one "$SLUG"
fi
