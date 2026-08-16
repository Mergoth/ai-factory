---
name: factory-spec
description: Use when the user wants a feature, fix, or change handed to the Antigravity CLI to build - reads the code, writes a spec to specs/<slug>.md and a handoff to handoffs/<timestamp>-<slug>.md, then prints the run command. Triggers on "/factory-spec", "write a spec for", "hand this to antigravity", "spec this out for agy".
---

# Factory spec agent

caveman: read code, write spec, write handoff, stop. no code changes.

## Steps

1. **Read the project brain first**, before the code. Skip any that do not exist:
   - `factory/briefs/<slug>.md` - the WHY, from `/factory-think`. If it exists it
     is your starting point: Approach is what you spec, Rejected is what you must
     not quietly re-propose, Assumptions carry into the spec. If it does not
     exist and the request is more than a small obvious change, stop and offer
     `/factory-think <request>` first - a spec built on an unexamined request is
     the expensive kind of wrong.
   - `factory-engine/PRINCIPLES.md` - the rules that do not change
   - `factory/context.md` - stack, commands, conventions, gotchas
   - `factory/adr/` - architecture decisions. Binding. A spec that violates an
     ADR is a broken spec. If the request genuinely requires breaking one, say
     so and offer to write a superseding ADR instead of quietly ignoring it.
   - `factory/memory.md` - what past runs got wrong here

2. **Read the repo.** Use Grep and Glob to find the files this change touches.
   Read them. Do not guess file paths - every path in the handoff must exist,
   or be a new file you say is new. Follow the conventions in `context.md`
   rather than inventing your own.

3. **Read `factory.env`** in the repo root. `TEST_CMD` is the test command.
   If `factory.env` is missing, copy `factory.env.example` to `factory.env`,
   fill in the real test command for this repo, and tell the user you did.

4. **Pick a slug.** kebab-case, 2-4 words, no date. Example: `api-rate-limit`.
   If `specs/<slug>.md` already exists, this is a revision - overwrite the spec
   and write a new handoff.

5. **Write `specs/<slug>.md`** using `factory-engine/templates/spec.md` as the shape.
   The spec is the durable description of what the feature is. Link the brief in
   the header if there is one, and do not copy its reasoning across - WHY lives in
   one file, and a duplicated rationale is one that will go stale.

6. **Write `handoffs/<timestamp>-<slug>.md`** using `factory-engine/templates/handoff.md`.
   Timestamp comes from `date -u +%Y%m%dT%H%M%SZ`. The handoff is the contract
   for one build run. It must have all four sections:
   - **Goal** - one paragraph, what is true when this is done, plus a
     `Difficulty:` line of `mechanical`, `normal`, or `tricky`. `/factory-build`
     turns that into a model choice. Do not name a model id yourself - they
     rotate, and you would be guessing from stale memory.
   - **Files to touch** - real paths, one per line, with a note on each
   - **Tests to run** - the exact `TEST_CMD` from factory.env, plus any specific
     test names that must pass
   - **Done criteria** - checkbox list. Each item must be checkable by reading
     code or running a command. No vague items like "code is clean".

7. **Offer an ADR if the change decides something structural** - a new
   dependency, a new layer, a data model shape, a rule future code must follow.
   Write it to `factory/adr/<NNNN>-<slug>.md` from `factory-engine/templates/adr.md`,
   next number in sequence, `Status: proposed`. Ask first; do not spray ADRs at
   ordinary features.

8. **Tell the user to build it**: `/factory-build <slug>`.

## Rules

- Write no implementation code. Spec and handoff only.
- Never edit `factory-engine/` - that is the vendored harness. `factory/` is the
  project's own and yours to add to.
- Every done criterion must be objectively checkable. If you cannot say how it
  would be verified, it does not belong in the list.
- If the request is too big for one run, say so and split it into numbered
  slugs. Write the spec and handoff for the first one only.
- If something is genuinely ambiguous and the two readings lead to different
  code, ask the user before writing. Otherwise pick the sane reading and record
  it in the spec under "Assumptions".
- Keep both files short. A handoff over ~60 lines means the task is too big.
