# {{TITLE}}

> {{TAGLINE}}

Scaffolded {{DATE}} from the holdco template. This is a self-running **operator repo**: an
autonomous Claude agent owns the business end to end. Overseen by holdco (the portfolio manager).

## Quick start

```
./{{VENTURE}}        # boot Claude as the autonomous operator (full autonomy, remote-steerable)
rake tasks:index     # regenerate TASKS.md from the per-task files in tasks/
rake task            # capture a new task in your $EDITOR (git-commit style)
```

## First steps after scaffolding

1. **Edit `AGENTS.md`** — describe the business, the stack, and the exact lint/test/deploy
   commands (the placeholders in the "Working agreement" section).
2. **Seed `tasks/`** — the first tasks should be the shortest path to a first paying customer.
3. **Set the thesis** in holdco's `ventures/{{VENTURE}}.md`.
4. Build the actual app, then `./{{VENTURE}}` to let the operator take over.

## Layout

| Path | What it is |
|------|------------|
| `{{VENTURE}}` | Launcher — boots the autonomous operator. |
| `.claude/agents/` | Operator persona (`operator`) + builders (`coder`/`designer`) + review panel. |
| `AGENTS.md` | The working agreement (also `CLAUDE.md`). **Fill in the stack bits.** |
| `tasks/` | Backlog, one file per task. Indexed by `TASKS.md` (generated). |
| `docs/LAUNCH.md` | How the system works / current state. |

See `docs/LAUNCH.md` for the runbook and `AGENTS.md` for how the operator works.
