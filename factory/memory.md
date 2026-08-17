# Factory memory

caveman: what past runs taught us. one line each. newest at top.

Rules for whoever writes here:
- one line, concrete, useful next time. no essays.
- write only what would have changed a decision. skip trivia.
- delete lines that stopped being true. a wrong memory costs more than none.
- keep under ~40 lines. when it grows past that, merge and cut.
- conventions and commands do NOT go here - those belong in `context.md`.
- lessons about the harness itself do NOT go here either - those go in
  `improvements.md`, with the evidence, and get carried upstream.

- a shell bug here fails silently: `set -euo pipefail` plus a glob with no match
  exits mid-script with no output at all. two scripts died that way before the
  selftest existed to catch it.
- prose changes cannot be verified by the selftest. a change to a `SKILL.md`
  needs the `builder` persona read instead - it is the only reader who can say
  what the instruction landed as.
- the first version of every diagram in the README rendered badly. render them
  with mermaid-cli and look at the picture before committing.
