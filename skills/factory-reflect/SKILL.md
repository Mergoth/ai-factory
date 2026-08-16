---
name: factory-reflect
description: Use after a full factory run has ended - passed or hit the round cap - to reflect on the run itself and write proposals for improving the factory into factory/improvements.md. Reads every status block, every agy log and the final diff, sorts each lesson to context, memory, an ADR or the engine, and never edits factory-engine/. Triggers on "/factory-reflect", "what did that run teach us", "reflect on the factory run", "post-mortem the build".
---

# Factory reflect agent

caveman: run is over. read what happened. write down how factory itself gets
better. no code changes, no engine edits.

The loop is a product too, and the only evidence about it comes from running it
(principle 16). A defect with no proposal behind it will be met again at full
price.

## When to run

After a run **ends**: `bash scripts/factory_state.sh <slug>` says `next: done` or
`next: cap`. A capped run teaches more than a clean one - do not skip it because
it failed.

Not mid-loop. Reflecting between rounds reflects on noise. If the state says
`build`, `check` or `wait`, say so and stop; the run is not over yet.

## Steps

1. **Find the target.** Slug given -> use it. No slug -> newest handoff in
   `handoffs/`. Print the slug.

2. **Read the whole run, in order.** This is the evidence base and there is no
   substitute for reading it:
   - `factory/briefs/<slug>.md` and `specs/<slug>.md`
   - the handoff with **every** `## Check` block, oldest to newest
   - **every** `handoffs/logs-*-<slug>.txt`, oldest to newest - not just the
     last one. The interesting failures are in the rounds that did not stick.
   - `git diff --stat` and the final diff
   - `factory/context.md`, `factory/adr/`, `factory/memory.md`
   - `factory/improvements.md`, if it exists - what was already proposed

3. **Reconstruct the rounds.** Start from `bash scripts/factory_state.sh <slug>`
   and the log headers - round number, model and snapshot are recorded there, so
   do not reconstruct by hand what the files already say. Then one table, printed
   to the user:

   | Round | Model | agy claimed | check found | cost |
   |---|---|---|---|---|

   `cost` is what the round bought: real progress, a wasted round, or a round
   spent on something the harness should have prevented.

4. **Ask the five questions.** Each answer must point at a round, a log line, a
   diff hunk, or a status block. Anything you cannot pin to this run is a
   hunch, and hunches do not go in the log.

   - **What got through a green suite?** Every defect the checker caught by
     hand, and every defect still sitting in the diff now, is a `factory-check`
     proposal. Name the class, not the instance: "behavioural claim verified by
     reading, not by executing", not "the query argument".
   - **What did Claude do that agy should have done?** Every file Claude typed,
     every scaffolding step, every "it was one line so I fixed it" is a
     principle 12 violation and a proposal to move that work into a handoff.
     Claude tokens are the expensive ones; the fact that it felt faster is the
     symptom, not the defence.
   - **What cost a round?** A contract that was wrong, a criterion that measured
     spelling, an environment the builder could not verify in, a model tier too
     weak, a config default nobody edited. Ask which file could have caught it
     before the money was spent - and if a rule could have caught it, the
     proposal targets `scripts/factory_lint.sh`, not a skill's prose. A check
     that runs every time beats an instruction an agent might skim (principle
     14).
   - **What died mid-run, and what did that cost?** A killed round, an exhausted
     session, a lock left behind. Did the run resume from the files, or did work
     get redone? Anything that had to be reconstructed from memory is a
     `factory_state.sh` proposal.
   - **What held, and would be refactored away by someone who was not here?**
     Name it and say what removing it would cost. This is the half of the log
     that stops the next improvement from being a regression.

5. **Sort every lesson to exactly one destination.** Wrong destination is how a
   lesson dies:
   - always true about this repo -> `factory/context.md`
   - a lesson from runs here, one line -> `factory/memory.md`
   - a rule future code must obey -> offer an ADR, ask before writing it
   - **the harness itself is wrong or missing something** ->
     `factory/improvements.md`, and nowhere else

6. **Append to `factory/improvements.md`.** Create it from
   `factory-engine/templates/improvements.md` if it does not exist. Append a
   block, never overwrite - the history is the point:

   ```
   ## <timestamp> - <slug>

   Run: <n> rounds, <models used>, final status <Success|Stopped at cap>.

   ### <short title of the proposal>
   Target: `factory-engine/skills/factory-check/SKILL.md`, step 7
   Evidence: round 2 log - RESULT: PASS, zero tests added, suite still 70
   Proposal: the exact wording you would put in that file, quoted.

   ### Held - <short title>
   Evidence: <where it did its work this run>
   Do not remove: <what breaks without it>
   ```

   Rules for a proposal:
   - **Target names a real file in the engine** - a skill, a template, a
     persona, `scripts/run_antigravity.sh`, or `PRINCIPLES.md`. "Somewhere in
     the prompt" is not a target.
   - **Evidence comes from this run.** No evidence, no entry.
   - **Proposal is the wording, not the wish.** Write the sentence you would
     paste into the file, so upstreaming it is a copy, not a rewrite.
   - **Cap it at five.** The fifth-best idea from one run is noise.
   - **Merge, do not repeat.** If an earlier block already proposed this, append
     `Seen again: <slug>, <what it cost this time>` to that entry instead of
     writing a new one. A proposal that recurs is stronger evidence, not new
     information.

7. **Report to the user.** Print the round table, the proposals by title, and
   which lessons went to context, memory or an ADR. Then say plainly that
   nothing in the engine has changed: `factory/improvements.md` is a queue, and
   carrying it upstream is a human action - a PR against the harness repo.

## Rules

- Write no code, no spec, no handoff. You touch `factory/improvements.md`, and
  `factory/context.md`, `factory/memory.md` or a new ADR where step 5 sends
  something.
- **Never edit `factory-engine/`.** It is vendored; the change would die at the
  next `git submodule update` and belongs upstream anyway (principle 9). This
  holds even when the fix is one obvious word.
- Every entry cites the run. A reflection that could have been written before
  the run started is a reflection about nothing.
- Nothing worth saying -> write the `Run:` line and stop. An honest empty
  reflection beats an invented proposal, and a run with no findings is itself
  worth recording.
- Do not re-litigate the design. Whether the feature was right belongs in the
  brief; this is about the machine that built it.
- Reflection is cheap, unattended, and touches no code. It runs after every full
  run, not only the interesting ones.
