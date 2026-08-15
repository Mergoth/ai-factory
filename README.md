# ai-factory

Small AI factory for one repo. Claude Code writes the spec, the
[Antigravity CLI](https://antigravity.google) (`agy`) writes the code, Claude
Code checks the result.

Three moving parts, no magic:

| Part | Who runs it | What it does |
|---|---|---|
| `/factory-spec` | Claude Code | reads the code, writes `specs/<slug>.md` + `handoffs/<ts>-<slug>.md` |
| `scripts/run_antigravity.sh` | your shell | calls `agy` with that contract, tees the log to `handoffs/` |
| `/factory-check` | Claude Code | re-runs the tests, appends a Success / Needs fix block to the handoff |

The handoff file is the contract. It is the only thing the three parts share.

## Install into a project

The harness lives in this repo and is pulled into a project as a submodule, so
one copy serves every project you use it in.

```bash
cd /path/to/your-project
git submodule add https://github.com/Mergoth/ai-factory .factory
bash .factory/install.sh
```

`install.sh` symlinks the harness into the paths Claude Code and `agy` look at,
then creates the working directories:

```
your-project/
  .factory/                       # submodule, the harness
  .claude/skills/factory-spec     -> .factory/skills/factory-spec
  .claude/skills/factory-check    -> .factory/skills/factory-check
  .agents/skills                  -> .factory/agents/skills
  scripts/run_antigravity.sh      -> .factory/scripts/run_antigravity.sh
  factory.env                     # real file, yours, per project
  specs/                          # feature specs
  handoffs/                       # contracts + logs
```

Symlinks mean improvements to the harness reach every project with
`git submodule update --remote .factory`. Nothing is copied, so nothing drifts.
On a filesystem without symlinks, use `bash .factory/install.sh --copy` and
re-run it after each update.

Then set your test command:

```bash
$EDITOR factory.env      # TEST_CMD="pytest -q"  (or npm test, go test ./..., ...)
```

## Use it

**1. Spec.** In Claude Code:

```
/factory-spec add rate limiting to the public API
```

Claude reads the code and writes two files:

```
specs/api-rate-limit.md
handoffs/20260815T142211Z-api-rate-limit.md
```

Read the handoff before running anything. It has Goal, Files to touch, Tests to
run, Done criteria. If it is wrong, say so and Claude rewrites it — that is far
cheaper than letting `agy` build the wrong thing.

**2. Build.** In a shell:

```bash
bash scripts/run_antigravity.sh api-rate-limit
```

This calls `agy --print` with a prompt pointing at the spec and handoff, and
saves everything to `handoffs/logs-<ts>-api-rate-limit.txt`. Add `--dry-run` to
see the exact prompt and command without calling `agy`.

`agy` changes code and runs tests. It does not commit, branch, or push — the
diff is left in your working tree for you to review.

Two things about `agy` the runner works around, worth knowing if you edit the
prompt:

- **It does not inherit your shell's cwd.** In `--print` mode its terminal
  starts in `~/.gemini/antigravity-cli/scratch`. The runner passes `--add-dir`,
  writes every path in the prompt as absolute, and tells `agy` to prefix each
  command with `cd <repo root>`. Drop that and it will hunt across your whole
  filesystem for `specs/` and report the spec as missing.
- **Its exit code is 0 even when the build fails.** A blocked run and a clean
  run both exit 0, so the exit code is not a signal. The report in the log and
  the actual test run are what count — which is why `/factory-check` re-runs
  the tests itself.

**3. Check.** Back in Claude Code:

```
/factory-check api-rate-limit
```

Claude reads the spec, the handoff, the log and `git diff`, **re-runs the tests
itself** rather than trusting the log, and appends a block to the handoff:

```markdown
## Check 20260815T145533Z

Status: Needs fix
Tests: 2 failed, 41 passed

- [x] limiter rejects over 100 req/min
- [ ] 429 response includes Retry-After header
- red flag: test_burst_allowance was marked skip, not fixed

### Next fix
- set Retry-After on the 429 path in api/middleware.py
- un-skip test_burst_allowance and make it pass
```

**4. Loop.** `Needs fix` means run step 2 again — the next-fix bullets are in
the handoff, so `agy` picks them up on the same contract. Repeat until
`Status: Success`.

To automate the checking, use Claude Code's built-in `/loop`:

```
/loop 5m /factory-check api-rate-limit
```

That re-runs the check every five minutes. `/factory-check` prints `DONE` when
the status is Success, which is your signal to stop the loop.

## Safety

- **Network:** the only outbound call is `agy` itself. Nothing else phones home.
- **Side effects stay in the repo:** `run_antigravity.sh` `cd`s to the repo root
  and runs `agy` there. `agy` is told not to commit, push, or branch.
- **`--dangerously-skip-permissions`** is passed to `agy` on purpose — `--print`
  is non-interactive, so a permission prompt would hang forever with nobody to
  answer it. This is the real trade: `agy` gets unattended tool access inside
  the repo. Use `--dry-run` first on a new project, and review the diff before
  committing anything.
- **Separation of duties:** `agy` never edits `specs/` or `handoffs/`;
  `/factory-check` never edits code. Neither one grades its own work.
- **No secrets:** `factory.env` holds a test command, a model name, and a
  timeout. Keep credentials out of it — it is committed to your project repo.
- **Logs are gitignored** (`handoffs/logs-*.txt`) since they can be long and may
  echo local paths. The handoff and its status blocks are committed; those are
  the record worth keeping.

## Requirements

- `agy` on `PATH` — [Antigravity CLI](https://antigravity.google)
- `git`, `bash`, `awk`
- Claude Code, for the two skills

## Layout of this repo

```
install.sh                     # symlink harness into a target repo
skills/factory-spec/SKILL.md   # Claude: write spec + handoff
skills/factory-check/SKILL.md  # Claude: verify, write status
scripts/run_antigravity.sh     # call agy, tee log
agents/skills/                 # agy-side skills (empty by design)
templates/spec.md              # shape of a spec
templates/handoff.md           # shape of a handoff
factory.env.example            # per-project config template
```

## License

MIT
