#!/usr/bin/env bash
# caveman: Claude Code SessionStart hook, wired up by install.sh in
# .claude/settings.json. once per new session, never mid-session: is the engine
# behind? if so, tell the agent to update before it does anything else. up to
# date or unknown -> say nothing. it must never break a session, so it always
# exits 0 and never prints anything but the hook JSON.
#
# FACTORY_ENGINE_INITED=1 means the hook command just ran `git submodule update
# --init` - a fresh git worktree, where the skills dangled until now. Claude
# scans .claude/skills before hooks finish, so ask it to scan again, whatever
# the version says.
set -uo pipefail

SELF="$0"; while [ -L "$SELF" ]; do L="$(readlink "$SELF")"
  case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"

RELOAD=""
[ "${FACTORY_ENGINE_INITED:-0}" = 1 ] && RELOAD=',"reloadSkills":true'

# caveman: JSON by hand - no jq on every machine. backslashes, quotes and
# newlines are all a message like this can hold.
emit() { # emit [message]
  local ctx=""
  if [ -n "${1:-}" ]; then
    ctx=",\"additionalContext\":\"$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')\""
  fi
  [ -n "$ctx$RELOAD" ] || exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart"%s%s}}\n' "$ctx" "$RELOAD"
  exit 0
}

# caveman: a new session deserves a fresh answer. offline, factory_version.sh
# falls back to the cached one by itself. the repo is git's - in a worktree
# $CLAUDE_PROJECT_DIR can be the main checkout, on another engine commit.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")"
OUT="$(cd "$ROOT" && bash "$HERE/factory_version.sh" --refresh 2>/dev/null)" || emit
STATUS="$(printf '%s\n' "$OUT" | sed -n 's/^status: *//p' | head -1)"
NEXT="$(printf '%s\n' "$OUT" | sed -n 's/^next: *//p' | head -1)"
case "$STATUS" in
  "update required"*|"update available"*|"re-run install"*) ;;
  *) emit ;;
esac

MSG="The ai-factory engine in this project is behind: $STATUS

Before anything else, update it. This comes before the user's request, whatever it is.
1. Your first tool call is \`$NEXT\` (Bash, from the project root), alone in its message - no other tool call beside it. Wait for its output before doing anything for the user.
2. If it fails (a dirty or diverged engine, no network), stop: tell the user what it printed, and do not work around it.
3. If its output has \`Action needed:\` lines and the update is required, do what they say before going on, or ask the user when a line needs their decision.
4. Then do what the user asked.
5. Your final reply to the user MUST start with this block, filled in from the update output, before your answer to their request:

   **ai-factory updated** <old version> -> <new version>
   - Action needed: <each Action needed line, verbatim - or 'none'>
   - <each 'new setting:' and changed-template line, if any>
   - Commit the update: factory-engine (submodule pointer, if it moved), factory/installed.txt, and .claude/settings.json if it changed. Not committed by the agent.

Do not commit unless the user asks. Do not check the version again in this session.
"

emit "$MSG"
