#!/usr/bin/env bash
# caveman: Claude Code SessionStart hook, wired up by install.sh in
# .claude/settings.json. once per new session, never mid-session: is the engine
# behind? if so, tell the agent to update before it does anything else. up to
# date or unknown -> say nothing. it must never break a session, so it always
# exits 0 and never prints anything but the hook JSON.
set -uo pipefail

SELF="$0"; while [ -L "$SELF" ]; do L="$(readlink "$SELF")"
  case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"

# caveman: a new session deserves a fresh answer. offline, factory_version.sh
# falls back to the cached one by itself.
OUT="$(cd "${CLAUDE_PROJECT_DIR:-.}" && bash "$HERE/factory_version.sh" --refresh 2>/dev/null)" || exit 0
STATUS="$(printf '%s\n' "$OUT" | sed -n 's/^status: *//p' | head -1)"
NEXT="$(printf '%s\n' "$OUT" | sed -n 's/^next: *//p' | head -1)"
case "$STATUS" in
  "update required"*|"update available"*|"re-run install"*) ;;
  *) exit 0 ;;
esac

MSG="The ai-factory engine in this project is behind: $STATUS

Before anything else - before answering the user's first message or starting any other work - update it:
1. Run \`$NEXT\` from the project root.
2. Read its output. Tell the user in one or two lines what moved (the version line) and pass on every \`Action needed:\` line, \`new setting:\` line and changed template it prints. For an update required, do what the Action needed lines say before going on, or stop and ask the user if a line needs their decision.
3. Tell the user the submodule pointer (if any) and factory/installed.txt changed and need committing. Do not commit unless they ask.
If the update fails - a dirty or diverged engine, no network - stop and tell the user what it printed. Do not work around it.
Then carry on with what the user asked. Do not check the version again in this session."

# caveman: JSON by hand - no jq on every machine. backslashes, quotes and
# newlines are all a message like this can hold.
ESC="$(printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESC"
exit 0
