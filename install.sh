#!/usr/bin/env bash
# caveman: link harness into a repo. make dirs. no magic.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: bash factory-engine/install.sh [target-repo-dir] [--copy] [--force]
       bash factory-engine/install.sh [target-repo-dir] --update [--no-pull]
       bash factory-engine/scripts/factory_version.sh   (am I behind?)

run it inside the harness repo itself to get self-development mode: the same
skills and scripts, working on the harness, with TEST_CMD set to its selftest.

  target-repo-dir  repo to install into. default: repo containing cwd.
  --copy           copy files instead of symlinking (for filesystems
                   without symlink support). updates then need --update.
  --force          replace real files that are in the way, not just symlinks.
  --update         bring an installed repo to the newest engine, in one go:
                   pull the engine (submodule update --remote, or git pull
                   --ff-only for a clone), re-link, refresh copies, prune what
                   upstream removed, and print the engine commits and the
                   CHANGELOG.md entries that came in.
                   copy mode is remembered, no need to pass --copy again.
  --no-pull        with --update: skip the pull, only re-link and prune.

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
  scripts/factory_version.sh     -> installed vs newest release, update or not
  specs/  handoffs/              -> empty, with .gitkeep
  factory/                       -> project brain: context, adr, briefs,
                                    memory, improvements, personas,
                                    prompt-extra
  factory/installed.txt          -> what the engine owns here, for --update
  factory.env                    -> real file, from factory.env.example
USAGE
}

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/factory_common.sh
. "$FACTORY_DIR/scripts/factory_common.sh"
TARGET=""
MODE=""
FORCE=0
UPDATE=0
PULL=1
FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --copy)    MODE="copy" ;;
    --force)   FORCE=1 ;;
    --update)  UPDATE=1 ;;
    --no-pull) PULL=0 ;;
    --from)    shift; FROM="${1:-}" ;;  # internal: engine rev before the pull
    -*)        echo "unknown flag: $1" >&2; usage; exit 2 ;;
    *)         TARGET="$1" ;;
  esac
  shift
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

# caveman: the manifest is the memory of the last install. without it an
# update cannot tell an engine file it may refresh or prune from a user's own.
MANIFEST="$REPO_ROOT/factory/installed.txt"
manifest_get() { sed -n "s/^$1: //p" "$MANIFEST" 2>/dev/null | head -1 || true; }
OLD_MODE="$(manifest_get mode)"
OLD_REV="$(manifest_get engine)"
OLD_VER="$(manifest_get version)"
OLD_PATHS="$(sed -n 's/^path: //p' "$MANIFEST" 2>/dev/null || true)"
NEW_PATHS=""

in_list() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

# caveman: the engine commit, only when the engine is its own checkout. a
# harness vendored as plain files inside the repo has no version of its own.
engine_rev() {
  [ "$(git -C "$FACTORY_DIR" rev-parse --show-toplevel 2>/dev/null || true)" = "$FACTORY_DIR" ] || return 0
  git -C "$FACTORY_DIR" rev-parse HEAD 2>/dev/null || true
}

# caveman: an update remembers how the repo was installed, so a copy install
# stays a copy without anyone having to remember the flag.
if [ -z "$MODE" ]; then
  MODE="link"
  if [ "$UPDATE" -eq 1 ]; then
    if [ -n "$OLD_MODE" ]; then MODE="$OLD_MODE"
    elif [ -d "$REPO_ROOT/.claude/skills/factory-spec" ] && [ ! -L "$REPO_ROOT/.claude/skills/factory-spec" ]; then
      MODE="copy"
    fi
  fi
fi
# caveman: copies are engine-owned by contract, so an update overwrites them.
[ "$UPDATE" -eq 1 ] && [ "$MODE" = "copy" ] && FORCE=1

# caveman: pull first, then hand over to the NEW install.sh. the old one would
# install the old list of files, and a new skill would never get linked.
if [ "$UPDATE" -eq 1 ] && [ "$PULL" -eq 1 ]; then
  BEFORE="$(engine_rev)"
  if [ "$SELF_MODE" -eq 1 ]; then
    echo "  skip  pull (self-development - the engine is this repo, use git)"
  elif [ -z "$BEFORE" ]; then
    echo "  skip  pull (engine is not its own git checkout - replace $FACTORY_DIR by hand)"
  else
    SUPER="$(git -C "$FACTORY_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
    [ -n "$SUPER" ] && SUPER="$(cd "$SUPER" && pwd -P)"
    if [ "$SUPER" = "$REPO_ROOT" ]; then
      echo "pull:    git submodule update --remote $FACTORY_REL"
      git -C "$REPO_ROOT" submodule update --remote -- "$FACTORY_REL" || {
        echo "error: could not update the engine submodule. nothing was changed." >&2; exit 1; }
    else
      echo "pull:    git -C $FACTORY_DIR pull --ff-only"
      git -C "$FACTORY_DIR" pull --ff-only || {
        echo "error: could not update the engine - local changes or a diverged branch? nothing was changed." >&2; exit 1; }
    fi
    PASS_ON=(--update --no-pull --from "$BEFORE")
    [ "$MODE" = "copy" ] && PASS_ON+=(--copy)
    [ "$FORCE" -eq 1 ] && PASS_ON+=(--force)
    exec bash "$FACTORY_DIR/install.sh" "$REPO_ROOT" "${PASS_ON[@]}"
  fi
fi

echo "harness: $FACTORY_DIR"
echo "repo:    $REPO_ROOT"
echo "mode:    $MODE$([ "$SELF_MODE" -eq 1 ] && echo ", self-development" || true)$([ "$UPDATE" -eq 1 ] && echo ", update" || true)"
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
  NEW_PATHS="$NEW_PATHS
$dest"

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
  install_one "scripts/factory_version.sh" "scripts/factory_version.sh"
  install_one "scripts/factory_env.sh"     "scripts/factory_env.sh"
  install_one "scripts/factory_common.sh"  "scripts/factory_common.sh"
else
  echo "  keep  scripts/ (self-development mode - the originals live here)"
fi

# caveman: upstream dropped or renamed something. what the last install put
# here and this one did not is gone from the engine - remove it, or a stale
# skill keeps loading. real files only go when the manifest says we copied
# them; anything else real is somebody's own and stays.
PRUNED=""
if [ "$UPDATE" -eq 1 ]; then
  while IFS= read -r p; do
    case "$p" in ""|/*|*..*) continue ;; esac
    in_list "$p" "$NEW_PATHS" && continue
    full="$REPO_ROOT/$p"
    if [ -L "$full" ]; then
      rm -f "$full"
    elif [ -e "$full" ] && [ "$OLD_MODE" = "copy" ] && [ "$SELF_MODE" -eq 0 ]; then
      rm -rf "$full"
    else
      continue
    fi
    PRUNED="$PRUNED $p"; echo "  prune $p (gone upstream)"
  done <<<"$OLD_PATHS"

  # caveman: installs from before the manifest have no list, so sweep the
  # engine's own spots for links into the engine that point at nothing now.
  for full in "$REPO_ROOT"/.claude/skills/factory-* "$REPO_ROOT"/scripts/*.sh; do
    [ -L "$full" ] && [ ! -e "$full" ] || continue
    p="${full#"$REPO_ROOT"/}"
    in_list "$p" "$NEW_PATHS" && continue
    L="$(readlink "$full")"
    owned="$SELF_MODE"
    case "$L" in "$FACTORY_DIR"/*) owned=1 ;; esac
    case "$FACTORY_REL" in ""|.) ;; *) case "$L" in *"$FACTORY_REL/"*) owned=1 ;; esac ;; esac
    [ "$owned" -eq 1 ] || continue
    rm -f "$full"; PRUNED="$PRUNED $p"; echo "  prune $p (dangling)"
  done
fi

# caveman: work dirs. git needs a file to keep them.
# factory/personas is empty on purpose - drop a file in to add a lens.
for d in specs handoffs factory/adr factory/briefs factory/personas; do
  mkdir -p "$REPO_ROOT/$d"
  [ -f "$REPO_ROOT/$d/.gitkeep" ] || touch "$REPO_ROOT/$d/.gitkeep"
  [ "$UPDATE" -eq 1 ] || echo "  dir   $d/"
done

# caveman: project brain. seeded once from templates, then it is yours.
# never overwrite - these fill up with real project knowledge.
seed() { # seed <template> <dest-rel>
  if [ -f "$REPO_ROOT/$2" ]; then
    [ "$UPDATE" -eq 1 ] || echo "  keep  $2 (yours)"
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
  [ "$UPDATE" -eq 1 ] || echo "  keep  factory.env (already exists)"
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

NEW_REV="$(engine_rev)"
[ "$SELF_MODE" -eq 1 ] && NEW_REV="self"
# caveman: the version comes from a file, not from git, so a copied engine with
# no history of its own still says which release it is.
NEW_VER="$(factory_engine_version "$FACTORY_DIR")"
{
  echo "# caveman: written by install.sh - what the engine owns in this repo, so"
  echo "# install.sh --update can refresh it and prune what upstream removed."
  echo "# do not edit. commit it."
  echo "mode: $MODE"
  echo "engine: ${NEW_REV:-unknown}"
  echo "version: ${NEW_VER:-unknown}"
  printf '%s\n' "$NEW_PATHS" | sed '/^$/d; s/^/path: /'
} > "$MANIFEST"

# caveman: an update is only worth running if you can see what it brought.
if [ "$UPDATE" -eq 1 ]; then
  # caveman: the manifest knows what this repo last installed, which beats
  # where the engine happened to be just before this pull.
  case "$OLD_REV" in ""|unknown|self) OLD_REV="$FROM" ;; esac
  echo
  if [ "$SELF_MODE" -eq 1 ] || [ -z "$NEW_REV" ]; then
    echo "engine:  no version to compare (self mode, or not a git checkout)"
  elif [ -z "$OLD_REV" ] || ! git -C "$FACTORY_DIR" cat-file -e "$OLD_REV^{commit}" 2>/dev/null; then
    echo "engine:  now at ${NEW_REV:0:7} (previous version unknown)"
  elif [ "$OLD_REV" = "$NEW_REV" ]; then
    echo "engine:  ${NEW_REV:0:7} (already up to date)"
  else
    N="$(git -C "$FACTORY_DIR" rev-list --count "$OLD_REV..$NEW_REV" 2>/dev/null || echo "?")"
    echo "engine:  ${OLD_REV:0:7} -> ${NEW_REV:0:7}, $N new commit(s):"
    git -C "$FACTORY_DIR" log --oneline --no-decorate -20 "$OLD_REV..$NEW_REV" 2>/dev/null | sed 's/^/  /' || true
    # caveman: factory/ was seeded from these once and is never overwritten, so
    # a template change upstream reaches a project only if someone looks.
    TPL="$(git -C "$FACTORY_DIR" diff --name-only "$OLD_REV" "$NEW_REV" -- templates factory.env.example 2>/dev/null || true)"
    if [ -n "$TPL" ]; then
      echo "templates changed - your factory/ files are yours, compare by hand:"
      printf '%s\n' "$TPL" | sed 's/^/  /'
    fi
    # caveman: only settings this update brought in. one the project left out
    # on purpose would otherwise nag on every run until nobody reads it.
    env_keys() { git -C "$FACTORY_DIR" show "$1:factory.env.example" 2>/dev/null |
                 sed -n 's/^#* *\([A-Z][A-Z_]*\)=.*/\1/p' | sort -u || true; }
    OLD_KEYS="$(env_keys "$OLD_REV")"
    for k in $(env_keys "$NEW_REV"); do
      in_list "$k" "$OLD_KEYS" && continue
      grep -qE "^[# ]*$k=" "$REPO_ROOT/factory.env" 2>/dev/null ||
        echo "new setting: $k (see factory.env.example)"
    done
  fi
  # caveman: commits say what changed, the changelog says what it means for you.
  if [ -n "$NEW_VER" ] && [ "$SELF_MODE" -eq 0 ]; then
    FROM_VER="$OLD_VER"
    factory_is_ver "$FROM_VER" || FROM_VER="0.0.0"
    if [ "$(factory_ver_cmp "$NEW_VER" "$FROM_VER")" = 1 ]; then
      echo "version: ${OLD_VER:-none} -> $NEW_VER - from CHANGELOG.md:"
      factory_changelog_between "$FACTORY_DIR/CHANGELOG.md" "$FROM_VER" "$NEW_VER" | sed 's/^/  /'
    else
      echo "version: $NEW_VER"
    fi
  fi
  [ -z "$PRUNED" ] || echo "pruned: $PRUNED"
  echo
  echo "done. review and commit: git -C $REPO_ROOT status"
  exit 0
fi

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
echo
echo "later, to see if you are behind:   bash scripts/factory_version.sh"
echo "and to take the newest engine:     bash <engine>/install.sh --update"
