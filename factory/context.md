# Project context

caveman: this repo IS the harness. self-development mode. every rule here is
about changing the factory itself, not about a product it builds.

## Stack

- language / runtime: POSIX-ish bash, targeting macOS `/bin/bash` 3.2 and GNU
  bash alike. no associative arrays, no `mapfile`, no `${x^^}`.
- everything else is markdown that a model reads: skills, personas, templates.
- package manager: none. no dependencies, on purpose.

## Commands

- test: `bash scripts/selftest.sh` (~12s, no network, no agy, no money)
- one area: `bash scripts/selftest.sh --only lock`
- keep the sandbox to poke at: `bash scripts/selftest.sh --keep`
- syntax check: `bash -n scripts/*.sh install.sh`
- where am I: `bash scripts/factory_env.sh`

## Layout

- `skills/*/SKILL.md` - instructions for Claude. prose, unverifiable by script.
- `scripts/*.sh` - the machinery. real code, covered by the selftest.
- `scripts/factory_common.sh` - shared bones. sourced, never executed.
- `personas/` - lenses for `/factory-think`. `personas/engine/` loads only here.
- `templates/` - shapes for brief, spec, handoff, ADR, memory, improvements.
- `PRINCIPLES.md` - the rules every skill obeys. numbered, and the numbers are
  referenced from skills, so renumbering is a breaking change.

## Conventions

- **caveman comments.** Every non-obvious block opens with `# caveman:` and one
  plain sentence saying why it exists, not what it does.
- **Every script sources `factory_common.sh`** through the four-line bootstrap
  at its top. That bootstrap is the only duplicated code, and it has to be.
- **No `set -e` in `selftest.sh`** - a failed assertion must report and keep
  going. Every other script uses `set -euo pipefail`.
- **In-place edits are `sed -i.bak` then `rm`**, never bare `sed -i` (GNU-only)
  or `sed -i ''` (BSD-only).
- Prose changes go with a `builder` persona read; script changes go with a
  selftest case. Neither substitutes for the other.

## Gotchas

- **`pipefail` + a glob that matches nothing.** `ls foo-* | wc -l` fails the
  whole pipeline and `set -e` kills the script, silently and with no output.
  Use `factory_count` / `factory_newest`, which end in `|| true`.
- **The logs are the round counter.** Anything that changes log filenames
  changes `MAX_ROUNDS` accounting. Two rounds in one second used to share a
  filename and one round vanished.
- **Never `install_one` a script onto itself.** In self mode the sources are
  already in `scripts/`, and `install_one` deletes the destination before
  linking - it would delete the original.
- **The selftest copies the working tree, not `git clone`.** A clone tests HEAD,
  which is exactly the version you are not changing.
- **Sandbox paths must be `pwd -P`'d.** `$TMPDIR` ends in a slash and `/var` is
  a symlink to `/private/var`; git normalises both, so raw paths never match
  what the runner prints.
- `PRINCIPLES.md` numbers are cited by skills. Insert at the end, or fix every
  reference in the same commit.
