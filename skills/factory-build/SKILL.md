---
name: factory-build
description: Use to run the whole factory loop without babysitting it - launches the Antigravity CLI on a handoff, waits for it to finish, verifies the result, and re-runs it with fix instructions until the tests pass or the round cap is hit. Triggers on "/factory-build", "run the factory", "build the spec", "hand it to agy and loop until it works".
---

# Factory build agent

caveman: launch agy, wait, check, launch again if broken. stop when pass or cap.

## Steps

1. **Find the target.** Slug given -> use it. No slug -> newest handoff in
   `handoffs/`. Print the slug and the handoff path.

2. **Read the handoff out loud first.** Print its Goal and Done criteria to the
   user before launching anything. A wrong handoff wastes a whole agy run, and
   this is the cheapest moment to catch it. Then start round 1.

3. **Launch agy in the background.** Foreground Bash calls are capped at 10
   minutes and an agy run can exceed that, so it MUST be backgrounded:

   Bash tool, `run_in_background: true`:
   ```
   bash scripts/run_antigravity.sh <slug>
   ```

   You are re-invoked when it exits. Do not poll in a tight loop, and do not
   start a second round while one is still running.

4. **Verify.** Read `.claude/skills/factory-check/SKILL.md` and follow its
   steps 2 through 6 exactly. That is the single source of verification truth -
   do not reimplement the checks here. It appends a status block to the handoff.

5. **Decide.**
   - `Status: Success` -> stop. Say `DONE - <slug> is complete.` Print the round
     count and `git diff --stat`.
   - `Status: Needs fix` and rounds used < `MAX_ROUNDS` -> go to step 3 again.
     The next-fix bullets are already in the handoff, so agy picks them up from
     the same contract. No prompt changes needed.
   - Round cap hit -> stop. Say `STOPPED at <n> rounds.` Summarise what is still
     failing and what you would try next. Do not silently keep going.

6. **Report at the end**: rounds used, final status, files changed, last test
   line, and anything you want a human to look at.

## Rules

- `MAX_ROUNDS` comes from `factory.env`, default 3. Each round is a real agy
  run that costs real money and time, so never raise the cap on your own - ask.
- Stop early, before the cap, if two rounds in a row produce the same failure.
  Repeating an identical run is not progress. Report the stuck failure instead.
- Stop immediately and ask the user if agy edits `specs/` or `handoffs/`, deletes
  or skips tests to go green, or touches files far outside the handoff. Those
  are signals the contract is wrong, not that another round will help.
- Write no implementation code yourself, in any round. If the fix is obvious,
  it goes in the handoff as a next-fix bullet and agy does it. The moment you
  patch the code yourself, nobody is grading the builder any more.
- Never commit, branch, or push. The diff stays in the working tree.
