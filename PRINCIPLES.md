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

A truncated run looks identical to a successful one from the outside: exit 0,
green suite, plausible files. The only reliable tells are structural — did the log
end with a `RESULT:` block, and did the thing the handoff asked for actually
appear. Check both, every round.

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

## 12. Cheap hands, expensive judgement

`agy` tokens are cheap. Claude tokens are expensive. The whole factory is built on
that price difference, and every skill spends against it.

Claude Code is a team of **senior colleagues**: they decide what is worth
building, write the guidelines the work must follow, and grade what comes back.
`agy` is a team of **mid-to-senior developers**: fast, competent, and good at
following a contract they were given. So `agy` writes the code — all of it.
Implementation, tests, fixtures, scaffolding, migrations, docs, the boring parts.
Claude defines, checks, and improves.

Hand over the whole slice, not the interesting half. A short handoff can ask for a
large amount of work; the ~60-line limit is on the contract, not on the job.

A senior who takes the keyboard because it would be faster has stopped grading the
work and started doing it — and there is now nobody left to grade it (principle
2). If you catch yourself typing the fix, that is a next-fix bullet you have not
written yet.

## 13. A criterion measures what it measures

"Checkable" is necessary, not sufficient. A grep checks spelling. A passing test
checks the assertion its author wrote. Neither checks the behaviour you meant.
Before accepting a criterion, ask what a lazy, literal-minded, or truncated run
could do to satisfy it without doing the work. When the answer is "quite a lot",
rewrite it as something that runs the code.

## 14. If a script can decide it, a script decides it

A shape check is free, identical every time, and never gets bored on the third
round. Judgement is the expensive, scarce thing. So anything decidable by a rule
— a missing section, a `Difficulty:` line that is not one of three words, a done
list with no checkboxes, a log with no `RESULT:` block, a path that does not
exist — belongs in `scripts/factory_lint.sh`, and runs before any agent spends a
token or a round on the same question.

The order is always: machine checks first, then read what is left. A skill that
re-reads what a script already proved is paying for certainty it had for free.

## 15. Any step can die, and the run resumes from the files

Claude runs out of context. `agy` times out. The network drops, the laptop
sleeps, a human hits ctrl-c. Assume every step dies at its worst moment.

So no agent keeps run state in its head. The round counter is the number of logs
on disk. The verdict is the last status block in the handoff. "A round is in
flight" is a lock file with a pid in it. Every one of those survives the agent
that wrote it, which is what lets a fresh session pick the run up mid-flight
instead of starting over or double-spending.

Two things follow. Before spending money, ask `scripts/factory_state.sh` where
the run stopped and do what it says. And before letting a round loose, snapshot
the uncommitted work — it is the only copy there is, and a bad round eating a
good one is the one loss the factory cannot undo.

## 16. Every full run improves the factory

The loop is a product too, and the only evidence about it comes from running it.
After every run that ends — passed or capped — spend one cheap round on the
harness itself: what got past a green suite, what cost a round, what Claude typed
that `agy` should have. Proposals go in `factory/improvements.md` with the
evidence from the run sitting next to them. A defect with no proposal behind it
will be met again, at full price.
