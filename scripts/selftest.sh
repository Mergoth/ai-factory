#!/usr/bin/env bash
# caveman: prove the harness still works. builds throwaway repos, fakes agy,
# runs the real scripts against them. no network, no model, no money.
#
# this is the engine's own TEST_CMD. every bug found in the harness should
# arrive here as a case before it is fixed anywhere else.
#
# NOT set -e: a failed assertion must report and continue, not kill the run.
set -uo pipefail

usage() {
  cat <<'USAGE'
usage: bash scripts/selftest.sh [--keep] [--only <pattern>]

  --keep          leave the sandbox repos on disk and print where they are
  --only <pat>    run only groups whose name matches <pat>

builds temporary git repos under $TMPDIR, installs this harness into them,
puts a fake `agy` on PATH, and drives the real scripts. touches nothing
outside the sandbox.

exit 0 = all passed, 1 = something failed.
USAGE
}

KEEP=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --keep)    KEEP=1 ;;
    --only)    shift; ONLY="${1:-}" ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

ENGINE="$(cd "$(dirname "$0")/.." && pwd)"
# caveman: resolve the sandbox path the same way git does - through symlinks and
# without double slashes - or every assertion about a path in the prompt misses.
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/factory-selftest.XXXXXX")" && pwd -P)"
cleanup() {
  if [ "$KEEP" -eq 1 ]; then echo; echo "sandbox kept: $WORK"
  else rm -rf "$WORK"; fi
}
trap cleanup EXIT

PASS=0
FAIL=0
CURRENT=""
LAST_OUT=""
LAST_RC=0

group() {
  case "$1" in
    *"$ONLY"*) GROUP_ON=1; echo; echo "=== $1" ;;
    *)         GROUP_ON=0 ;;
  esac
}
GROUP_ON=1

t()    { CURRENT="$1"; }
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$CURRENT"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$CURRENT"
         printf '        %s\n' "$1"
         [ -z "${2:-}" ] || printf '        --- output ---\n%s\n' "$(printf '%s' "$2" | sed 's/^/        /')"; }

run() { # run <dir> <cmd...>  - captures stdout+stderr and exit code
  local d="$1"; shift
  LAST_OUT="$(cd "$d" && PATH="$d/bin:$PATH" "$@" 2>&1)"
  LAST_RC=$?
}

rc_is()   { [ "$LAST_RC" = "$1" ] && ok || bad "exit was $LAST_RC, wanted $1" "$LAST_OUT"; }
rc_not()  { [ "$LAST_RC" != "$1" ] && ok || bad "exit was $LAST_RC, wanted anything else" "$LAST_OUT"; }
has()     { case "$LAST_OUT" in *"$1"*) ok ;; *) bad "output does not contain '$1'" "$LAST_OUT" ;; esac; }
lacks()   { case "$LAST_OUT" in *"$1"*) bad "output should not contain '$1'" "$LAST_OUT" ;; *) ok ;; esac; }
is()      { [ "$1" = "$2" ] && ok || bad "got '$1', wanted '$2'"; }
exists()  { [ -e "$1" ] && ok || bad "missing file: $1"; }
absent()  { [ ! -e "$1" ] && ok || bad "file should not exist: $1"; }
counts()  { local n; n="$(ls -1d $1 2>/dev/null | wc -l | tr -d ' ' || true)"; [ "$n" = "$2" ] && ok || bad "found $n of '$1', wanted $2"; }

# caveman: fake agy. answers `models`, otherwise writes a file and reports.
# modes come from the environment so a test can ask for a bad round.
make_agy() { # make_agy <repo>
  mkdir -p "$1/bin"
  cat > "$1/bin/agy" <<'FAKE'
#!/bin/sh
if [ "$1" = "models" ]; then printf 'model-a\tflash\nmodel-b\tpro\n'; exit 0; fi
prev=""; repo=""; model=""
for a in "$@"; do
  case "$prev" in --add-dir) repo="$a" ;; --model) model="$a" ;; esac
  prev="$a"
done
if [ -n "${FAKE_FAIL_MODEL:-}" ] && [ "$model" = "$FAKE_FAIL_MODEL" ]; then
  echo "boom: $model is unavailable"; exit 1
fi
case "${FAKE_MODE:-ok}" in
  allfail)
    echo "boom: everything is down"; exit 1 ;;
  truncated)
    echo "I will start by reading the spec and then I wi"
    exit 0 ;;
  noop)
    echo "RESULT: PASS"; echo "TESTS: nothing to do"; echo "WALKTHROUGH:"; echo "  how it works: unchanged"
    exit 0 ;;
  *)
    mkdir -p "$repo/src"
    echo "print('hi')" > "$repo/src/app.py"
    echo "RESULT: PASS"
    echo "TESTS: 1 passed"
    echo "CHANGED: src/app.py"
    echo "BLOCKED: none"
    echo "LEARNED: none"
    echo "WALKTHROUGH:"
    echo "  how it works: src/app.py prints"
    echo "  verify by hand: python src/app.py"
    exit 0 ;;
esac
FAKE
  chmod +x "$1/bin/agy"
}

write_spec() { # write_spec <repo> <slug>
  cat > "$1/specs/$2.md" <<EOF
# $2

## Problem
something is missing.

## Solution
add it.

## Scope
In:
- the thing
EOF
}

write_handoff() { # write_handoff <repo> <slug> [difficulty]
  cat > "$1/handoffs/20260816T090000Z-$2.md" <<EOF
# Handoff: $2

## Goal

The thing exists.

Difficulty: ${3:-normal}

## Files to touch

- \`src/app.py\` - NEW, the app

## Tests to run

\`\`\`
true
\`\`\`

## Done criteria

- [ ] src/app.py exists
EOF
}

append_check() { # append_check <repo> <slug> <status> <n>
  local f="$1/handoffs/20260816T090000Z-$2.md"
  printf '\n## Check 2026081%sT120000Z\n\nStatus: %s\nTests: 1 passed (1 tests, was 0 last round)\n\n- a bullet\n' \
    "$4" "$3" >> "$f"
  [ "$3" = "Needs fix" ] && printf '\n### Next fix\n- do the thing\n' >> "$f"
  return 0
}

new_repo() { # new_repo <name> -> path on stdout
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name t )
  bash "$ENGINE/install.sh" "$d" >/dev/null 2>&1
  printf 'TEST_CMD="true"\nMAX_ROUNDS="2"\n' > "$d/factory.env"
  make_agy "$d"
  write_spec "$d" feat
  write_handoff "$d" feat
  printf 'seed\n' > "$d/seed.txt"
  ( cd "$d" && git add -A && git commit -qm init >/dev/null 2>&1 )
  echo "$d"
}

strip_line() { # strip_line <file> <sed-pattern>  - portable on BSD and GNU
  sed -i.bak "/$2/d" "$1" && rm -f "$1.bak"
}

state_next() { # state_next <repo> <slug>
  (cd "$1" && PATH="$1/bin:$PATH" bash scripts/factory_state.sh "$2" --next 2>/dev/null)
}

echo "harness:  $ENGINE"
echo "sandbox:  $WORK"

# ---------------------------------------------------------------- install
group "install"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo install)"

  t "links all five Claude skills"
  counts "$R/.claude/skills/factory-*" 5

  t "links the three scripts"
  counts "$R/scripts/factory_*.sh" 2
  t "links the runner"
  exists "$R/scripts/run_antigravity.sh"

  t "seeds the project brain"
  exists "$R/factory/improvements.md"
  t "seeds memory"
  exists "$R/factory/memory.md"
  t "creates work dirs"
  exists "$R/handoffs/.gitkeep"

  t "gitignores logs"
  run "$R" grep -qxF "handoffs/logs-*.txt" .gitignore
  rc_is 0

  t "second install keeps factory.env"
  printf 'TEST_CMD="mine"\n' > "$R/factory.env"
  run "$R" bash "$ENGINE/install.sh" .
  run "$R" grep -qxF 'TEST_CMD="mine"' factory.env
  rc_is 0

  t "refuses to install into the harness itself"
  run "$ENGINE" bash "$ENGINE/install.sh" "$ENGINE"
  rc_not 0
  t "and says why"
  has "harness repo itself"
fi

# ------------------------------------------------------- runner preflight
group "runner preflight"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo preflight)"

  t "refuses a TEST_CMD that is not on PATH"
  printf 'TEST_CMD="pytest-that-does-not-exist -q"\n' > "$R/factory.env"
  run "$R" bash scripts/run_antigravity.sh feat
  rc_not 0
  t "and names the missing binary"
  has "pytest-that-does-not-exist"
  t "and writes no log for it"
  counts "$R/handoffs/logs-*.txt" 0

  printf 'TEST_CMD="true"\nMAX_ROUNDS="2"\n' > "$R/factory.env"

  t "refuses a handoff with no Difficulty line"
  write_handoff "$R" feat
  strip_line "$R/handoffs/20260816T090000Z-feat.md" '^Difficulty:'
  run "$R" bash scripts/run_antigravity.sh feat
  rc_not 0
  t "and points at the lint"
  has "factory_lint.sh"
  t "and spends no round on it"
  counts "$R/handoffs/logs-*.txt" 0

  t "--no-lint overrides the gate"
  run "$R" env FAKE_MODE=ok bash scripts/run_antigravity.sh feat --no-lint
  rc_is 0

  write_handoff "$R" feat

  t "--dry-run prints the prompt"
  rm -f "$R"/handoffs/logs-*.txt
  run "$R" bash scripts/run_antigravity.sh feat --dry-run
  has "The handoff is the contract"
  t "--dry-run calls nothing"
  counts "$R/handoffs/logs-*.txt" 0
fi

# ----------------------------------------------------- context marker rule
group "context marker"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo marker)"

  t "template marker on line 1 drops the file"
  run "$R" bash scripts/run_antigravity.sh feat --dry-run
  lacks "$R/factory/context.md"
  t "and warns loudly on stdout"
  has "still has the factory:template marker on line 1"

  t "marker in the body does NOT drop the file"
  printf '# Project context\n\nwatch out: files with factory:template on line 1 are skipped.\n' \
    > "$R/factory/context.md"
  run "$R" bash scripts/run_antigravity.sh feat --dry-run
  has "$R/factory/context.md"
  t "and stops warning about it"
  lacks "factory/context.md still has"
fi

# ------------------------------------------------------------------- lock
group "lock"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo lock)"

  t "a completed round leaves no lock"
  run "$R" bash scripts/run_antigravity.sh feat
  rc_is 0
  t "lock file cleared"
  absent "$R/.factory-cache/locks/feat.lock"

  t "a live lock refuses a second round"
  sleep 300 & LIVE=$!
  mkdir -p "$R/.factory-cache/locks"
  printf 'pid=%s\nstarted=NOW\n' "$LIVE" > "$R/.factory-cache/locks/feat.lock"
  run "$R" bash scripts/run_antigravity.sh feat
  rc_not 0
  t "and says a round is running"
  has "already running"
  t "state says wait while it runs"
  is "$(state_next "$R" feat)" "wait"
  kill "$LIVE" 2>/dev/null
  wait "$LIVE" 2>/dev/null

  t "--force overrides a lock"
  printf 'pid=%s\nstarted=NOW\n' "$$" > "$R/.factory-cache/locks/feat.lock"
  run "$R" bash scripts/run_antigravity.sh feat --force
  rc_is 0

  t "a stale lock is cleared with a note"
  printf 'pid=999999\nstarted=OLD\n' > "$R/.factory-cache/locks/feat.lock"
  run "$R" bash scripts/run_antigravity.sh feat
  has "stale lock"
  t "and the round runs anyway"
  rc_is 0
fi

# --------------------------------------------------------------- snapshot
group "snapshot"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo snapshot)"
  printf 'GOOD\n' > "$R/tracked-edit.txt"
  ( cd "$R" && git add tracked-edit.txt && git commit -qm add >/dev/null 2>&1 )
  printf 'GOOD EDIT\n' > "$R/tracked-edit.txt"
  printf 'KEEP ME\n' > "$R/untracked.txt"

  t "a round writes a snapshot"
  run "$R" bash scripts/run_antigravity.sh feat
  counts "$R/.factory-cache/snapshots/*-feat.tar.gz" 1

  SNAP="$(ls -1 "$R"/.factory-cache/snapshots/*-feat.tar.gz | tail -n 1)"
  printf 'MANGLED\n' > "$R/tracked-edit.txt"
  rm -f "$R/untracked.txt"
  ( cd "$R" && tar xzf "$SNAP" -C . )

  t "restores a mangled tracked file"
  is "$(cat "$R/tracked-edit.txt")" "GOOD EDIT"
  t "restores a deleted untracked file"
  is "$(cat "$R/untracked.txt" 2>/dev/null)" "KEEP ME"

  t "keeps at most ten snapshots per slug"
  for i in 1 2 3 4 5 6 7 8 9; do
    touch "$R/.factory-cache/snapshots/2026080${i}T000000Z-feat.tar.gz"
  done
  touch "$R/.factory-cache/snapshots/20260810T000000Z-feat.tar.gz"
  touch "$R/.factory-cache/snapshots/20260811T000000Z-feat.tar.gz"
  run "$R" bash scripts/run_antigravity.sh feat
  counts "$R/.factory-cache/snapshots/*-feat.tar.gz" 10

  t "--no-snapshot skips it"
  R2="$(new_repo snapshot2)"
  printf 'x\n' > "$R2/dirty.txt"
  run "$R2" bash scripts/run_antigravity.sh feat --no-snapshot
  counts "$R2/.factory-cache/snapshots/*-feat.tar.gz" 0
fi

# ------------------------------------------------------------ round logs
group "rounds"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo rounds)"

  t "round 1 writes one log"
  run "$R" bash scripts/run_antigravity.sh feat
  counts "$R/handoffs/logs-*-feat.txt" 1

  t "two rounds back to back write two logs"
  run "$R" bash scripts/run_antigravity.sh feat
  counts "$R/handoffs/logs-*-feat.txt" 2

  t "the log header records the round number"
  run "$R" grep -q '^round:     2' "$(ls -1 "$R"/handoffs/logs-*-feat.txt | tail -n 1)"
  rc_is 0
  t "and the model used"
  run "$R" grep -q '=== model used: model-a ===' "$(ls -1 "$R"/handoffs/logs-*-feat.txt | tail -n 1)"
  rc_is 0
  t "and the exit footer"
  run "$R" grep -q '=== agy exit code: 0 ===' "$(ls -1 "$R"/handoffs/logs-*-feat.txt | tail -n 1)"
  rc_is 0

  t "state counts rounds off the disk, not memory"
  run "$R" bash scripts/factory_state.sh feat
  has "rounds_run:   2"
fi

# --------------------------------------------------------- model fallback
group "model fallback"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo fallback)"

  t "a dead model falls through to another"
  run "$R" env FAKE_FAIL_MODEL=model-a bash scripts/run_antigravity.sh feat
  rc_is 0
  t "and the log names the model that worked"
  has "model used: model-b"

  t "every model failing is a failed run"
  R2="$(new_repo fallback2)"
  run "$R2" env FAKE_MODE=allfail bash scripts/run_antigravity.sh feat
  rc_not 0
  t "and it says so"
  has "failed to run"
fi

# ------------------------------------------------------------------- lint
group "lint"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo lint)"

  t "a clean contract passes"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_is 0

  t "a missing spec is an error"
  mv "$R/specs/feat.md" "$R/specs/feat.md.bak"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_not 0
  t "and names the file"
  has "specs/feat.md"
  mv "$R/specs/feat.md.bak" "$R/specs/feat.md"

  t "a handoff with no done criteria is an error"
  write_handoff "$R" feat
  strip_line "$R/handoffs/20260816T090000Z-feat.md" '^- \[ \]'
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_not 0
  t "and says what is missing"
  has "no done criteria"
  write_handoff "$R" feat

  t "Needs fix with no Next fix is an error"
  append_check "$R" feat "Needs fix" 1
  sed -i.bak '/^### Next fix/,$d' "$R/handoffs/20260816T090000Z-feat.md"
  rm -f "$R/handoffs/20260816T090000Z-feat.md.bak"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_not 0
  t "and says which block"
  has "Next fix"
  write_handoff "$R" feat

  t "a path that does not exist is a warning, not an error"
  printf -- '- `src/never.py` - the missing one\n' >> "$R/handoffs/20260816T090000Z-feat.md"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_is 0
  write_handoff "$R" feat

  t "a brief with an empty Rejected list is an error"
  mkdir -p "$R/factory/briefs"
  printf '# Brief\n\n## Problem\np\n\n## Approach\na\n\n## Rejected\n\n' > "$R/factory/briefs/feat.md"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_not 0
  t "and says the design was a reflex"
  has "Rejected"
  rm -f "$R/factory/briefs/feat.md"

  t "a truncated log is an error"
  mkdir -p "$R/handoffs"
  printf 'header only, agy died here' > "$R/handoffs/logs-20260816T100000Z-feat.txt"
  run "$R" bash scripts/factory_lint.sh feat
  rc_not 0
  t "and names the truncation"
  has "no RESULT:"
  t "but --contract ignores logs, so a dead round never blocks a retry"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_is 0
  t "and the runner still starts the next round"
  run "$R" bash scripts/run_antigravity.sh feat
  rc_is 0
fi

# ---------------------------------------------------------- state machine
group "state machine"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo state)"

  t "no handoff -> spec"
  rm -f "$R"/handoffs/*-feat.md
  is "$(state_next "$R" feat)" "spec"

  write_handoff "$R" feat
  t "handoff, no rounds -> build"
  is "$(state_next "$R" feat)" "build"

  t "malformed handoff -> fix"
  strip_line "$R/handoffs/20260816T090000Z-feat.md" '^Difficulty:'
  is "$(state_next "$R" feat)" "fix"
  write_handoff "$R" feat

  t "one round, no verdict -> check"
  run "$R" bash scripts/run_antigravity.sh feat
  is "$(state_next "$R" feat)" "check"

  t "Needs fix under the cap -> build"
  append_check "$R" feat "Needs fix" 1
  is "$(state_next "$R" feat)" "build"

  t "cap reached and still failing -> cap"
  run "$R" bash scripts/run_antigravity.sh feat
  append_check "$R" feat "Needs fix" 2
  is "$(state_next "$R" feat)" "cap"

  t "Success -> done"
  append_check "$R" feat "Success" 3
  is "$(state_next "$R" feat)" "done"

  t "the report prints a resume command"
  run "$R" bash scripts/factory_state.sh feat
  has "resume:"
  t "and a restore command for the snapshot"
  has "restore:      tar xzf"

  t "--all lists every slug"
  write_spec "$R" other
  write_handoff "$R" other
  run "$R" bash scripts/factory_state.sh --all
  has "other"
fi

# ----------------------------------------------------------------- report
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
