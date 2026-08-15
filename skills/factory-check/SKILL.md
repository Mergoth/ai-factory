---
name: factory-check
description: Use after the Antigravity CLI has run to verify the work - reads the spec, handoff, agy log and git diff, re-runs the tests, then appends a Success or Needs fix status block to the handoff. Triggers on "/factory-check", "check the antigravity run", "did agy do it right", and is safe to run repeatedly via /loop.
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
   - `specs/<slug>.md`
   - the handoff `handoffs/<timestamp>-<slug>.md`
   - the newest `handoffs/logs-*-<slug>.txt`
   - `git status --short` and `git diff` (add `git diff --staged` if staged)

3. **Check the done criteria one by one.** For each checkbox in the handoff,
   find the evidence in the diff or in the code. Read the actual files - the
   diff alone can hide that a function is never called.

4. **Re-run the tests yourself.** Run `TEST_CMD` from `factory.env` in a Bash
   call. Do not trust `RESULT: PASS` in the log. The log says what agy claims;
   the test run says what is true. If they disagree, the test run wins and that
   disagreement is a red flag worth a bullet.

5. **Look for red flags:**
   - tests deleted, skipped, or weakened instead of fixed
   - files changed that the handoff did not list, with no reason given
   - secrets, keys, tokens, or absolute local paths added
   - `specs/` or `handoffs/` edited by agy (it must not touch those)
   - code that satisfies the letter of a criterion but not the goal

6. **Append a status block to the handoff.** Append, never overwrite - the
   history of attempts is the point. Exact shape:

   ```
   ## Check <timestamp>

   Status: Success
   Tests: <last line of test output>

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

7. **Tell the user the verdict in one line**, then:
   - Success -> say `DONE - <slug> is complete.` and tell them to stop the loop.
   - Needs fix -> print `bash scripts/run_antigravity.sh <slug>` to run again.

## Rules

- Write no implementation code. You verify; agy builds. If the fix is one
  obvious line, still write it as a next-fix bullet and let agy do it - that
  keeps the loop honest.
- Only edit the handoff file. Nothing else.
- Safe to run twice on the same state. If the newest status block already says
  Success and the diff has not changed since, say so and append nothing.
- Under `/loop`, stop condition is `Status: Success`. Say `DONE` clearly so the
  user knows to stop the loop.
