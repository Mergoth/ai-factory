# Personas

caveman: each file is one lens. `/factory-think` runs them all at once, blind to
each other, then reconciles what comes back.

These four are the default set. They are deliberately narrow — the value is in
the gap between them, so each one has a "Stay in your lane" section keeping it
off the others' ground.

| File | Lens |
|---|---|
| `product.md` | who hurts today, what done looks like from outside |
| `architect.md` | where it lands, what it couples to, which ADR it touches |
| `skeptic.md` | what the request assumes, where it breaks |
| `operator.md` | how it is tested, how it fails loudly, how it is undone |

## The engine set

`engine/` holds three more lenses, and they load **only in self-development
mode** — when the repo being worked on is the harness itself. A product repo
does not want them; they are aimed at prose, prompts and the harness's own
history.

| File | Lens |
|---|---|
| `engine/builder.md` | reads a changed skill as its recipient: what would I actually do? |
| `engine/auditor.md` | which rules a machine could decide instead of a reader |
| `engine/archaeologist.md` | what this cost before, what already covers it, what it displaces |

`builder` is the important one. A `SKILL.md` is an instruction for a model, and
no script can tell you whether the wording lands — but a blind reader given only
that file can tell you what it understood. That is the closest thing to a test
prose ever gets, and it is cheap: a read-only subagent, no `agy` round.

`scripts/factory_env.sh` prints the persona directories that are actually in
play, so `/factory-think` never has to know which mode it is in.

## Adding your own

Drop a markdown file into **`factory/personas/`** in your project. It joins the
round table on the next run — no re-install, nothing to register. A file there
with the same name as one here replaces it, so you can rewrite `skeptic.md` for
your codebase without forking the engine.

Worth adding when a project has a standing concern that the default four keep
missing: `security.md`, `data.md`, `performance.md`, `compliance.md`, `a11y.md`.

Copy the shape of an existing one. The **Return** block must stay identical
across every persona — synthesis merges them mechanically, and a persona that
invents its own output shape breaks that.

Keep the set small. Six lenses that disagree beat twelve that pad. Every persona
is a real subagent reading real code, so each one costs.
