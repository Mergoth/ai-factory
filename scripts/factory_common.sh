# caveman: shared bones for every factory script. source it, do not run it.
#
# every script needs the same answers: where is the repo, where is the engine,
# which mode are we in, what does factory.env say, which handoff is newest.
# they used to each carry their own copy, and the copies drifted.
#
# bootstrap, verbatim, at the top of every script in the engine's scripts/ dir:
#
#   SELF="$0"; while [ -L "$SELF" ]; do L="$(readlink "$SELF")"
#     case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
#   FACTORY_ENGINE="$(cd "$(dirname "$SELF")/.." && pwd -P)"
#   . "$FACTORY_ENGINE/scripts/factory_common.sh"

# caveman: follow a symlink chain to the real file. the scripts are symlinked
# into a project, so $0 is never where the engine actually lives.
factory_resolve() { # factory_resolve <path>
  local p="$1" l
  while [ -L "$p" ]; do
    l="$(readlink "$p")"
    case "$l" in
      /*) p="$l" ;;
      *)  p="$(dirname "$p")/$l" ;;
    esac
  done
  printf '%s\n' "$p"
}

# caveman: the repo being worked on. every path is relative to this.
factory_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# caveman: where the harness itself lives. three installs, one answer:
#   vendored  -> <repo>/factory-engine
#   outside   -> wherever the symlinks point
#   self      -> the repo IS the engine, and there is no factory-engine/
# resolving through this library's own path covers all three, because this
# file is always inside the engine.
factory_engine_root() {
  if [ -n "${FACTORY_ENGINE:-}" ]; then printf '%s\n' "$FACTORY_ENGINE"; return 0; fi
  local here
  here="$(factory_resolve "$0")"
  (cd "$(dirname "$here")/.." && pwd -P)
}

# caveman: self mode = the engine is the project. it is how the factory works
# on itself, and the only mode where editing the engine is allowed.
factory_mode() { # factory_mode <repo_root> <engine_root>
  if [ "$1" = "$2" ]; then echo "self"; else echo "project"; fi
}

# caveman: config with defaults first, then factory.env on top. one place, so
# a new setting does not have to be added to four scripts.
factory_load_env() { # factory_load_env <repo_root>
  TEST_CMD="${TEST_CMD:-}"
  MAX_ROUNDS="${MAX_ROUNDS:-3}"
  AGY_TIMEOUT="${AGY_TIMEOUT:-30m}"
  AGY_FALLBACKS="${AGY_FALLBACKS:-2}"
  MODELS_TTL_MIN="${MODELS_TTL_MIN:-720}"
  # shellcheck source=/dev/null
  [ -f "$1/factory.env" ] && . "$1/factory.env"
  return 0
}

# caveman: the template marker only counts on line 1, where install.sh puts it.
# matching it anywhere made a filled-in file that merely mentions the marker
# drop itself, silently.
factory_is_template() { # factory_is_template <file>
  case "$(head -n 1 "$1" 2>/dev/null)" in
    *factory:template*) return 0 ;;
    *) return 1 ;;
  esac
}

# caveman: ls fails on a glob with no match, and pipefail turns that into an
# exit. every count and every "newest" goes through these two.
factory_count() { # factory_count <glob...>
  ls -1d $* 2>/dev/null | wc -l | tr -d ' ' || true
}

factory_newest() { # factory_newest <glob...>
  ls -1 $* 2>/dev/null | sort | tail -n 1 || true
}

factory_newest_handoff() { # factory_newest_handoff <slug>   (run from repo root)
  factory_newest "handoffs/*-$1.md"
}

factory_newest_log() { # factory_newest_log <slug>
  factory_newest "handoffs/logs-*-$1.txt"
}

factory_count_logs() { # factory_count_logs <slug>  - this is the round counter
  factory_count "handoffs/logs-*-$1.txt"
}

# caveman: <timestamp>-<slug>.md -> slug
factory_slug_of() { # factory_slug_of <handoff-path>
  local base
  base="$(basename "$1" .md)"
  printf '%s\n' "${base#*-}"
}

factory_all_slugs() {
  ls -1 handoffs/*.md 2>/dev/null |
    sed -e 's|.*/||' -e 's|\.md$||' -e 's|^[0-9TZ]*-||' | sort -u || true
}

# caveman: no argument -> newest handoff decides. same rule in every script.
factory_default_slug() {
  local newest
  newest="$(factory_newest 'handoffs/*.md')"
  [ -n "$newest" ] || return 1
  factory_slug_of "$newest"
}
