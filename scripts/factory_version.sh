#!/usr/bin/env bash
# caveman: is this project on the newest engine, and does it have to move.
# three numbers - what was installed, what the engine checkout is, what the
# newest release is - and one status line a skill can act on.
set -uo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/factory_version.sh [--short] [--refresh]

compares three versions:
  installed  what install.sh last put here      (factory/installed.txt)
  engine     what the engine checkout is at      (<engine>/VERSION)
  latest     the newest v* release tag upstream  (git ls-remote on the engine)

and prints one status:
  up to date        nothing to do
  update required   a newer MAJOR release - something you rely on changed,
                    read CHANGELOG.md for what to do, then update
  update available  a newer minor or patch release
  re-run install    the engine moved but install.sh did not run after it
  unknown           no release could be looked up (offline, no remote,
                    copy install) - the local numbers are still printed

  --short    only the status line
  --refresh  ask upstream now instead of using the cached answer

the upstream answer is cached in .factory-cache/latest-version.txt for
VERSION_TTL_MIN minutes (default 720). exit 0 unless the repo is unreadable.
USAGE
}

SHORT=0
REFRESH=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --short)   SHORT=1 ;;
    --refresh) REFRESH=1 ;;
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
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
cd "$REPO_ROOT"
ENGINE="$(factory_engine_root)"
MODE="$(factory_mode "$REPO_ROOT" "$ENGINE")"
factory_load_env "$REPO_ROOT"
VERSION_TTL_MIN="${VERSION_TTL_MIN:-720}"

MANIFEST="$REPO_ROOT/factory/installed.txt"
INSTALL_MODE="$(sed -n 's/^mode: //p' "$MANIFEST" 2>/dev/null | head -1 || true)"
INSTALLED="$(sed -n 's/^version: //p' "$MANIFEST" 2>/dev/null | head -1 || true)"

# caveman: a copy install carries the engine's scripts inside the project, so
# the "engine" found from $0 is the project itself. the real engine is
# somewhere else and only install.sh --update knows where.
COPY=0
[ "$INSTALL_MODE" = "copy" ] && [ "$MODE" = "self" ] && { COPY=1; MODE="project"; }

ENGINE_VER=""
[ "$COPY" -eq 1 ] || ENGINE_VER="$(factory_engine_version "$ENGINE")"
[ "$MODE" = "self" ] && INSTALLED="$ENGINE_VER"

# caveman: how to call install.sh from the project root, for the hint.
case "$ENGINE" in
  "$REPO_ROOT")   INSTALL="bash install.sh" ;;
  "$REPO_ROOT"/*) INSTALL="bash ${ENGINE#"$REPO_ROOT"/}/install.sh" ;;
  *)              INSTALL="bash $ENGINE/install.sh" ;;
esac
[ "$COPY" -eq 1 ] && INSTALL="bash <engine>/install.sh"

# caveman: the newest release is a tag on the engine's remote. ls-remote reads
# without fetching, so the checkout is never moved by a check. never prompt,
# never hang - a check that blocks a build is worse than no check.
LATEST=""
LATEST_FROM=""
lookup_latest() {
  [ "$COPY" -eq 0 ] || { LATEST_FROM="copy install, no engine checkout to ask"; return 0; }
  [ "$(git -C "$ENGINE" rev-parse --show-toplevel 2>/dev/null || true)" = "$ENGINE" ] ||
    { LATEST_FROM="engine is not a git checkout"; return 0; }
  local remote
  remote="$(git -C "$ENGINE" remote 2>/dev/null | grep -x origin || git -C "$ENGINE" remote 2>/dev/null | head -1 || true)"
  [ -n "$remote" ] || { LATEST_FROM="engine has no git remote"; return 0; }

  local cache_dir="$REPO_ROOT/.factory-cache" cache
  cache="$cache_dir/latest-version.txt"
  if [ "$REFRESH" -eq 0 ] && [ -n "$(find "$cache" -mmin "-$VERSION_TTL_MIN" 2>/dev/null)" ]; then
    LATEST="$(head -n 1 "$cache")"
    factory_is_ver "$LATEST" && { LATEST_FROM="newest v* tag on $remote, cached"; return 0; }
    LATEST=""
  fi

  local tags v best=""
  tags="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
          git -C "$ENGINE" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 \
          ls-remote --tags --refs "$remote" 'v*' 2>/dev/null)" || {
    LATEST="$(head -n 1 "$cache" 2>/dev/null || true)"
    if factory_is_ver "$LATEST"; then LATEST_FROM="could not reach $remote, using the last answer"
    else LATEST=""; LATEST_FROM="could not reach $remote"; fi
    return 0
  }
  for v in $(printf '%s\n' "$tags" | sed -n 's|.*refs/tags/v||p'); do
    factory_is_ver "$v" || continue
    if [ -z "$best" ] || [ "$(factory_ver_cmp "$v" "$best")" = 1 ]; then best="$v"; fi
  done
  [ -n "$best" ] || { LATEST_FROM="no v* release tags on $remote yet"; return 0; }
  LATEST="$best"
  LATEST_FROM="newest v* tag on $remote"
  mkdir -p "$cache_dir" && printf '%s\n' "$LATEST" > "$cache"
  return 0
}
lookup_latest

major() { printf '%s\n' "${1%%.*}"; }

if [ "$MODE" = "self" ]; then
  # caveman: in the engine itself "behind" means a release nobody tagged, or a
  # checkout older than what is already out.
  if [ -z "$ENGINE_VER" ]; then
    STATUS="unknown - VERSION is missing or not X.Y.Z"
  elif [ -z "$LATEST" ]; then
    STATUS="unknown - $LATEST_FROM. VERSION is $ENGINE_VER"
  else
    case "$(factory_ver_cmp "$ENGINE_VER" "$LATEST")" in
      1)  STATUS="unreleased - VERSION $ENGINE_VER has no tag yet: git tag v$ENGINE_VER && git push origin v$ENGINE_VER" ;;
      0)  STATUS="up to date - $ENGINE_VER is the newest release" ;;
      -1) STATUS="behind - v$LATEST is out and this checkout is $ENGINE_VER: git pull" ;;
    esac
  fi
else
  # caveman: what the project actually runs. in a copy install that is the
  # installed version; otherwise the links already serve the engine checkout.
  HAVE="${ENGINE_VER:-$INSTALLED}"
  if [ -n "$LATEST" ] && [ -n "$HAVE" ] && [ "$(major "$LATEST")" -gt "$(major "$HAVE")" ]; then
    STATUS="update required - v$LATEST is a major release past $HAVE. read its Action needed in CHANGELOG.md, then: $INSTALL --update"
  elif [ -n "$LATEST" ] && [ -n "$HAVE" ] && [ "$(factory_ver_cmp "$LATEST" "$HAVE")" = 1 ]; then
    STATUS="update available - v$LATEST is out, this project is on $HAVE: $INSTALL --update"
  elif [ -n "$ENGINE_VER" ] && { [ -z "$INSTALLED" ] || [ "$(factory_ver_cmp "$ENGINE_VER" "$INSTALLED")" = 1 ]; }; then
    STATUS="re-run install - the engine is at $ENGINE_VER but install.sh last ran for ${INSTALLED:-a version before 1.0.0}: $INSTALL --update --no-pull"
  elif [ -z "$LATEST" ]; then
    STATUS="unknown - $LATEST_FROM. this project is on ${HAVE:-an unversioned engine}"
  else
    STATUS="up to date - $HAVE is the newest release"
  fi
fi

if [ "$SHORT" -eq 1 ]; then
  printf 'status:      %s\n' "$STATUS"
  exit 0
fi
printf 'mode:        %s%s\n' "$MODE" "$([ "$COPY" -eq 1 ] && echo ", copy install" || true)"
printf 'installed:   %s\n' "${INSTALLED:-none recorded (installed before 1.0.0)}"
printf 'engine:      %s\n' "${ENGINE_VER:-unknown}$([ "$COPY" -eq 0 ] && echo " ($ENGINE/VERSION)" || true)"
printf 'latest:      %s\n' "${LATEST:-unknown}${LATEST_FROM:+ ($LATEST_FROM)}"
printf 'status:      %s\n' "$STATUS"
exit 0
