<!-- factory:template - delete this line once the first run has written here -->
# Factory improvements

caveman: what this project's runs taught about the factory itself. `/factory-reflect`
appends here after every full run. oldest at top, newest at the bottom.

This file is a queue, not a changelog. Nothing here is applied - `factory-engine/`
is vendored and never edited from a project (PRINCIPLES #9). Carrying an entry
upstream is a human action: a PR against the harness repo.

In this repo the file is also the shared inbox: projects with FACTORY_UPSTREAM
pointing here append their `/factory-reflect` blocks, headed `<project> / <slug>`.

Rules for whoever writes here:
- Target names a real engine file: a skill, a template, a persona, the runner,
  or PRINCIPLES.md. "somewhere in the prompt" is not a target.
- Evidence comes from the run being reflected on. No evidence, no entry.
- Proposal is the wording you would paste into that file, not the wish.
- Five entries per run, maximum.
- A proposal that recurs gets `Seen again:` appended to the original entry.
  Recurrence is stronger evidence, not a new idea.
- `Held -` entries record what worked and must not be refactored away. They are
  as valuable as the proposals and get deleted less often.

<!-- example shape, delete this:

## 20260816T2100Z - vault-search

Run: 2 rounds, gemini-flash then a pro tier, final status Success.

### Behavioural criteria are verified by reading, not executing
Target: `factory-engine/skills/factory-check/SKILL.md`, step 3
Evidence: round 1 passed every criterion; the exploit ran in 4 seconds by hand
Proposal: "For any criterion phrased as a behaviour, construct the input that
would violate it and run it. A grep proves a string is absent; it does not
prove a behaviour holds."

### Held - ADRs survive rounds
Evidence: round 2's walkthrough re-proposed a persistent index; ADR-0002 killed it
Do not remove: without it the same argument is re-litigated every round, and the
builder wins the ones nobody remembers deciding.
-->

## 20261025T1330Z - unibot / rich-output-core

From: `vlaid-unibot`, `factory/improvements.md`

Run: 2 rounds, gemini-3.8-flash-high both times (requested claude-opus-4-6-thinking, then claude-sonnet-4-6), final status Success.

### A requested model skipped by the quota cache must be reported as skipped, not "exit 0"
Target: `scripts/run_antigravity.sh`, the quota_hit reorder and the final "model requested" line
Evidence: round 2 log `logs-20261025T131220Z`. `--model claude-sonnet-4-6` was moved behind the fallback because the `claude` family had hit 429 in round 1 (opus), and the only attempt was gemini-3.8-flash-high. The footer still printed `model requested: claude-sonnet-4-6 (exit 0) -> used: gemini-3.8-flash-high`, which reads as if sonnet ran and succeeded.
Proposal: replace the footer with `model requested: <m> (skipped: <family> quota hit <n>m ago) -> used: <m2>` when the requested model was never attempted, and keep `(exit N)` only for a model that actually ran.

### A fallback that drops below the handoff's Difficulty tier is a warning, not silent
Target: `scripts/run_antigravity.sh` fallback ordering + `scripts/factory_state.sh` `last_model:` line
Evidence: handoff `Difficulty: tricky`; both rounds fell back to a flash tier (round 1: opus 429 mid-run after it had started editing; round 2: quota cache). Round 1's defects (dead `text=` aliases that crash on `ChatResponse(content=...)`, getattr chains added for mocks, a private `_load()` call) are the kind a stronger tier usually avoids. Nothing in the state output flagged the downgrade, so the checker had to notice it.
Proposal: in `factory_state.sh`, after `last_model:`, print `warn: tier downgrade - handoff says <difficulty>, round ran on <model>` when Difficulty is `tricky` and the used model id contains `flash` or `low`; in factory-build step 3, add: "If the state shows a tier downgrade, say so to the user before the next round and offer to wait for the quota reset instead of spending a round."

### Held - executing the dead-looking fallback, not reading it
Evidence: round 1 check. The `ChatResponse(content=text or "")` fallback looked harmless and every test passed; running a one-line probe raised `TypeError: missing ... 'model'`.
Do not remove: factory-check step 3b ("execute the claim"); without it this ships as a latent crash on the first `text=` caller.

### Held - red flag for getattr chains that exist only to fit a test double
Evidence: the round 1 walkthrough's "why" admitted the getattr chain was there "to prevent tests with mock configs from crashing". The step 7 red flag caught it; round 2 fixed the mocks instead (conftest gained `structured_output`).
Do not remove: factory-check step 7, the getattr/alias red-flag bullet.

## 20261025T1900Z - unibot / rich-output-web, rich-output-fixes

From: `vlaid-unibot`, `factory/improvements.md`

Run: rich-output-web 2 rounds (gemini-3.8-flash-high, then gemini-3.8-flash-medium), Success. rich-output-fixes 2 rounds (gemini-3.8-flash-high x2), Success.

### `next: done` should be `next: reflect` until the run has a reflection
Target: `scripts/factory_state.sh`, the `next:` decision
Evidence: both runs ended Success and the next run was chained straight after. `/factory-reflect` was skipped for both and only noticed when the user asked whether the proposals had been submitted. factory-build step 8 says to reflect, but nothing enforced it.
Proposal: "If the last check is Success and `factory/improvements.md` has no `## … - <slug>` heading (or one listing the slug), print `next: reflect` and `resume: /factory-reflect <slug>`; print `done` only once that heading exists."

### A criterion's example input must be the whole payload, not a fragment
Target: `skills/factory-spec/SKILL.md`, step 6, the "Cite the real shape" bullet
Evidence: the rich-output-fixes handoff said "`to_reply` raises for `{"label":""}`". The builder took it literally and added a top-level `label` check to `to_reply`, plus tests for it. That cost the round-2 cleanup.
Proposal: append to the bullet: "When a criterion gives an example input, write the full payload exactly as the function receives it (`{"text":"x","choices":[{"label":""}]}`), never a fragment of it."

### Held - driving shipped UI in a real browser
Evidence: rich-output-web r1 passed lint, both builds and 25 integration tests, yet every assistant bubble blanked the page (`react-markdown` 10 rejects `className`). Only factory-check step 3c, driving the widget in Chromium with stubbed SSE, caught it.
Do not remove: step 3c "When the change ships UI, drive each screen…". Without it, a crash on every reply ships green.

Seen again (on "A requested model skipped by the quota cache must be reported as skipped"): rich-output-web r1 sonnet exit 3 -> flash; rich-output-fixes r1 opus skipped by quota cache, footer said exit 0.

## 20261025T1945Z - unibot / mem0-recall-fix

From: `vlaid-unibot`, `factory/improvements.md`

Run: 2 rounds, claude-sonnet-4-6 both (the requested model actually ran), final status Success.

### Probe the real external service before writing the spec
Target: `skills/factory-spec/SKILL.md`, step 2 (Read the repo)
Evidence: a 1-minute probe against real Mem0, run before the spec, showed that `delete_all(agent_id=…)` wipes every agent's memories. Neither the issue nor the code review had spotted that second bug, and it went into the same contract instead of costing a later run.
Proposal: add to step 2: "When the change depends on an external API's behaviour (filters, deletes, async writes), run a throwaway probe against the real service and cite its output in the spec. The docs say what the API accepts; only a probe says what it does."

### Held - checker reads the files, not a filtered diff
Evidence: a `grep '^[-+][^-+]'` over `git diff` hid markdown bullet lines and nearly failed a correct round as "walkthrough claims edits not in the diff".
Do not remove: factory-check step 5's instruction to compare the walkthrough with `git diff` itself. Never pipe that diff through a content filter.

## 20261025T2000Z - unibot / ci-env-concurrency

From: `vlaid-unibot`, `factory/improvements.md`

### Held - for CI changes, the proof is two real runs, not a local lint
Evidence: no actionlint and no local Actions. Pushing a second commit and reading both runs' job timelines proved queueing (run 2's TEST deploy started 3 s after run 1's e2e ended).
Do not remove: the "Environment limits -> checker verifies on the real PR" handoff pattern.

Seen again (on "A requested model skipped by the quota cache must be reported as skipped"): ci-env-concurrency r1, claude-sonnet-4-6 exit 3, fell back to flash.
