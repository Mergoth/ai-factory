# Field notes — first full run of the factory

caveman: what broke, what held, what to change. written from one real project, not theory.

Source run: `second-brain-mcp`, 2026-08-16. Greenfield repo → 119 tests, 11 MCP tools, 3
increments, 6 agy rounds, all on one model tier. Engine at `a64b6f6`.

The headline finding, because everything else follows from it:

> **Every single agy round passed its own tests and still contained a real defect.** Six rounds,
> three increments, three different failure classes. Not one was visible in the test output.

That is not an argument against the loop — the loop caught all three. It is an argument that
`/factory-check` is the load-bearing part of this system, and that its instructions should be
sharpened more aggressively than the build side.

---

## 1. What the loop caught (and how)

| # | Defect | How it was caught | Would tests have caught it? |
|---|---|---|---|
| 1 | **RCE.** `search_vault` appended a model-controlled query to `rg` as a bare positional, so `--pre=<script>` executed arbitrary commands | Running the exploit by hand during check | No — the call returns an empty result list; nothing looks wrong |
| 2 | **Truncated agy run reporting success.** Log ended mid-sentence, no `RESULT:`, no `WALKTHROUGH:`, correct source, **zero tests**, `agy exit code: 0` | Test count unchanged at 70 | No — the suite was green, it just never grew |
| 3 | **Format corruption.** `append_log` prefixed a bullet, adding a third line shape to a file that already had two and serves as an audit tripwire | Reading the resulting file after driving the tool | No — the tests assert append-only behaviour, which holds either way |

Three distinct lessons: **behavioural claims need execution, not assertions**; **agy's exit code
and report are both untrustworthy**; **output format needs eyeballing, not just parsing**.

---

## 2. Proposals for `factory-check`

### 2.1 Add a "verify by execution" step for security and behaviour claims

Current step 3 says "find the evidence in the diff or in the code". That is how defect #1 nearly
shipped: the code *looked* correct, the criteria all passed, and only running the attack proved
otherwise.

Proposed addition to `factory-check/SKILL.md`:

> **3b. Execute the claim, don't read it.** For any done criterion phrased as a behaviour — "X is
> rejected", "Y cannot escape", "Z is validated" — construct the input that would violate it and
> run it. A grep proves a string is absent; it does not prove a behaviour holds. Where the criterion
> is a security boundary, the check is not done until you have tried to cross it and failed.
> Side-effect attacks (command execution, file writes outside a root) must be checked by looking
> for the side effect, not the return value — the return value of a successful attack is often
> empty and innocuous.

### 2.2 Make "test count did not increase" a first-class red flag

Defect #2 was caught only because the checker happened to compare counts. Add to step 7:

> - **the test count did not increase** while the handoff asked for new tests. A green suite that
>   did not grow is the signature of a truncated or skipped run, not of an easy task.

### 2.3 Treat a missing `WALKTHROUGH:` as a failed round, not a shrug

Current instruction: "No `WALKTHROUGH:` block in the log at all -> note it, and judge on the diff
alone. Do not fail the round for it; older logs predate this."

That carve-out is now wrong more often than it is right. A missing walkthrough on a run that also
produced no tests is the tell that agy was cut off mid-flight while still exiting 0. Suggested
replacement:

> No `WALKTHROUGH:` block **and** no `RESULT:` block -> the run was truncated. Status is
> `Needs fix` regardless of test state, and the next-fix bullet names what is missing. A missing
> walkthrough on an otherwise complete log (report present, tests grew) is still a note, not a
> failure.

### 2.4 Read the artefact, not only the assertion

Defect #3 needs its own instruction because it is a whole class:

> When a tool writes a file, **open the file**. Tests assert what the author thought to assert;
> they routinely cover behaviour (appended, did not truncate) while missing shape (format, ordering,
> encoding, trailing newline). If the change produces a durable artefact — a log line, a frontmatter
> block, a filename, a serialized record — put one instance of it in the status block verbatim so a
> human can see the shape.

---

## 3. Proposals for `factory-spec`

### 3.1 Grep-shaped done criteria are weaker than they look

Two failures traced to this. In round 1 of increment 1, the criterion
`grep -rE "unlink|os\.remove|shutil\.rmtree" src/` matched **comments**, and agy satisfied it by
rewording the comments. The underlying rule (no delete calls) was genuinely honoured, so this was
not cheating — but the criterion measured spelling, not behaviour.

> Prefer a criterion that runs the code over one that greps it. Keep greps for *structural* rules
> where the string genuinely is the thing ("no `startswith` in `paths.py`"), and write behavioural
> rules as named tests instead. When you do write a grep, ask what a comment, a docstring, or a
> `.pyc` would do to it — all three produced false results in this run.

### 3.2 Say what the chokepoint covers, in full

The RCE existed because the spec said "every caller-supplied **path** goes through `resolve()`".
`glob`, `scope`, and `query` are caller-controlled strings that reach the filesystem and a
subprocess without being paths, so they were outside the rule as written and nobody noticed.

> When specifying a security chokepoint, enumerate the *inputs it covers*, not the argument names
> it expects. "Every caller-controlled string that reaches the filesystem or a subprocess" would
> have prevented this; "every path argument" did not.

### 3.3 A handoff should say what is *not* verifiable on this machine

Docker's daemon was down for the whole run. Saying so in the handoff — "write the artefacts, do not
claim the image builds, list it under `not covered`" — produced an honest walkthrough instead of a
fabricated success claim. Worth making standard:

> **Environment limits.** If something in scope cannot be verified here (no daemon, no network, no
> credentials), say so in the handoff and instruct the builder to declare it uncovered. A builder
> that cannot verify and is not told so will usually claim success.

---

## 4. Proposals for `factory-think`

The four-persona round table earned its cost. Concretely, from one run:

- **operator** went and read the *real* target data and found that `EPAM/` is a **sibling** of the
  vault root, not a child — turning an abstract confinement requirement into a concrete one-`..`
  traversal case.
- **skeptic** checked the spec's own cited evidence and found it misattributed: the spec claimed
  sync-conflict files proved a risk, and there were zero of them in the relevant tree. That
  prevented building merge logic nobody needed.
- **skeptic** alone noticed a file was being asked to serve as both machine audit trail and human
  tripwire, which became a design decision.
- **product vs skeptic** disagreed on phase ordering, and **architect** dissolved it structurally
  rather than either side winning.

Two changes suggested by the run:

### 4.1 Tell personas to read the real data, not only the repo

The single highest-value finding came from a persona reading files *outside* the repo — the actual
vault the software would operate on. Suggested addition to the persona prompt template:

> If the change operates on real data that exists on this machine, read a representative sample of
> it. The spec describes what the author believed; the data shows what is true. Cite paths.

### 4.2 Ask personas to check the request's own citations

The skeptic's best find was that the source spec cited evidence that did not exist. Add to the
skeptic charter:

> Verify the request's own evidence. When it says "X proves Y", go look at X. Specs cite from
> memory and are wrong often enough to be worth checking.

---

## 5. Proposals for `PRINCIPLES.md`

### 5.1 Sharpen #3 with the observed failure mode

Current: *"`agy` exits 0 when it failed, and a report is a claim, not evidence."*

Observed something stronger: agy exited 0 **and** produced correct code **and** a green test suite,
while having been cut off before writing any tests. Suggested amendment:

> A truncated run looks identical to a successful one from the outside: exit 0, green suite,
> plausible files. The only reliable tells are structural — did the log end with a `RESULT:` block,
> and did the thing the handoff asked for actually appear. Check both, every round.

### 5.2 Add a principle about criteria that measure the wrong thing

Nothing in `PRINCIPLES.md` currently covers this, and it caused two of three defects:

> **N. A criterion measures what it measures.** "Checkable" is necessary, not sufficient. A grep
> checks spelling, a passing test checks the assertion its author wrote, and neither checks the
> behaviour you meant. Before accepting a criterion, ask what a malicious, lazy, or truncated run
> could do to satisfy it without doing the work.

---

## 6. Autonomy — what actually blocked it

The session ran unattended across three increments. What stopped it being fully autonomous, in
descending order of cost:

1. **Harness misconfiguration that fails late.** `TEST_CMD` was the unedited template default
   (`pytest -q`) invoking a `pytest` that was not installed, on a Python below the SDK's floor. That
   would have burned a paid round on `command not found`. **Proposal: `/factory-spec` should run
   `TEST_CMD` once and refuse to write a handoff if it does not exit cleanly on an empty-but-valid
   suite.** Discovering this costs seconds up front and a full round otherwise.

2. **`factory/context.md` silently dropped.** `run_antigravity.sh:90` greps for the template marker
   and drops the file — correct behaviour, but silent, and the consequence (builder gets no stack,
   no conventions, re-decides everything every round) is invisible until you read the log. Worse:
   the marker string appearing *anywhere* in the file triggers it, so a context file that mentions
   the marker in its own gotchas section drops itself. That happened during this run.
   **Proposal: print a loud warning to stdout, not stderr, and match the marker only on the first
   line.**

3. **`pytest` exits 5 on empty collection**, which reads as a failed round. Round 1 of a greenfield
   project is exactly when the suite might legitimately be empty. **Proposal: mention this in the
   spec template's Notes section as a standing gotcha for Python projects.**

4. **No baseline commit.** With zero commits, `/factory-check`'s strongest check (walkthrough vs.
   `git diff`) is inert, and the only rollback verb is `git clean -fd`, which deletes the untracked
   spec you are building from. **Proposal: `/factory-spec` should refuse to write a handoff in a
   repo with no commits, and say why.** PRINCIPLES #10 correctly forbids the agent committing, so
   this must be a stop-and-ask, not an auto-commit.

5. **Scaffolding that the first round must invent.** Round 1 wrote `pyproject.toml`, `uv.lock`, the
   package skeleton, *and* the feature. Bootstrapping those by hand first — and verifying the test
   command green — meant the builder spent its round on the actual problem. **Proposal: add an
   explicit "bootstrap before first build" note to `factory-spec` for greenfield repos.**

---

## 7. What held up well

Worth recording so it does not get refactored away:

- **ADRs are the highest-leverage artefact.** They were the only thing that survived across rounds
  and made "you broke ADR-0002" a check the builder could not argue with. The
  `run_antigravity.sh` ADR block firing only when `factory/adr/` is non-empty is right.
- **The brief's `Rejected` list did real work.** It caught the checker's own temptation to
  re-propose a persistent search index and a phase reorder that had already been decided against.
- **Separating WHY / WHAT / CONTRACT into three files.** Six months from now the brief is the only
  file that explains why confinement is absolute, and it says so with the exploit that proved it.
- **`Difficulty:` → model tier.** `tricky` on the confinement increment was correct; the failure
  there was contract scope, not model capability, and no cheaper model would have done better.
- **The status-block-append pattern.** Reading three `## Check` blocks in one handoff is a genuine
  history of what was tried, and it is what made the "test count unchanged" comparison possible.
