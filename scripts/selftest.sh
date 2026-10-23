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
# caveman: FACTORY_UPSTREAM lives in shell profiles by design. inherited, it
# points every sandbox at the real inbox - cases that want it set it themselves.
unset FACTORY_UPSTREAM
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
case "$2" in *"stopped mid-run"*) echo "saw: continue-note" ;; esac
if [ -n "${FAKE_FAIL_MODEL:-}" ] && [ "$model" = "$FAKE_FAIL_MODEL" ]; then
  echo "boom: $model is unavailable"; exit 1
fi
if [ -n "${FAKE_DIRTY_FAIL_MODEL:-}" ] && [ "$model" = "$FAKE_DIRTY_FAIL_MODEL" ]; then
  echo "half" > "$repo/half.txt"; echo "boom: died mid-edit"; exit 1
fi
if [ -n "${FAKE_QUOTA_MODEL:-}" ] && [ "$model" = "$FAKE_QUOTA_MODEL" ]; then
  echo "RESOURCE_EXHAUSTED (code 429)"; exit 3
fi
[ -z "${FAKE_STRAY:-}" ] || echo "x" > "$repo/patch.py"
[ -z "${FAKE_DETACH:-}" ] || git -C "$repo/sub" checkout -q --detach
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
    echo "  outside the contract: none"
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

  t "links the shared scripts"
  counts "$R/scripts/factory_*.sh" 5
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

  t "install writes the manifest"
  run "$R" grep -qxF "path: .claude/skills/factory-check" factory/installed.txt
  rc_is 0
fi

# ----------------------------------------------------------------- update
group "update"
if [ "$GROUP_ON" = 1 ]; then
  # caveman: an upstream engine to pull from, built from the working tree like
  # self mode. file:// submodules are refused by default since git 2.38, so
  # allow them for this group only, through the environment, not global config.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  U="$WORK/upstream"
  mkdir -p "$U"
  ( cd "$ENGINE" && tar cf - --exclude .git --exclude .factory-cache . ) | ( cd "$U" && tar xf - )
  rm -f "$U/factory/installed.txt"
  ( cd "$U" && git init -q . && git config user.email t@example.com &&
    git config user.name t && git add -A && git commit -qm base >/dev/null 2>&1 )

  upstream_commit() { # upstream_commit <msg>  - one more commit upstream
    ( cd "$U" && echo "$1" >> skills/factory-spec/SKILL.md && git add -A && git commit -qm "$1" )
  }
  plain_repo() { # plain_repo <name> -> empty git repo, nothing installed
    local d="$WORK/$1"
    mkdir -p "$d"
    ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name t )
    echo "$d"
  }

  # -- engine as a clone outside the repo
  C="$WORK/engine-clone"
  git clone -q "$U" "$C"
  ( cd "$C" && git config user.email t@example.com && git config user.name t )
  O="$(plain_repo outside)"
  bash "$C/install.sh" "$O" >/dev/null 2>&1

  # caveman: upstream adds a skill and drops a script - the two things a plain
  # re-run of the old install.sh could never get right.
  ( cd "$U" && mkdir -p skills/factory-new && echo "# new" > skills/factory-new/SKILL.md &&
    awk '/install_one "skills\/factory-reflect"/ { print; print "install_one \"skills/factory-new\" \".claude/skills/factory-new\""; next }
         /install_one "scripts\/factory_state.sh"/ { next } { print }' install.sh > install.sh.new &&
    mv install.sh.new install.sh && git add -A && git commit -qm "add factory-new, drop state" )
  upstream_commit "tweak the spec skill"
  ( cd "$U" && printf '\n# a knob added upstream\nNEW_KNOB="1"\n' >> factory.env.example &&
    git commit -qam "add NEW_KNOB" )
  printf 'TEST_CMD="true"\n' > "$O/factory.env"

  t "--update pulls a cloned engine"
  run "$O" bash "$C/install.sh" --update
  rc_is 0
  t "to the upstream head"
  is "$(git -C "$C" rev-parse HEAD)" "$(git -C "$U" rev-parse HEAD)"
  t "and lists the commits that came in"
  has "tweak the spec skill"
  t "with a count"
  has "3 new commit(s)"
  t "names a setting this update added"
  has "new setting: NEW_KNOB"
  t "but not old settings the project left out"
  lacks "new setting: AGY_TIMEOUT"
  t "links the skill upstream added, using the NEW install.sh"
  [ -L "$O/.claude/skills/factory-new" ] && ok || bad "factory-new was not linked" "$LAST_OUT"
  t "prunes the script upstream dropped"
  absent "$O/scripts/factory_state.sh"
  t "and says so"
  has "prune scripts/factory_state.sh"
  t "keeps the rest"
  exists "$O/scripts/factory_lint.sh"
  t "records the new engine in the manifest"
  run "$O" grep -qxF "engine: $(git -C "$U" rev-parse HEAD)" factory/installed.txt
  rc_is 0

  t "a second --update is a no-op"
  run "$O" bash "$C/install.sh" --update
  has "already up to date"

  t "a diverged engine fails loudly"
  ( cd "$C" && echo local >> README.md && git commit -qam "local edit" )
  upstream_commit "upstream edit"
  run "$O" bash "$C/install.sh" --update
  rc_not 0
  t "and says nothing was changed"
  has "nothing was changed"
  ( cd "$C" && git reset -q --hard origin/HEAD )

  # -- engine as a submodule, the documented install
  M="$(plain_repo submod)"
  ( cd "$M" && git submodule add -q "$U" factory-engine >/dev/null 2>&1 &&
    bash factory-engine/install.sh >/dev/null 2>&1 && git add -A && git commit -qm init >/dev/null 2>&1 )
  upstream_commit "submodule news"

  t "--update moves a submodule engine"
  run "$M" bash factory-engine/install.sh --update
  rc_is 0
  t "to the upstream head"
  is "$(git -C "$M/factory-engine" rev-parse HEAD)" "$(git -C "$U" rev-parse HEAD)"
  t "and shows the commit"
  has "submodule news"
  t "links stay relative to the submodule"
  is "$(readlink "$M/.claude/skills/factory-check")" "../../factory-engine/skills/factory-check"

  # -- copy mode
  K="$(plain_repo copied)"
  bash "$C/install.sh" "$K" --copy >/dev/null 2>&1
  ( cd "$C" && git pull -q --ff-only )
  upstream_commit "copy marker"

  t "a plain --copy re-run does NOT refresh the copies"
  run "$K" bash "$C/install.sh" --copy
  has "skip  .claude/skills/factory-spec"

  t "--update remembers copy mode and refreshes the copies"
  run "$K" bash "$C/install.sh" --update
  rc_is 0
  run "$K" grep -q "copy marker" .claude/skills/factory-spec/SKILL.md
  rc_is 0
  t "which stay real files"
  [ -L "$K/.claude/skills/factory-spec" ] && bad "copy became a symlink" || ok

  # -- installs from before the manifest existed
  P="$(new_repo legacy)"
  rm -f "$P/factory/installed.txt"
  ln -s "$(cd "$ENGINE" && pwd -P)/skills/factory-gone" "$P/.claude/skills/factory-gone"
  ln -s "/nowhere/factory-mine" "$P/.claude/skills/factory-mine"

  t "--no-pull still relinks"
  run "$P" bash "$ENGINE/install.sh" --update --no-pull
  rc_is 0
  lacks "pull:"
  t "prunes a dangling link into the engine"
  [ -L "$P/.claude/skills/factory-gone" ] && bad "factory-gone survived" "$LAST_OUT" || ok
  t "but leaves a dangling link that is not the engine's"
  [ -L "$P/.claude/skills/factory-mine" ] && ok || bad "factory-mine was removed" "$LAST_OUT"
  t "and writes the manifest it was missing"
  exists "$P/factory/installed.txt"

  t "does not nag about settings when no engine commits came in"
  lacks "new setting:"

  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
fi

# ---------------------------------------------------------------- version
group "version"
if [ "$GROUP_ON" = 1 ]; then
  t "VERSION is X.Y.Z"
  run "$ENGINE" grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' VERSION
  rc_is 0
  t "and the newest CHANGELOG entry is that version"
  is "$(sed -n 's/^## \([0-9][0-9.]*\) .*/\1/p' "$ENGINE/CHANGELOG.md" | head -1)" "$(cat "$ENGINE/VERSION")"

  t "versions compare as numbers, not as strings"
  is "$(. "$ENGINE/scripts/factory_common.sh"; factory_ver_cmp 1.10.0 1.9.0)" "1"

  # caveman: a released upstream, tagged the way a release is tagged.
  VU="$WORK/vupstream"
  mkdir -p "$VU"
  ( cd "$ENGINE" && tar cf - --exclude .git --exclude .factory-cache . ) | ( cd "$VU" && tar xf - )
  rm -f "$VU/factory/installed.txt"
  ( cd "$VU" && printf '1.0.0\n' > VERSION && git init -q . && git config user.email t@example.com &&
    git config user.name t && git add -A && git commit -qm base >/dev/null 2>&1 && git tag v1.0.0 )
  release() { # release <version> <note>  - VERSION, changelog entry, tag
    ( cd "$VU" && printf '%s\n' "$1" > VERSION &&
      { sed -n '1,/^## /p' CHANGELOG.md | sed '$d'; printf '## %s - 2026-01-01\n\n- %s\n\n' "$1" "$2";
        sed -n '/^## /,$p' CHANGELOG.md; } > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md &&
      git commit -qam "release $1" && git tag "v$1" )
  }
  VC="$WORK/vengine"
  git clone -q "$VU" "$VC"
  V="$WORK/versioned"
  mkdir -p "$V"
  ( cd "$V" && git init -q . && git config user.email t@example.com && git config user.name t )
  bash "$VC/install.sh" "$V" >/dev/null 2>&1

  t "install records the version in the manifest"
  run "$V" grep -qxF "version: 1.0.0" factory/installed.txt
  rc_is 0
  t "the version script is linked into the project"
  [ -L "$V/scripts/factory_version.sh" ] && ok || bad "scripts/factory_version.sh is not a link"

  t "on the newest release -> up to date"
  run "$V" bash scripts/factory_version.sh
  rc_is 0
  has "status:      up to date"
  t "and names all three numbers"
  has "latest:      1.0.0"

  release 1.1.0 "a shiny new check"
  t "a cached answer does not ask upstream again"
  run "$V" bash scripts/factory_version.sh
  has "up to date"
  t "--refresh does, and finds the minor release"
  run "$V" bash scripts/factory_version.sh --refresh
  has "update available - v1.1.0"
  t "with the command that takes it"
  has "install.sh --update"
  t "--short prints the status line only"
  run "$V" bash scripts/factory_version.sh --short
  is "$(printf '%s\n' "$LAST_OUT" | wc -l | tr -d ' ')" "1"

  t "--update prints the version move"
  run "$V" bash "$VC/install.sh" --update
  has "version: 1.0.0 -> 1.1.0"
  t "and the changelog entry that came in"
  has "a shiny new check"
  t "but not the entries it already had"
  lacks "## 1.0.0"
  t "and records the new version"
  run "$V" grep -qxF "version: 1.1.0" factory/installed.txt
  rc_is 0

  release 2.0.0 "a breaking change"
  t "a newer major release -> update required"
  run "$V" bash scripts/factory_version.sh --refresh
  has "update required - v2.0.0"
  t "pointing at the changelog"
  has "CHANGELOG.md"

  t "an engine moved without install.sh -> re-run install"
  ( cd "$VC" && git pull -q --ff-only )
  run "$V" bash scripts/factory_version.sh
  has "re-run install"

  t "an unreachable upstream -> the last answer, said so"
  ( cd "$VC" && git remote set-url origin "$WORK/nowhere" )
  run "$V" bash scripts/factory_version.sh --refresh
  rc_is 0
  has "using the last answer"
  t "and with no answer at all -> unknown, still exit 0"
  rm -f "$V/.factory-cache/latest-version.txt"
  bash "$VC/install.sh" "$V" --update --no-pull >/dev/null 2>&1
  run "$V" bash scripts/factory_version.sh
  rc_is 0
  has "status:      unknown"

  t "a copy install still knows what it has"
  VK="$WORK/vcopied"
  mkdir -p "$VK"
  ( cd "$VK" && git init -q . )
  bash "$VC/install.sh" "$VK" --copy >/dev/null 2>&1
  run "$VK" bash scripts/factory_version.sh
  has "installed:   2.0.0"
  t "and does not pretend to be the engine"
  has "copy install"
  lacks "mode:        self"

  t "in the engine, a VERSION with no tag -> unreleased"
  ( cd "$VC" && git remote set-url origin "$VU" && printf '2.1.0\n' > VERSION )
  run "$VC" bash scripts/factory_version.sh --refresh
  has "unreleased - VERSION 2.1.0 has no tag yet"
fi

# ---------------------------------------------------------------- release
group "release"
if [ "$GROUP_ON" = 1 ]; then
  # caveman: what the release workflow runs on every merge to main. a copy of
  # the engine, so the real VERSION and CHANGELOG are never touched.
  RL="$WORK/release"
  mkdir -p "$RL"
  ( cd "$ENGINE" && tar cf - --exclude .git --exclude .factory-cache . ) | ( cd "$RL" && tar xf - )
  ( cd "$RL" && printf '1.0.0\n' > VERSION && git init -q . && git config user.email t@example.com &&
    git config user.name t && git add -A && git commit -qm base >/dev/null 2>&1 && git tag v1.0.0 )
  cut_release() { # cut_release <title> [body]  - as the workflow does, then tag
    printf '%s\n' "${2:-}" > "$RL/body.txt"
    run "$RL" bash scripts/release.sh --title "$1" --body body.txt --url "https://example.com/pull/9" --date 2026-01-01
    ( cd "$RL" && git commit -qam "release" && git tag "v$(cat VERSION)" )
  }
  top_entry() { sed -n 's/^## \([0-9][0-9.]*\) .*/\1/p' "$RL/CHANGELOG.md" | head -1; }

  t "a fix -> patch"
  cut_release "fix: the lint misses a heading"
  is "$LAST_OUT" "1.0.1"
  t "VERSION and the newest changelog entry agree"
  is "$(top_entry)" "$(cat "$RL/VERSION")"
  t "the entry is the title without its prefix, with the PR link"
  run "$RL" grep -qxF -- "- the lint misses a heading (https://example.com/pull/9)" CHANGELOG.md
  rc_is 0

  t "a feat -> minor"
  cut_release "feat(check): a new red flag"
  is "$LAST_OUT" "1.1.0"
  t "anything else -> patch"
  cut_release "docs: typo"
  is "$LAST_OUT" "1.1.1"

  t "a breaking title -> major"
  cut_release "feat!: handoffs move to a new format"
  is "$LAST_OUT" "2.0.0"
  t "with an Action needed pointer when the PR gave none"
  run "$RL" grep -q "^Action needed: breaking change, read https://example.com/pull/9" CHANGELOG.md
  rc_is 0
  t "BREAKING CHANGE in the body -> major too"
  cut_release "refactor: rename a setting" "BREAKING CHANGE: AGY_TIMEOUT is gone
Action needed: rename AGY_TIMEOUT to AGY_ROUND_TIMEOUT in factory.env"
  is "$LAST_OUT" "3.0.0"
  t "and the PR's own Action needed lands in the entry"
  run "$RL" grep -qxF "Action needed: rename AGY_TIMEOUT to AGY_ROUND_TIMEOUT in factory.env" CHANGELOG.md
  rc_is 0
  t "newest entry first"
  is "$(top_entry)" "3.0.0"

  t "a VERSION set by hand and not tagged is released as is"
  ( cd "$RL" && printf '5.0.0\n' > VERSION &&
    awk '!d && /^## [0-9]/ { print "## 5.0.0 - 2026-01-01\n\n- written by hand\n"; d=1 } { print }' CHANGELOG.md > c.new &&
    mv c.new CHANGELOG.md && git commit -qam "hand" )
  run "$RL" bash scripts/release.sh --title "feat: whatever"
  is "$LAST_OUT" "5.0.0"
  t "keeping the entry written by hand, not adding a second"
  is "$(grep -c '^## 5.0.0 ' "$RL/CHANGELOG.md")" "1"

  t "no --title is an error"
  run "$RL" bash scripts/release.sh
  rc_is 2
fi

# ------------------------------------------------------ self-development
group "self mode"
if [ "$GROUP_ON" = 1 ]; then
  # caveman: never install into the real engine repo - copy it first. a copy of
  # the WORKING TREE, not a clone of HEAD: the point is to test what is about to
  # be committed, not what already was.
  S="$WORK/selfmode"
  mkdir -p "$S"
  ( cd "$ENGINE" && tar cf - --exclude .git --exclude .factory-cache . ) | ( cd "$S" && tar xf - )
  ( cd "$S" && git init -q . && git config user.email t@example.com &&
    git config user.name t && git add -A && git commit -qm base >/dev/null 2>&1 )

  t "installing into the harness itself is self-development mode"
  run "$S" bash ./install.sh .
  rc_is 0
  t "and says so"
  has "self-development"

  t "the skills are linked inside the engine repo"
  counts "$S/.claude/skills/factory-*" 5
  t "with relative links that stay inside the repo"
  is "$(readlink "$S/.claude/skills/factory-check")" "../../skills/factory-check"
  t "and the linked skill is readable"
  exists "$S/.claude/skills/factory-check/SKILL.md"

  t "the scripts are NOT relinked onto themselves"
  [ -L "$S/scripts/factory_lint.sh" ] && bad "scripts/factory_lint.sh became a symlink" || ok
  t "and the runner survived"
  exists "$S/scripts/run_antigravity.sh"

  t "TEST_CMD is the harness selftest"
  run "$S" grep -q 'TEST_CMD="bash scripts/selftest.sh"' factory.env
  rc_is 0
  t "which actually runs"
  run "$S" bash scripts/selftest.sh --only "state machine"
  rc_is 0

  t "factory_env.sh reports self mode"
  run "$S" bash scripts/factory_env.sh
  has "mode:        self"
  t "with the engine and the project being one repo"
  has "engine:      $S"
  t "and engine edits allowed"
  has "engine_edit: allowed"
  t "and the engine persona lenses loaded"
  has "personas/engine"

  t "a second self-install keeps factory.env"
  run "$S" bash ./install.sh .
  rc_is 0
  t "and is still self mode"
  has "self-development"

  t "--update in self mode skips the pull"
  run "$S" bash ./install.sh . --update
  rc_is 0
  has "skip  pull"
  t "and leaves the real scripts alone"
  [ -L "$S/scripts/factory_lint.sh" ] && bad "scripts/factory_lint.sh became a symlink" || ok

  t "project mode reports the vendored engine instead"
  P="$(new_repo projectmode)"
  run "$P" bash scripts/factory_env.sh
  has "mode:        project"
  t "and forbids engine edits"
  has "engine_edit: forbidden"
  t "and does not load the engine-only lenses"
  lacks "personas/engine"
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

# --------------------------------------------- upstream sweep 2026-10
# caveman: one case per rule carried up from consumer improvements.md files.
group "upstream sweep"
if [ "$GROUP_ON" = 1 ]; then
  R="$(new_repo sweep)"

  t "TEST_CMD left at the example default is an error"
  printf 'TEST_CMD="pytest -q"\n' > "$R/factory.env"
  run "$R" bash scripts/factory_lint.sh feat --contract
  rc_not 0
  t "and says so"
  has "untouched example default"
  t "a commented example is a choice, not a default"
  printf 'TEST_CMD="go test ./..."\n' > "$R/factory.env"
  run "$R" bash scripts/factory_lint.sh feat --contract
  lacks "untouched example default"
  printf 'TEST_CMD="true"\nMAX_ROUNDS="2"\n' > "$R/factory.env"

  t "a diff criterion over the whole tree is a warning"
  printf -- '- [ ] `git diff --quiet -- . ":!sub"` is clean\n' >> "$R/handoffs/20260816T090000Z-feat.md"
  run "$R" bash scripts/factory_lint.sh feat --contract
  has "whole tree"
  t "but not an error"
  rc_is 0
  write_handoff "$R" feat
  t "a scoped one is fine"
  printf -- '- [ ] `git status --porcelain -- src/` lists only src/app.py\n' >> "$R/handoffs/20260816T090000Z-feat.md"
  run "$R" bash scripts/factory_lint.sh feat --contract
  lacks "whole tree"
  write_handoff "$R" feat

  t "the prompt asks for unlisted edits"
  run "$R" bash scripts/run_antigravity.sh feat --dry-run
  has "outside the contract:"
  t "a walkthrough without that line is a warning"
  printf 'RESULT: PASS\nWALKTHROUGH:\n  how it works: x\n=== agy exit code: 0 ===\n' \
    > "$R/handoffs/logs-20260816T100000Z-feat.txt"
  run "$R" bash scripts/factory_lint.sh feat
  has "outside the contract"
  rm -f "$R"/handoffs/logs-*.txt

  t "a clean round leaves no stray files"
  run "$R" bash scripts/run_antigravity.sh feat
  run "$R" bash scripts/factory_state.sh feat
  has "stray:        none"
  t "a helper the builder left behind is stray"
  run "$R" env FAKE_STRAY=1 bash scripts/run_antigravity.sh feat
  run "$R" bash scripts/factory_state.sh feat
  has "stray:        patch.py"
  t "but a listed file is not"
  lacks "src/app.py"

  R2="$(new_repo sweep2)"
  t "a fallback after a clean failure gets the plain prompt"
  run "$R2" env FAKE_FAIL_MODEL=model-a bash scripts/run_antigravity.sh feat
  lacks "saw: continue-note"
  t "the substitution is named, with the exit code"
  has "model requested: model-a (exit 1)"
  t "and the state shows it"
  run "$R2" bash scripts/factory_state.sh feat
  has "(requested model-a (exit 1))"
  t "a fallback after a half-edited tree is told to continue"
  run "$R2" env FAKE_DIRTY_FAIL_MODEL=model-a bash scripts/run_antigravity.sh feat
  has "saw: continue-note"

  R3="$(new_repo sweep3)"
  t "a quota failure falls back"
  run "$R3" env FAKE_QUOTA_MODEL=model-a bash scripts/run_antigravity.sh feat --model model-a
  has "model used: model-b"
  t "and the next round skips that family first"
  run "$R3" bash scripts/run_antigravity.sh feat --model model-a
  has "hit its quota"
  t "starting with the fallback"
  has "model used: model-b"

  t "a round that detaches a submodule is called out"
  R4="$(new_repo sweep4)"
  SUBSRC="$WORK/subsrc"
  mkdir -p "$SUBSRC" && ( cd "$SUBSRC" && git init -q . && git config user.email t@example.com &&
    git config user.name t && echo s > s.txt && git add -A && git commit -qm s >/dev/null 2>&1 )
  ( cd "$R4" && git -c protocol.file.allow=always submodule add -q "$SUBSRC" sub >/dev/null 2>&1 &&
    git commit -qm sub >/dev/null 2>&1 && git -C sub checkout -q -B work )
  run "$R4" env FAKE_DETACH=1 bash scripts/run_antigravity.sh feat
  has "moved a submodule's branch"
  t "and the log records it"
  run "$R4" grep -q '^=== submodule branch changed: sub work -> HEAD ===' "$(ls -1 "$R4"/handoffs/logs-*-feat.txt | tail -n 1)"
  rc_is 0

  t "reflect's inbox is off until FACTORY_UPSTREAM is set"
  run "$R" bash scripts/factory_env.sh
  has "upstream:    unset"
  t "the vendored engine is refused as an inbox"
  run "$R" env FACTORY_UPSTREAM="$ENGINE" bash scripts/factory_env.sh
  has "upstream:    invalid"
  t "a separate checkout is accepted"
  UPC="$WORK/upstream-checkout"; mkdir -p "$UPC/factory" && touch "$UPC/PRINCIPLES.md"
  run "$R" env FACTORY_UPSTREAM="$UPC" bash scripts/factory_env.sh
  has "upstream:    $UPC/factory/improvements.md"
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
