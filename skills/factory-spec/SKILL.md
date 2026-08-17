---
name: factory-spec
description: Use when the user wants a feature, fix, or change handed to the Antigravity CLI to build - reads the code, writes a spec to specs/<slug>.md and a handoff to handoffs/<timestamp>-<slug>.md, then prints the run command. Triggers on "/factory-spec", "write a spec for", "hand this to antigravity", "spec this out for agy".
---

# Factory spec agent

caveman: read code, write spec, write handoff, stop. no code changes.

## Steps

1. **Orient, then read the project brain**, before the code. Run
   `bash scripts/factory_env.sh` first: it prints the mode, the absolute paths
   to `PRINCIPLES.md` and `templates/`, and which brain files are filled in.
   Never guess at `factory-engine/` - in self-development mode there is no such
   directory. Then read, skipping any that do not exist:
   - `factory/briefs/<slug>.md` - the WHY, from `/factory-think`. If it exists it
     is your starting point: Approach is what you spec, Rejected is what you must
     not quietly re-propose, Assumptions carry into the spec. If it does not
     exist and the request is more than a small obvious change, stop and offer
     `/factory-think <request>` first - a spec built on an unexamined request is
     the expensive kind of wrong.
   - the principles file that `factory_env.sh` named - the rules that do not change
   - `factory/context.md` - stack, commands, conventions, gotchas
   - `factory/adr/` - architecture decisions. Binding. A spec that violates an
     ADR is a broken spec. If the request genuinely requires breaking one, say
     so and offer to write a superseding ADR instead of quietly ignoring it.
   - `factory/memory.md` - what past runs got wrong here

2. **Read the repo.** Use Grep and Glob to find the files this change touches.
   Read them. Do not guess file paths - every path in the handoff must exist,
   or be a new file you say is new. Follow the conventions in `context.md`
   rather than inventing your own.

3. **Preflight the harness, before writing anything.** Each of these costs
   seconds here and a whole paid round if it is discovered by `agy`:

   - **`factory.env` and `TEST_CMD`.** If `factory.env` is missing, copy
     `factory.env.example` to `factory.env`, fill in the real test command for
     this repo, and tell the user you did. A `TEST_CMD` still holding the
     template default is the single most expensive thing on this list.
   - **Run `TEST_CMD` once, now.** Not to see tests pass - to see that the
     command exists and the runner starts. If it dies on `command not found`, a
     missing interpreter, an unsupported runtime version, or an unresolvable
     import, **do not write a handoff**. Say what broke and what would fix it.
     Python gotcha: `pytest` exits 5 on an empty collection, which is the normal
     state of a greenfield round 1 - that is a pass for this preflight, and it
     belongs in the spec's Notes so the builder is not confused by it.
   - **A repo with no commits.** With zero commits `/factory-check` cannot
     compare the walkthrough against `git diff`, and the only rollback verb is
     `git clean -fd`, which deletes the untracked spec being built from. Stop
     and ask the user for a baseline commit. Do not make it yourself -
     principle 10 says commits are the human's.
   - **Greenfield scaffolding.** If there is no package manifest, no test
     directory, no importable package, round 1 will spend itself inventing all
     of that instead of solving the problem. Do not type it yourself either
     (principle 12) - write a separate `bootstrap-<slug>` spec and handoff at
     `Difficulty: mechanical`, whose only done criterion is that `TEST_CMD` runs
     green on one trivial test. Cheap model, one round, and the real handoff
     starts from a working repo.

4. **Pick a slug.** kebab-case, 2-4 words, no date. Example: `api-rate-limit`.
   If `specs/<slug>.md` already exists, this is a revision - overwrite the spec
   and write a new handoff.

5. **Write `specs/<slug>.md`** using the `templates/spec.md` under the engine path from step 1.
   The spec is the durable description of what the feature is. Link the brief in
   the header if there is one, and do not copy its reasoning across - WHY lives in
   one file, and a duplicated rationale is one that will go stale.

6. **Write `handoffs/<timestamp>-<slug>.md`** using `templates/handoff.md` under that same engine path.
   Timestamp comes from `date -u +%Y%m%dT%H%M%SZ`. The handoff is the contract
   for one build run. It must have all of these sections:
   - **Goal** - one paragraph, what is true when this is done, plus a
     `Difficulty:` line of `mechanical`, `normal`, or `tricky`. `/factory-build`
     turns that into a model choice. Do not name a model id yourself - they
     rotate, and you would be guessing from stale memory.
   - **Files to touch** - real paths, one per line, with a note on each
   - **Tests to run** - the exact `TEST_CMD` from factory.env, plus any specific
     test names that must pass
   - **Done criteria** - checkbox list. Each item must be checkable by reading
     code or running a command. No vague items like "code is clean".
   - **Environment limits** - anything in scope that cannot be verified on this
     machine: no docker daemon, no network, no credentials, no device. Say so,
     and instruct the builder to write the artefact and declare it uncovered.
     A builder that cannot verify and is not told so will claim success.

   Ask for the whole slice, not the interesting half: implementation, tests,
   fixtures, migrations, docs. The ~60-line limit is on the contract, not on the
   amount of work it asks for (principle 12).

   **Write criteria that measure the thing, not its spelling.** Two rules, both
   bought with a failed round:

   - **Prefer a criterion that runs the code over one that greps it.** A grep is
     right only where the string genuinely is the rule ("no `startswith` in
     `paths.py`"). Behavioural rules become named tests instead. Before writing
     a grep, ask what a comment, a docstring, or a stale `.pyc` does to it - all
     three have produced false results here. `grep -rE "unlink|os\.remove" src/`
     was satisfied by rewording a comment.
   - **When you specify a chokepoint, enumerate the inputs it covers, not the
     argument names it expects.** "Every caller-supplied *path* goes through
     `resolve()`" left a `query` string reaching a subprocess and shipped an
     RCE. "Every caller-controlled string that reaches the filesystem or a
     subprocess" would have caught it. Name the class of input, then name the
     ones you know about as examples.

7. **Offer an ADR if the change decides something structural** - a new
   dependency, a new layer, a data model shape, a rule future code must follow.
   Write it to `factory/adr/<NNNN>-<slug>.md` from the engine's `templates/adr.md`,
   next number in sequence, `Status: proposed`. Ask first; do not spray ADRs at
   ordinary features.

8. **Lint what you wrote, before handing it over.**

   ```
   bash scripts/factory_lint.sh <slug>
   ```

   It checks the shape of the brief, spec and handoff: required sections, a valid
   `Difficulty:` line, at least one done criterion, a `Rejected` list with real
   entries, paths that do not exist and are not marked NEW. Fix everything it
   flags now - the runner gates on this same check and will refuse the round
   otherwise, and a shape error found here costs nothing (principle 14).

9. **Tell the user to build it**: `/factory-build <slug>`.

## Rules

- Write no implementation code. Spec and handoff only.
- Never edit the engine in `project` mode - it is vendored, and the change dies
  at the next update. `factory/` is the project's own and yours to add to. In
  `self` mode the engine IS the project and editing it is the work; the
  `engine_edit:` line from `factory_env.sh` says which you are in.
- Every done criterion must be objectively checkable. If you cannot say how it
  would be verified, it does not belong in the list. Then ask the second
  question (principle 13): what could a lazy or truncated run do to satisfy this
  without doing the work? If the answer is "quite a lot", rewrite it.
- You write files under `specs/`, `handoffs/` and `factory/`. Nothing else -
  not the scaffolding, not the "obvious" one-liner, not the fixture. Those are
  handoff lines, and agy is cheaper at them than you are (principle 12).
- If the request is too big for one run, say so and split it into numbered
  slugs. Write the spec and handoff for the first one only.
- If something is genuinely ambiguous and the two readings lead to different
  code, ask the user before writing. Otherwise pick the sane reading and record
  it in the spec under "Assumptions".
- Keep both files short. A handoff over ~60 lines means the *contract* is
  sprawling, not that the job is - a tight contract can still ask for a whole
  vertical slice, tests and fixtures included.
