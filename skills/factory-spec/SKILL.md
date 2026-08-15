---
name: factory-spec
description: Use when the user wants a feature, fix, or change handed to the Antigravity CLI to build - reads the code, writes a spec to specs/<slug>.md and a handoff to handoffs/<timestamp>-<slug>.md, then prints the run command. Triggers on "/factory-spec", "write a spec for", "hand this to antigravity", "spec this out for agy".
---

# Factory spec agent

caveman: read code, write spec, write handoff, stop. no code changes.

## Steps

1. **Read the repo.** Use Grep and Glob to find the files this change touches.
   Read them. Do not guess file paths - every path in the handoff must exist,
   or be a new file you say is new.

2. **Read `factory.env`** in the repo root. `TEST_CMD` is the test command.
   If `factory.env` is missing, copy `factory.env.example` to `factory.env`,
   fill in the real test command for this repo, and tell the user you did.

3. **Pick a slug.** kebab-case, 2-4 words, no date. Example: `api-rate-limit`.
   If `specs/<slug>.md` already exists, this is a revision - overwrite the spec
   and write a new handoff.

4. **Write `specs/<slug>.md`** using `.factory/templates/spec.md` as the shape.
   The spec is the durable description of what the feature is.

5. **Write `handoffs/<timestamp>-<slug>.md`** using `.factory/templates/handoff.md`.
   Timestamp comes from `date -u +%Y%m%dT%H%M%SZ`. The handoff is the contract
   for one build run. It must have all four sections:
   - **Goal** - one paragraph, what is true when this is done
   - **Files to touch** - real paths, one per line, with a note on each
   - **Tests to run** - the exact `TEST_CMD` from factory.env, plus any specific
     test names that must pass
   - **Done criteria** - checkbox list. Each item must be checkable by reading
     code or running a command. No vague items like "code is clean".

6. **Print the run command** for the user:
   `bash scripts/run_antigravity.sh <slug>`

## Rules

- Write no implementation code. Spec and handoff only.
- Every done criterion must be objectively checkable. If you cannot say how it
  would be verified, it does not belong in the list.
- If the request is too big for one run, say so and split it into numbered
  slugs. Write the spec and handoff for the first one only.
- If something is genuinely ambiguous and the two readings lead to different
  code, ask the user before writing. Otherwise pick the sane reading and record
  it in the spec under "Assumptions".
- Keep both files short. A handoff over ~60 lines means the task is too big.
