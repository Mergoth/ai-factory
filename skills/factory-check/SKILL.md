---
name: factory-check
description: Use after the Antigravity CLI has run to verify the work - reads the brief, spec, handoff, agy log and git diff, re-runs the tests, checks agy's walkthrough against the real diff, then appends a Success or Needs fix status block to the handoff. Triggers on "/factory-check", "check the antigravity run", "did agy do it right", and is safe to run repeatedly via /loop.
---

# Factory check agent

caveman: read what agy did, run test self, write verdict in handoff. no code changes.

## Steps

1. **Find the target.**
   - Slug given as an argument -> use it.
   - No argument -> newest file in `handoffs/` matching `*-*.md` that is not a
     log. That file's slug is the target.
   - Print which slug you picked before doing anything else.

2. **Read everything.** All of it, in full:
   - `factory/briefs/<slug>.md`, if it exists - the WHY. "What done looks like"
     there is the real target; the handoff criteria are only a proxy for it.
   - `specs/<slug>.md`
   - the handoff `handoffs/<timestamp>-<slug>.md`
   - the newest `handoffs/logs-*-<slug>.txt`, including its `WALKTHROUGH:` block
   - `git status --short` and `git diff` (add `git diff --staged` if staged)
   - the project brain, if present: `factory/context.md`, `factory/adr/`,
     `factory/memory.md`. These are what "right for this project" means here.

3. **Check the done criteria one by one.** For each checkbox in the handoff,
   find the evidence in the diff or in the code. Read the actual files - the
   diff alone can hide that a function is never called.

4. **Re-run the tests yourself.** Run `TEST_CMD` from `factory.env` in a Bash
   call. Do not trust `RESULT: PASS` in the log, and do not trust the `agy exit
   code` line either - agy exits 0 even when it failed or was blocked. The log
   says what agy claims; the test run says what is true. If they disagree, the
   test run wins and that disagreement is a red flag worth a bullet.

5. **Check the walkthrough against the diff.** Read agy's `WALKTHROUGH:` block
   line by line with `git diff` open beside it. This catches a whole class of
   failure the tests cannot:
   - **describes code that is not in the diff** -> the report is fiction. Say so
     plainly, name the claim, `Needs fix`.
   - **its "why" contradicts an ADR or the brief's Approach** -> `Needs fix` even
     when the tests are green.
   - **re-proposes something the brief already listed under Rejected** -> say
     which one, and why the brief rejected it.
   - **"not covered" names a real gap** -> that gap is a next-fix bullet, not a
     shrug. agy admitting it is worth more than agy hiding it.
   - **"verify by hand" commands** -> run one if it is cheap and safe. A
     walkthrough whose own command does not work is not a walkthrough.

   No `WALKTHROUGH:` block in the log at all -> note it, and judge on the diff
   alone. Do not fail the round for it; older logs predate this.

6. **Judge against the brief, not just the checkboxes.** If a brief exists, ask
   whether "What done looks like" is now true. Code that passes every criterion
   while missing the point is the expensive failure, and the checkbox list is the
   one place it hides. Say so as its own bullet.

7. **Look for red flags:**
   - tests deleted, skipped, or weakened instead of fixed
   - files changed that the handoff did not list, with no reason given
   - secrets, keys, tokens, or absolute local paths added
   - `specs/`, `handoffs/`, or `factory-engine/` edited by agy (it must not touch those)
   - code that satisfies the letter of a criterion but not the goal
   - **an ADR broken.** Name the ADR in the bullet. This is `Needs fix` even
     when every test passes - tests do not encode architecture.
   - a convention in `factory/context.md` ignored

8. **Append a status block to the handoff.** Append, never overwrite - the
   history of attempts is the point. Exact shape:

   ```
   ## Check <timestamp>

   Status: Success
   Tests: <last line of test output>
   Walkthrough: matches diff | overstates | absent

   - bullet per done criterion, met or not
   - bullet per red flag, or "no red flags"
   ```

   Use `Status: Needs fix` when any criterion fails, tests fail, or a red flag
   is real. When it is `Needs fix`, add a final section:

   ```
   ### Next fix
   - concrete, specific instruction
   ```

   Each next-fix bullet must be specific enough that `run_antigravity.sh` can be
   re-run against this same handoff and agy will know what to do.

9. **Tell the user the verdict in one line**, then:
   - Success -> say `DONE - <slug> is complete.` and tell them to stop the loop.
     Print agy's "verify by hand" lines so they can see it work themselves.
   - Needs fix -> print `bash scripts/run_antigravity.sh <slug>` to run again.

## Rules

- Write no implementation code. You verify; agy builds. If the fix is one
  obvious line, still write it as a next-fix bullet and let agy do it - that
  keeps the loop honest.
- A confident walkthrough is not evidence. It is the claim you are checking.
  Every finding you report cites the diff, a file you read, or a command you ran.
- Only edit the handoff file. Nothing else.
- Safe to run twice on the same state. If the newest status block already says
  Success and the diff has not changed since, say so and append nothing.
- Under `/loop`, stop condition is `Status: Success`. Say `DONE` clearly so the
  user knows to stop the loop.
