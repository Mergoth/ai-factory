---
name: factory-think
description: Use before writing a spec, when a request needs understanding rather than typing - runs product, architect, skeptic and operator personas in parallel over the codebase, reconciles them, and writes factory/briefs/<slug>.md holding the WHY, the rejected alternatives and the assumptions. Triggers on "/factory-think", "think about", "let's design", "should we build", "figure out what to build", and any feature request vague enough that two people would build different things.
---

# Factory think agent

caveman: four heads read code alone. then one head joins them. write why, not how.

## Steps

1. **Read the rules first.** `factory-engine/PRINCIPLES.md`, then the project
   brain if it exists: `factory/context.md`, `factory/adr/`, `factory/memory.md`.
   Skip what is missing. Do not read the whole codebase yourself — that is what
   the personas are for, and doing their work first biases how you read them.

2. **Pick a slug.** kebab-case, 2-4 words, no date. Example: `api-rate-limit`.
   Print it. If `factory/briefs/<slug>.md` exists, this is a rethink — read the
   old brief, and say what changed.

3. **Collect the personas.** List `factory-engine/personas/*.md` and
   `factory/personas/*.md`. Project files win on name collision; everything else
   joins the set. Ignore `README.md`. Print the names that will run.

   No `factory-engine/` directory? The harness was installed from outside the
   repo, so resolve it with `readlink .claude/skills/factory-think` and take
   `personas/` and `PRINCIPLES.md` from that parent instead.

4. **Run them all in parallel, blind.** One message, one `Agent` call per
   persona, `subagent_type: "Explore"` — read-only, so a persona cannot edit code
   even by accident. Never run them in sequence: the whole point is that they do
   not see each other's answers, and sequential runs converge on the first one.

   Each prompt contains, in this order:
   - the repo root as an absolute path
   - the user's request, verbatim, not your paraphrase of it
   - the full text of that persona's charter file
   - the project brain paths that exist, to read
   - this instruction:
     > You are analysing, not just locating. Read the files that matter in full.
     > Every finding cites something real — a path, a line, a test name, an ADR
     > number. If this change operates on real data that exists on this machine,
     > read a representative sample of it, even when it lives outside the repo.
     > The spec describes what its author believed; the data shows what is true.
     > Cite paths. You cannot talk to the user and must not try; unknowns become
     > findings or your one QUESTION. Return only the block your charter's
     > Return section defines, nothing else.

5. **Reconcile.** Now you read all four. Your job is judgement, not stapling:
   - Where they agree on evidence, take it as settled.
   - Where they conflict, decide, and keep the conflict in the brief under
     Persona notes with how you resolved it. A live disagreement is the most
     valuable thing on the table — do not average it away.
   - Where they all agree instantly and thinly, be suspicious. Four agents that
     read the same README and repeated it have told you nothing.
   - Drop findings with no evidence behind them, however plausible.
   - Collect their `QUESTION` lines. Most are not real forks — kill any you can
     answer from the code, the brief, or an ADR.

6. **Ask, at most once.** Keep only questions where two readings lead to
   genuinely different code. Cap three. Ask them in a single `AskUserQuestion`
   call, with your recommended option first. No real forks -> ask nothing and say
   so. Everything you chose to decide yourself becomes a line under Assumptions,
   which is where a human vetoes it cheaply.

7. **Write `factory/briefs/<slug>.md`** from `factory-engine/templates/brief.md`.
   `Rejected` must have at least one real entry — a design with no discarded
   alternative was a reflex, not a decision. Keep it under ~80 lines; the brief is
   reasoning, not a transcript.

8. **Hand off.** Print the Problem, the Approach and the Assumptions to the user,
   then continue straight into `/factory-spec <slug>` unless they said to stop.
   Thinking is cheap and reversible, so it chains — the money gate is at the
   handoff, not here.

## Rules

- Write no code, and no spec. You produce exactly one file: the brief.
- The brief holds WHY. The spec holds WHAT. Never merge them — see principle 4.
- Personas run blind and in parallel, always. If you catch yourself feeding one
  persona's output to another, stop; that is a different design and not this one.
- Never send a persona a paraphrased request. Paraphrase is where the user's real
  problem quietly becomes your assumption about it.
- A persona that returns nothing usable gets dropped from the brief, not rerun.
  Say which one, so the charter can be fixed.
- Small and obvious requests do not need this. A rename, a typo, a one-line fix —
  say so and send the user straight to `/factory-spec`. Four subagents to decide
  on a rename is theatre.
