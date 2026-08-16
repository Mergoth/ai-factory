<!-- factory:template - delete this line once the first run has written here -->
# Factory improvements

caveman: what this project's runs taught about the factory itself. `/factory-reflect`
appends here after every full run. oldest at top, newest at the bottom.

This file is a queue, not a changelog. Nothing here is applied - `factory-engine/`
is vendored and never edited from a project (PRINCIPLES #9). Carrying an entry
upstream is a human action: a PR against the harness repo.

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
