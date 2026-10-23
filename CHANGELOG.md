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

Every release is a `VERSION` bump, an entry here, and a `v<version>` tag on
`main`. `scripts/factory_version.sh` compares a project against the newest tag.

## 1.0.0 - 2026-10-23

First versioned release. Everything before it is this release too: installs
that predate it record no version and are treated as older than 1.0.0.

- `VERSION`, this changelog, and `v*` release tags.
- `scripts/factory_version.sh`: installed vs engine vs newest release, and
  whether the project is up to date, behind, or must update. `/factory-check`
  runs it and passes a "behind" on to you.
- `factory/installed.txt` records the engine version, also for copied installs
  with no git history of their own.
- `install.sh --update` prints the changelog entries the update brought in.
- Already shipped before versioning: `/factory-think`, `/factory-spec`,
  `/factory-build`, `/factory-check`, `/factory-reflect`, the project brain in
  `factory/`, self-development mode, the selftest suite, the upstream
  improvements inbox, and `install.sh --update`.

Action needed: commit `factory/installed.txt` after your next `--update`, so the
version it now records is shared with the rest of the team.
