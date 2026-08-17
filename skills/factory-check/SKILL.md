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

1b. **Run the machine checks first.** They are free and they are certain:

   ```
   bash scripts/factory_lint.sh <slug>
   bash scripts/factory_state.sh <slug>
   ```

   The lint decides everything a rule can decide - missing sections, an invalid
   `Difficulty:`, a done list with no checkboxes, a log with no `RESULT:` block,
   a check block that says Needs fix with no Next fix, a listed path that does
   not exist. Every ERROR it prints is a status-block bullet you did not have to
   spend a token finding, and `log_state` from the state script tells you at once
   whether the round you are judging even finished. Read what is left with your
   own eyes; do not re-derive what the script already proved (principle 14).

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

   **3b. Execute the claim, do not read it.** For any criterion phrased as a
   behaviour - "X is rejected", "Y cannot escape", "Z is validated" - construct
   the input that would violate it and run it. A grep proves a string is absent;
   it does not prove a behaviour holds. Where the criterion is a security
   boundary, it is not checked until you have tried to cross it and failed.
   Check side-effect attacks - command execution, a write outside the root - by
   looking for the side effect, not the return value: a successful attack
   usually returns something empty and innocuous.

   **3c. Read the artefact, not only the assertion.** When the change writes a
   file, open the file. Tests assert what their author thought to assert, and
   routinely cover behaviour (appended, did not truncate) while missing shape
   (format, ordering, encoding, trailing newline). If the change produces a
   durable artefact - a log line, a frontmatter block, a filename, a serialized
   record - drive the code to produce one and paste it into the status block
   verbatim, so a human sees the shape.

4. **Re-run the tests yourself.** Run `TEST_CMD` from `factory.env` in a Bash
   call. Do not trust `RESULT: PASS` in the log, and do not trust the `agy exit
   code` line either - agy exits 0 even when it failed or was blocked. The log
   says what agy claims; the test run says what is true. If they disagree, the
   test run wins and that disagreement is a red flag worth a bullet.

   **Compare the test count to the previous `## Check` block** in this handoff.
   A green suite that did not grow, when the handoff asked for new tests, is the
   signature of a truncated or skipped run - not of an easy task. Put the number
   in the status block every time so the next round can make the comparison.

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

   No `WALKTHROUGH:` block **and** no `RESULT:` block -> the run was truncated,
   whatever the exit code says. `Status: Needs fix` regardless of test state, and
   the next-fix bullet names what is missing. A missing walkthrough on an
   otherwise complete log - report present, tests grew - is a note, not a
   failure.

6. **Judge against the brief, not just the checkboxes.** If a brief exists, ask
   whether "What done looks like" is now true. Code that passes every criterion
   while missing the point is the expensive failure, and the checkbox list is the
   one place it hides. Say so as its own bullet.

7. **Look for red flags:**
   - **the test count did not increase** while the handoff asked for new tests
   - a criterion satisfied by editing a comment, a docstring, or a name rather
     than the behaviour it was meant to pin down (principle 13)
   - tests deleted, skipped, or weakened instead of fixed
   - files changed that the handoff did not list, with no reason given
   - secrets, keys, tokens, or absolute local paths added
   - `specs/`, `handoffs/`, or the engine itself edited by agy (it must not touch
     those - in self mode the engine is in scope, but only when the handoff
     says so)
   - code that satisfies the letter of a criterion but not the goal
   - **an ADR broken.** Name the ADR in the bullet. This is `Needs fix` even
     when every test passes - tests do not encode architecture.
   - a convention in `factory/context.md` ignored

8. **Append a status block to the handoff.** Append, never overwrite - the
   history of attempts is the point. Write it as soon as you have the verdict,
   before any long explanation to the user: the status block is what a resumed
   session reads to know this round was judged, and a verdict that exists only in
   your reply dies with the session (principle 15). Exact shape:

   ```
   ## Check <timestamp>

   Status: Success
   Tests: <last line of test output> (<n> tests, was <n> last round)
   Walkthrough: matches diff | overstates | absent | log truncated

   - bullet per done criterion, met or not
   - bullet per red flag, or "no red flags"

   Artefact: <what writes it, and where>
       <one real instance, verbatim, indented four spaces>
   ```

   Drop the `Artefact:` section when the change writes nothing durable. Never
   drop the test count - it is what makes the next round's comparison possible.

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
     Print agy's "verify by hand" lines so they can see it work themselves, then
     point them at `/factory-reflect <slug>` - the run is only finished once it
     has taught the factory something.
   - Needs fix -> print `bash scripts/run_antigravity.sh <slug>` to run again.

## Rules

- Write no implementation code. You verify; agy builds. If the fix is one
  obvious line, still write it as a next-fix bullet and let agy do it - that
  keeps the loop honest (principle 12).
- Throwaway probes are not implementation code. A script that fires the attack
  in step 3b, or drives the tool to emit one artefact for step 3c, is exactly
  the job - write it outside the repo, run it, quote the result, and leave no
  trace in the working tree.
- A confident walkthrough is not evidence. It is the claim you are checking.
  Every finding you report cites the diff, a file you read, or a command you ran.
- Only edit the handoff file. Nothing else.
- Safe to run twice on the same state. If the newest status block already says
  Success and the diff has not changed since, say so and append nothing.
- Under `/loop`, stop condition is `Status: Success`. Say `DONE` clearly so the
  user knows to stop the loop.
