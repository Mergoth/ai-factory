# ai-factory

Small AI factory for one repo. Claude Code writes the spec, the
[Antigravity CLI](https://antigravity.google) (`agy`) writes the code, Claude
Code checks the result.

Four moving parts, no magic:

| Part | Who runs it | What it does |
|---|---|---|
| `/factory-think` | Claude Code | runs four personas in parallel over the code, writes `factory/briefs/<slug>.md` — the WHY |
| `/factory-spec` | Claude Code | reads the brief and the code, writes `specs/<slug>.md` + `handoffs/<ts>-<slug>.md` |
| `/factory-build` | Claude Code | launches `agy`, waits, verifies, re-runs until pass or cap |
| `scripts/run_antigravity.sh` | Claude or your shell | calls `agy` with that contract, tees the log to `handoffs/` |
| `/factory-check` | Claude Code | re-runs the tests, checks the walkthrough against the diff, appends a verdict |

Files are the only thing these parts share, which is what lets Claude and `agy`
hand work back and forth without a shared session. The rules they all obey are in
[`PRINCIPLES.md`](PRINCIPLES.md) — one page, worth reading before you change
anything here.

## Install into a project

The harness lives in this repo and is pulled into a project as a submodule, so
one copy serves every project you use it in.

```bash
cd /path/to/your-project
git submodule add https://github.com/Mergoth/ai-factory factory-engine
bash factory-engine/install.sh
```

`install.sh` symlinks the harness into the paths Claude Code and `agy` look at,
then creates the working directories:

```
your-project/
  factory-engine/                       # submodule, the harness
  .claude/skills/factory-think    -> factory-engine/skills/factory-think
  .claude/skills/factory-spec     -> factory-engine/skills/factory-spec
  .claude/skills/factory-build    -> factory-engine/skills/factory-build
  .claude/skills/factory-check    -> factory-engine/skills/factory-check
  .agents/skills                  -> factory-engine/agents/skills
  scripts/run_antigravity.sh      -> factory-engine/scripts/run_antigravity.sh
  factory.env                     # real file, yours, per project
  factory/                        # YOUR project brain
    context.md                    #   how this repo works
    adr/                          #   binding decisions
    briefs/                       #   why each feature exists
    memory.md                     #   lessons from past runs
    personas/                     #   extra lenses, empty by default
    prompt-extra.md               #   raw orders for the builder
  specs/                          # feature specs
  handoffs/                       # contracts + logs
  .factory-cache/                 # gitignored, cached model list
```

Two directories, and the split is the whole idea:

- **`factory-engine/`** — the machinery. Vendored, replaced wholesale on update.
  Never edit it; your changes would be blown away and belong upstream anyway.
- **`factory/`** — your project's own knowledge. Seeded once, then yours forever.

Symlinks mean improvements to the harness reach every project with
`git submodule update --remote factory-engine`. Nothing is copied, so nothing
drifts.
On a filesystem without symlinks, use `bash factory-engine/install.sh --copy` and
re-run it after each update.

Then set your test command:

```bash
$EDITOR factory.env      # TEST_CMD="pytest -q"  (or npm test, go test ./..., ...)
```

## Teaching it about your project

`factory-engine/` is the vendored harness — never edit it. **`factory/` is yours**,
and it is how one generic harness becomes specific to this codebase. `install.sh`
seeds it; fill in what is useful and skip the rest.

| File | What it is | Who reads it |
|---|---|---|
| `factory/context.md` | stack, commands, layout, conventions, gotchas | all |
| `factory/adr/` | architecture decisions, numbered. **Binding.** | all |
| `factory/memory.md` | one-line lessons from past runs | builder, spec |
| `factory/briefs/` | why each feature was built, what was rejected | all |
| `factory/personas/` | extra lenses for `/factory-think` | think |
| `factory/prompt-extra.md` | raw orders pasted into the builder prompt | builder |

Each has a distinct job, and keeping them apart is what stops the whole thing
turning into one sprawling prompt:

- **`context.md`** — things always true about the repo. Where code lives, how to
  run it, what a good test looks like here.
- **`adr/`** — decisions with consequences. `/factory-check` treats a broken ADR
  as `Needs fix` **even when every test passes**, because tests do not encode
  architecture. `/factory-spec` offers to write one when a change decides
  something structural, and refuses to quietly violate an existing one.
- **`memory.md`** — what went wrong last time. "Flash models keep missing the
  retry decorator in `api/`." `/factory-build` appends a line when a round
  teaches something, and is told to keep it under ~40 lines and delete stale
  entries — a wrong memory costs more than no memory.
- **`briefs/`** — written by `/factory-think`, one per feature. The only file
  that answers "why is it like this" six months later, and the only one holding
  the alternatives you rejected, so nobody re-proposes them.
- **`personas/`** — drop a markdown file here and it joins the `/factory-think`
  round table on the next run. No re-install, nothing to register; a file whose
  name matches a built-in replaces it. Add `security.md` or `data.md` when the
  default four keep missing a concern this project actually has. See
  [`personas/README.md`](personas/README.md).
- **`prompt-extra.md`** — the escape hatch, when you want to tell the builder
  something directly without forking the harness.

Files still holding their seeded `factory:template` marker are treated as
unfilled and **not** sent to `agy` — blank headings would read as project facts.
Delete the marker line when you fill one in. Nothing here is required; an empty
`factory/` just means the builder works from the spec alone.

## Use it

**1. Think.** In Claude Code:

```
/factory-think add rate limiting to the public API
```

Four personas — **product, architect, skeptic, operator** — read the codebase in
parallel, blind to each other, each as a read-only subagent so none of them can
touch code. Then Claude reconciles them and writes:

```
factory/briefs/api-rate-limit.md
```

The brief holds what the spec cannot: why this is worth building, what "done"
looks like from outside, which alternatives were rejected and why, and every
assumption taken where the request was ambiguous.

Blind and parallel is the whole trick. Run in sequence they read each other and
converge on whatever the first one said; run blind they disagree, and the
disagreements are the findings. Consensus that arrives instantly usually means
four agents read the same README.

They will not interrogate you. Personas cannot ask anything at all; only the
synthesis step can, capped at **three questions, asked once, together**, and only
where two readings genuinely produce different code. Everything else becomes a
line under Assumptions, which you can veto at a glance.

Skip this step for a rename or a typo — four subagents to decide on a rename is
theatre, and the skill will tell you so itself.

**2. Spec.** Chains automatically from the brief, or run it alone:

```
/factory-spec add rate limiting to the public API
```

Claude reads the brief and the code and writes two files:

```
specs/api-rate-limit.md
handoffs/20260815T142211Z-api-rate-limit.md
```

Read the handoff before running anything. It has Goal, Files to touch, Tests to
run, Done criteria. If it is wrong, say so and Claude rewrites it — that is far
cheaper than letting `agy` build the wrong thing.

**3. Build.** In Claude Code:

```
/factory-build api-rate-limit
```

Claude prints the handoff's goal and done criteria, launches `agy` in the
background, waits for it to exit, verifies the result, and re-runs `agy` with
the fix bullets until the tests pass or `MAX_ROUNDS` (default 3) is hit. You do
not have to sit in the terminal for it.

The run has to be backgrounded because Claude Code caps foreground shell
commands at 10 minutes and an `agy` run can be longer. `/factory-build` handles
that; it is only worth knowing if you rewrite the skill.

If you would rather drive it by hand, the script is a normal script:

```bash
bash scripts/run_antigravity.sh api-rate-limit
```

This calls `agy --print` with a prompt pointing at the spec and handoff, and
saves everything to `handoffs/logs-<ts>-api-rate-limit.txt`. Add `--dry-run` to
see the exact prompt and command without calling `agy`.

`agy` changes code and runs tests. It does not commit, branch, or push — the
diff is left in your working tree for you to review.

### The walkthrough

`agy` does not just report pass/fail. Its report ends with a walkthrough:

```
WALKTHROUGH:
  how it works    - the flow after the change, in order, naming real functions
  why             - each choice a reviewer would question, and the reason
  verify by hand  - exact commands to watch it work, not the test suite
  not covered     - what it did not test, and what it is unsure about
```

This is not decoration. `/factory-check` reads it **against `git diff`**, which
catches a failure class the tests cannot: a walkthrough describing code that was
never written. That is `Needs fix` regardless of a green suite, as is a "why"
that contradicts an ADR or re-proposes something the brief already rejected.

The other half is for you. After an unattended loop, "verify by hand" is the one
thing worth having — a command that shows you the feature working, rather than a
test suite asserting that it does.

### Model selection

**No model ids are configured anywhere.** They rotate — a whole new family
appeared while this README was being written — so a pinned id rots silently and
costs you a failed round to discover.

- **The spec says how hard, not which model.** `/factory-spec` writes a
  `Difficulty:` line (`mechanical` / `normal` / `tricky`) into the handoff.
- **The build agent picks.** `/factory-build` runs `agy models`, reads today's
  real list, maps difficulty to a family and tier, and passes `--model`.
  Cheap flash for a rename, the strongest thinking model for tricky logic. It
  steps up a tier when a round fails on correctness rather than re-rolling the
  same model against the same contract.
- **The script validates and falls back.** The chosen id is checked against the
  live list, so a dead id is caught without burning a call. If `agy` itself
  fails to run, the script tries other models — **preferring a different
  family**, since three tiers of one family all die together when that family
  is down.

The fallback triggers on `agy` exiting non-zero — a bad id, quota, transport
failure. It deliberately does **not** trigger when `agy` runs fine but the build
fails, because that is the builder's problem, not the model's, and retrying it
on three models would just cost three times as much to fail the same way.

The list is cached in `.factory-cache/` (gitignored) for `MODELS_TTL_MIN`
minutes, since the fetch is a slow network call and every round would otherwise
pay it. Force a refresh with `--refresh-models`.

```bash
bash scripts/run_antigravity.sh api-rate-limit --model <id from agy models>
```

Two more things about `agy` the runner works around, worth knowing if you edit
the prompt:

- **It does not inherit your shell's cwd.** In `--print` mode its terminal
  starts in `~/.gemini/antigravity-cli/scratch`. The runner passes `--add-dir`,
  writes every path in the prompt as absolute, and tells `agy` to prefix each
  command with `cd <repo root>`. Drop that and it will hunt across your whole
  filesystem for `specs/` and report the spec as missing.
- **Its exit code is 0 even when the build fails.** A blocked run and a clean
  run both exit 0, so the exit code is not a signal. The report in the log and
  the actual test run are what count — which is why `/factory-check` re-runs
  the tests itself.

**4. Check.** Back in Claude Code:

```
/factory-check api-rate-limit
```

Claude reads the brief, the spec, the handoff, the log and `git diff`, **re-runs
the tests itself** rather than trusting the log, checks the walkthrough against
the diff, and appends a block to the handoff:

```markdown
## Check 20260815T145533Z

Status: Needs fix
Tests: 2 failed, 41 passed
Walkthrough: matches diff

- [x] limiter rejects over 100 req/min
- [ ] 429 response includes Retry-After header
- red flag: test_burst_allowance was marked skip, not fixed

### Next fix
- set Retry-After on the 429 path in api/middleware.py
- un-skip test_burst_allowance and make it pass
```

With a brief present it also asks the harder question: is "What done looks like"
actually true now? Code that ticks every checkbox while missing the point is the
expensive failure, and the checkbox list is exactly where it hides.

**5. Loop.** `/factory-build` already loops, so normally there is nothing to do
here. If you are driving by hand, `Needs fix` means run step 3 again — the
next-fix bullets are in the handoff, so `agy` picks them up on the same
contract. Repeat until `Status: Success`.

To watch a long-running job instead of driving it, use Claude Code's built-in
`/loop`:

```
/loop 5m /factory-check api-rate-limit
```

That re-runs the check every five minutes. `/factory-check` prints `DONE` when
the status is Success, which is your signal to stop the loop.

### Which one to use

- `/factory-think` — when you are not yet sure what should be built, or the
  request is vague enough that two people would build different things.
- `/factory-spec` straight away — when you already know exactly what you want and
  the brief would just be ceremony.
- `/factory-build` — the normal path once a handoff exists. Hands-off until it
  passes or gives up.
- `run_antigravity.sh` + `/factory-check` — when you want to inspect the diff
  between every round, or you are debugging the harness itself.
- `/loop /factory-check` — when something else is running the builds and you
  only want to poll the verdict.

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
  `/factory-check` and `/factory-build` never edit code. Nothing grades its own
  work.
- **Personas are read-only by construction.** They run as `Explore` subagents,
  which have no write tools — a thinking step cannot quietly become a building
  step, and that is enforced by the harness rather than by asking nicely.
- **Bounded loop:** `/factory-build` stops at `MAX_ROUNDS` (default 3), and
  earlier if two rounds produce the same failure. It will not spend your money
  in a circle, and it asks before raising its own cap.
- **No secrets:** `factory.env` holds a test command, a round cap, and timeouts.
  Keep credentials out of it — it is committed to your project repo.
- **Logs are gitignored** (`handoffs/logs-*.txt`) since they can be long and may
  echo local paths. The handoff and its status blocks are committed; those are
  the record worth keeping.

## Requirements

- `agy` on `PATH` — [Antigravity CLI](https://antigravity.google)
- `git`, `bash`, `awk`
- Claude Code, for the four skills

## Layout of this repo

```
PRINCIPLES.md                  # the rules every skill obeys
install.sh                     # symlink harness into a target repo
skills/factory-think/SKILL.md  # Claude: run personas, write brief
skills/factory-spec/SKILL.md   # Claude: write spec + handoff
skills/factory-build/SKILL.md  # Claude: drive agy, loop, verify
skills/factory-check/SKILL.md  # Claude: verify, write status
personas/product.md            # lens: who hurts, what done looks like
personas/architect.md          # lens: where it lands, what it couples to
personas/skeptic.md            # lens: what it assumes, where it breaks
personas/operator.md           # lens: test, fail loudly, roll back
scripts/run_antigravity.sh     # call agy, tee log
agents/skills/                 # agy-side skills (empty by design)
templates/brief.md             # shape of a brief
templates/spec.md              # shape of a spec
templates/handoff.md           # shape of a handoff
templates/context.md           # seeds factory/context.md
templates/memory.md            # seeds factory/memory.md
templates/adr.md               # shape of an ADR
templates/prompt-extra.md      # seeds factory/prompt-extra.md
factory.env.example            # per-project config template, no model ids
```

## License

MIT
