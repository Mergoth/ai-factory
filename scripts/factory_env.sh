#!/usr/bin/env bash
# caveman: where am I, which mode, where is everything. one answer, so no skill
# has to know whether the harness is vendored, symlinked from outside, or is
# the repo itself.
set -uo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/factory_env.sh [--paths]

prints the resolved factory environment: mode, engine root, project root, the
directories every skill needs, and which project-brain files are actually
readable. every path is absolute, so it can be read from any cwd.

  --paths   only the machine-readable key: value lines, no brain listing

modes:
  project   the harness is vendored (factory-engine/) or symlinked from
            outside. the engine is read-only from here - PRINCIPLES #9.
  self      the repo IS the harness. the factory is working on itself, and
            editing the engine is the whole point.

deterministic, free, no model call.
USAGE
}

PATHS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --paths)   PATHS_ONLY=1 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

SELF="$0"; while [ -L "$SELF" ]; do L="$(readlink "$SELF")"
  case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
FACTORY_ENGINE="$(cd "$(dirname "$SELF")/.." && pwd -P)"
# shellcheck source=factory_common.sh
. "$FACTORY_ENGINE/scripts/factory_common.sh"

REPO_ROOT="$(factory_repo_root)" || true
[ -n "$REPO_ROOT" ] || { echo "error: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"
ENGINE="$(factory_engine_root)"
MODE="$(factory_mode "$REPO_ROOT" "$ENGINE")"
factory_load_env "$REPO_ROOT"

# caveman: persona lenses come from up to three places and every one that
# exists joins the round table. the engine-only set is for harness work, so it
# is off unless the harness is what we are working on.
PERSONA_DIRS=""
[ -d "$ENGINE/personas" ] && PERSONA_DIRS="$ENGINE/personas"
if [ "$MODE" = "self" ] && [ -d "$ENGINE/personas/engine" ]; then
  PERSONA_DIRS="$PERSONA_DIRS $ENGINE/personas/engine"
fi
[ -d "$REPO_ROOT/factory/personas" ] && PERSONA_DIRS="$PERSONA_DIRS $REPO_ROOT/factory/personas"

printf 'mode:        %s\n' "$MODE"
printf 'engine:      %s\n' "$ENGINE"
printf 'project:     %s\n' "$REPO_ROOT"
printf 'principles:  %s\n' "$ENGINE/PRINCIPLES.md"
printf 'templates:   %s\n' "$ENGINE/templates"
printf 'skills:      %s\n' "$ENGINE/skills"
printf 'personas:    %s\n' "$PERSONA_DIRS"
printf 'test_cmd:    %s\n' "${TEST_CMD:-<unset>}"
printf 'max_rounds:  %s\n' "$MAX_ROUNDS"
if [ "$MODE" = "self" ]; then
  printf 'engine_edit: allowed - the engine is the project here\n'
else
  printf 'engine_edit: forbidden - vendored, changes die at the next update (PRINCIPLES #9)\n'
fi

[ "$PATHS_ONLY" -eq 0 ] || exit 0

echo
echo 'brain - read what is listed as filled:'
for f in factory/context.md factory/memory.md factory/improvements.md factory/prompt-extra.md; do
  if [ ! -s "$REPO_ROOT/$f" ]; then
    printf '  %-26s missing\n' "$f"
  elif factory_is_template "$REPO_ROOT/$f"; then
    printf '  %-26s template - not filled in, and NOT sent to agy\n' "$f"
  else
    printf '  %-26s filled\n' "$f"
  fi
done
printf '  %-26s %s decision(s)\n' "factory/adr/"    "$(factory_count "$REPO_ROOT/factory/adr/*.md")"
printf '  %-26s %s brief(s)\n'    "factory/briefs/" "$(factory_count "$REPO_ROOT/factory/briefs/*.md")"

echo
echo 'work:'
printf '  %-26s %s\n' "specs/"    "$(factory_count "$REPO_ROOT/specs/*.md") spec(s)"
printf '  %-26s %s contract(s), %s log(s)\n' "handoffs/" \
  "$(factory_count "$REPO_ROOT/handoffs/*.md")" \
  "$(factory_count "$REPO_ROOT/handoffs/logs-*.txt")"
