#!/usr/bin/env bash
# caveman: link harness into a repo. make dirs. no magic.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: bash factory-engine/install.sh [target-repo-dir] [--copy] [--force]

run it inside the harness repo itself to get self-development mode: the same
skills and scripts, working on the harness, with TEST_CMD set to its selftest.

  target-repo-dir  repo to install into. default: repo containing cwd.
  --copy           copy files instead of symlinking (for filesystems
                   without symlink support). updates then need a re-run.
  --force          replace real files that are in the way, not just symlinks.

creates in the target repo:
  .claude/skills/factory-think   -> harness skill (Claude)
  .claude/skills/factory-spec    -> harness skill (Claude)
  .claude/skills/factory-build   -> harness skill (Claude)
  .claude/skills/factory-check   -> harness skill (Claude)
  .claude/skills/factory-reflect -> harness skill (Claude)
  .agents/skills                 -> harness skills (Antigravity)
  scripts/*.sh                   -> runner, lint, state, env, shared lib
  scripts/factory_lint.sh        -> shape checks, free and deterministic
  scripts/factory_state.sh       -> where the run stopped, what to do next
  specs/  handoffs/              -> empty, with .gitkeep
  factory/                       -> project brain: context, adr, briefs,
                                    memory, improvements, personas,
                                    prompt-extra
  factory.env                    -> real file, from factory.env.example
USAGE
}

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
MODE="link"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --copy)    MODE="copy" ;;
    --force)   FORCE=1 ;;
    -*)        echo "unknown flag: $arg" >&2; usage; exit 2 ;;
    *)         TARGET="$arg" ;;
  esac
done

if [ -n "$TARGET" ]; then
  REPO_ROOT="$(cd "$TARGET" && git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo, and no target dir given" >&2; exit 1; }
fi

# caveman: self-development mode. the harness working on itself is not a
# mistake to be blocked - it is how the factory evolves without a second copy
# of anything. same skills, same scripts, same personas, one extra lens set.
SELF_MODE=0
[ "$REPO_ROOT" = "$FACTORY_DIR" ] && SELF_MODE=1

# caveman: relative link target if harness sits inside repo, else absolute.
FACTORY_REL=""
case "$FACTORY_DIR" in
  "$REPO_ROOT")   FACTORY_REL="." ;;
  "$REPO_ROOT"/*) FACTORY_REL="${FACTORY_DIR#"$REPO_ROOT"/}" ;;
  *) echo "note: harness is outside the target repo, using absolute symlinks" ;;
esac

echo "harness: $FACTORY_DIR"
echo "repo:    $REPO_ROOT"
echo "mode:    $MODE$([ "$SELF_MODE" -eq 1 ] && echo ", self-development" || true)"
echo

# caveman: put one thing from harness into repo.
install_one() { # install_one <src-rel-to-harness> <dest-rel-to-repo>
  local src="$1" dest="$2"
  local destdir; destdir="$(dirname "$dest")"
  local full="$REPO_ROOT/$dest"

  mkdir -p "$REPO_ROOT/$destdir"

  if [ -e "$full" ] || [ -L "$full" ]; then
    if [ -L "$full" ] || [ "$FORCE" -eq 1 ]; then
      rm -rf "$full"
    else
      echo "  skip  $dest (real file in the way, use --force)"
      return 0
    fi
  fi

  if [ "$MODE" = "copy" ]; then
    cp -R "$FACTORY_DIR/$src" "$full"
    echo "  copy  $dest"
    return 0
  fi

  # caveman: how many ../ to climb back to the repo root from this dest.
  local target depth=0 up="" i=0
  [ "$destdir" != "." ] && depth="$(awk -F'/' '{print NF}' <<<"$destdir")"
  while [ "$i" -lt "$depth" ]; do up="../$up"; i=$((i+1)); done

  if [ "$FACTORY_REL" = "." ]; then
    target="${up}${src}"                    # self mode: harness is the repo
  elif [ -n "$FACTORY_REL" ]; then
    target="${up}${FACTORY_REL}/${src}"     # vendored under the repo
  else
    target="$FACTORY_DIR/$src"              # harness lives outside
  fi

  ln -s "$target" "$full"
  echo "  link  $dest -> $target"
}

install_one "skills/factory-think"       ".claude/skills/factory-think"
install_one "skills/factory-spec"        ".claude/skills/factory-spec"
install_one "skills/factory-build"       ".claude/skills/factory-build"
install_one "skills/factory-check"       ".claude/skills/factory-check"
install_one "skills/factory-reflect"     ".claude/skills/factory-reflect"
install_one "agents/skills"              ".agents/skills"

# caveman: in self mode the scripts are already where they belong. linking them
# onto themselves would delete the originals first - never do that.
if [ "$SELF_MODE" -eq 0 ]; then
  install_one "scripts/run_antigravity.sh" "scripts/run_antigravity.sh"
  install_one "scripts/factory_lint.sh"    "scripts/factory_lint.sh"
  install_one "scripts/factory_state.sh"   "scripts/factory_state.sh"
  install_one "scripts/factory_env.sh"     "scripts/factory_env.sh"
  install_one "scripts/factory_common.sh"  "scripts/factory_common.sh"
else
  echo "  keep  scripts/ (self-development mode - the originals live here)"
fi

# caveman: work dirs. git needs a file to keep them.
# factory/personas is empty on purpose - drop a file in to add a lens.
for d in specs handoffs factory/adr factory/briefs factory/personas; do
  mkdir -p "$REPO_ROOT/$d"
  [ -f "$REPO_ROOT/$d/.gitkeep" ] || touch "$REPO_ROOT/$d/.gitkeep"
  echo "  dir   $d/"
done

# caveman: project brain. seeded once from templates, then it is yours.
# never overwrite - these fill up with real project knowledge.
seed() { # seed <template> <dest-rel>
  if [ -f "$REPO_ROOT/$2" ]; then
    echo "  keep  $2 (yours)"
  else
    cp "$FACTORY_DIR/templates/$1" "$REPO_ROOT/$2"
    echo "  seed  $2"
  fi
}
seed context.md      "factory/context.md"
seed memory.md       "factory/memory.md"
seed improvements.md "factory/improvements.md"
seed prompt-extra.md "factory/prompt-extra.md"

# caveman: per-project config. never overwrite what is already there.
# in self mode the test command is known - it is the harness's own suite.
if [ -f "$REPO_ROOT/factory.env" ]; then
  echo "  keep  factory.env (already exists)"
elif [ "$SELF_MODE" -eq 1 ]; then
  sed 's|^TEST_CMD=.*|TEST_CMD="bash scripts/selftest.sh"|' \
    "$FACTORY_DIR/factory.env.example" > "$REPO_ROOT/factory.env"
  echo "  new   factory.env  (TEST_CMD is the harness selftest)"
else
  cp "$FACTORY_DIR/factory.env.example" "$REPO_ROOT/factory.env"
  echo "  new   factory.env  <- EDIT THIS, set TEST_CMD"
fi

# caveman: logs are noise, keep them out of git.
GI="$REPO_ROOT/.gitignore"
add_ignore() {
  grep -qxF "$1" "$GI" 2>/dev/null || { echo "$1" >> "$GI"; echo "  git   ignore $1"; }
}
touch "$GI"
add_ignore "handoffs/logs-*.txt"
add_ignore ".factory-cache/"

echo
echo "done."
if [ "$SELF_MODE" -eq 1 ]; then
  echo "self-development mode: this repo now runs its own factory."
  echo "  TEST_CMD is bash scripts/selftest.sh - no agy needed to verify a change"
  echo "  /factory-think loads the engine lenses in personas/engine/ as well"
  echo "  /factory-reflect may edit the engine here; from a project it may not"
  echo
fi
echo "next:"
echo "  1. edit $REPO_ROOT/factory.env and set TEST_CMD"
echo "  2. in Claude Code:  /factory-think <what you want built>  (personas -> brief)"
echo "  3. in Claude Code:  /factory-build <slug>   (drives agy, loops, verifies)"
echo
echo "manual route, if you want to drive it yourself:"
echo "  bash scripts/run_antigravity.sh <slug>  then  /factory-check <slug>"
