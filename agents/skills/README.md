# Antigravity skills

caveman: skills for `agy`, not for Claude.

`install.sh` links this directory to `.agents/skills/` in the target repo.

It is empty on purpose. The runner passes the whole contract in the prompt, so
`agy` needs no skill to do a normal build run. Add one here only when you have
a repo-shaped instruction that every run should get - a build convention, a
lint gate, a deploy rule.

One skill per subdirectory, same shape as a Claude skill:

```
agents/skills/<name>/SKILL.md
```

Check `agy agents` to see what the CLI currently picks up.
