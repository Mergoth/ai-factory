# Changelog

What changed in the engine, release by release, for the people who run it in a
project. Newest first. `install.sh --update` prints the entries between the
version you had and the one you got.

Versions follow semver, read from the client's side:

- **major** - update required. Something a project relies on changed shape: a
  file it owns, a `factory.env` setting, a handoff or spec format, a command.
  The entry says what to do, under `Action needed:`.
- **minor** - update available. New skills, settings, checks. Nothing to do
  beyond `install.sh --update`.
- **patch** - fixes only.

Releases are automatic: every PR merged to `main` is one. The PR title picks
the bump - `feat!:` (or `BREAKING CHANGE` in the body) major, `feat:` minor,
anything else patch - and `.github/workflows/release.yml` writes `VERSION`, adds
the entry here, tags `v<version>` and publishes a GitHub release. Lines in the
PR body that start with `Action needed:` are copied into the entry.
`scripts/factory_version.sh` compares a project against the newest tag.

## 1.1.0 - 2026-10-23

- The session hook works in fresh git worktrees, like the ones the Claude
  desktop app makes per session. `git worktree add` leaves submodules empty, so
  the hook command now inits the engine submodule only (no other submodule,
  so one you cannot clone does not block it) when its `VERSION` is missing,
  skips the session script quietly when the fetch fails, takes the repo root from git rather than `$CLAUDE_PROJECT_DIR`, and
  has a 120 s timeout. After an init, `factory_session_start.sh` returns
  `"reloadSkills": true` so the `/factory-*` skills load in that same session.
- `install.sh --update` rewrites an existing session hook command (the 1.0.0
  one or a hand-edited one) in place instead of leaving it alone.

Commit `.claude/settings.json` after `--update` - its hook command changed.

## 1.0.0 - 2026-10-23

First versioned release. Everything before it is this release too: installs
that predate it record no version and are treated as older than 1.0.0.

- `VERSION`, this changelog, and `v*` release tags, cut automatically on every
  merge to `main` by `.github/workflows/release.yml`.
- `scripts/factory_version.sh`: installed vs engine vs newest release, and
  whether the project is up to date, behind, or must update.
- A Claude Code `SessionStart` hook in `.claude/settings.json`: every new
  session checks the version and, when behind, the agent updates the engine
  before doing anything else.
- `factory/installed.txt` records the engine version, also for copied installs
  with no git history of their own.
- `install.sh --update` prints the changelog entries the update brought in.
- Already shipped before versioning: `/factory-think`, `/factory-spec`,
  `/factory-build`, `/factory-check`, `/factory-reflect`, the project brain in
  `factory/`, self-development mode, the selftest suite, the upstream
  improvements inbox, and `install.sh --update`.

Action needed: commit `factory/installed.txt` and `.claude/settings.json` after
your next `--update`, so the version and the session hook reach the whole team.
