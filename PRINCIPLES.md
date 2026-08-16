# Factory principles

caveman: rules that do not change. read once, apply always. every skill points here.

## 1. The artifact is the contract

Agents do not share a session. They share files. Brief, spec, handoff, log — if it
is not written down, the next agent does not know it. Say it in the file, not in
the chat.

## 2. Nothing grades its own work

The builder never verifies. The checker never writes code. The thinker never
builds. When one agent does two of these, the loop stops being a check and starts
being a rubber stamp.

## 3. Trust the run, not the report

Re-run the tests yourself. `agy` exits 0 when it failed, and a report is a claim,
not evidence. When the report and the run disagree, the run wins — and the
disagreement is itself a finding.

## 4. WHY, WHAT, and CONTRACT are three different files

- `factory/briefs/<slug>.md` — why this is worth building, what was rejected
- `specs/<slug>.md` — what the thing is
- `handoffs/<ts>-<slug>.md` — the contract for one build run

Collapsing them loses the reasoning first. Six months later the brief is the only
file that answers "why is it like this".

## 5. Ask rarely, assume loudly

Never ask what you can find by reading the code. When a fork is real — two
readings, different code — ask once, batched, capped at three. Everything else
becomes a line under Assumptions, where a human can veto it at a glance.

## 6. Every loop has a cap, and no agent raises its own

Rounds cost real money. Hit the cap, stop, report what is still broken. Asking for
more is allowed; granting it to yourself is not.

## 7. Checkable or it does not count

Every done criterion is verifiable by running a command or reading a named file.
"Code is clean" is not a criterion. If you cannot say how it would be checked, cut
it.

## 8. No model ids anywhere

They rotate. A pinned id rots silently and costs a failed round to discover. Ask
`agy models` at run time and choose from what is actually there.

## 9. `factory-engine/` is machinery, `factory/` is knowledge

Never edit the engine from a project — it is vendored and your change dies at the
next update. Project truth goes in `factory/`: context, ADRs, memory, personas,
briefs.

## 10. Side effects stay in the repo

The only outbound call is `agy`. No commits, no branches, no pushes — the diff
stays in the working tree where a human decides its fate.

## 11. Disagreement is signal, consensus is suspicious

When four personas instantly agree, they read the same file and stopped thinking.
Keep real conflicts in the brief. A design with no rejected alternative was not a
design, it was a reflex.
