# PM board maintenance — a scheduled fleet janitor over the whole task board

**Status:** shipped · **Applies when:** the hosted task board is configured (`TASKS_WORKER_URL`).

## Problem

With the hosted board, the fleet has **one** board and **one** inbox on it: tasks with no venture
(`venture_id` NULL, `status=open`), where the owner files things ad hoc. Making the holdco operator
drain that inbox and do ambient board hygiene **every pass** competes with its higher-leverage work
and doesn't need Opus-grade reasoning on its expensive context.

**Move all of it to a dedicated, cheap, always-on cron — a standing fleet PM / board janitor.** A
single fleet-wide board is holdco-level infra, so the janitor lives in holdco's repo — not the
per-venture toolbelt, and NOT the template. Venture operators still work their OWN boards (claim /
do / close as they finish); the PM is the fleet-wide **safety janitor on top**, not a replacement.

## Remit (the whole board, not just the inbox)

- **Triage** — route inbox tasks to the best-fit **live** venture (route against the CURRENT
  `PORTFOLIO.md` / `bin/holdco fleet` — never hardcode) and fill missing `priority` (P0–P2),
  `kind`, `domain`. Owner-only items (live keys, domain/entity filings, bank/payout, personal asks)
  → flag owner-blocked (`--owner`) AND route to a venture for context. Unclear venture → route to
  `holdco` (catch-all) rather than leave it stuck.
- **Cleanup** — metadata/priority hygiene across open tasks (missing `domain`/`kind`, an obviously
  mis-banded priority). Pure metadata — always safe.
- **Close what's really done — PROOF-GATED.** Only close a task when the reason cites concrete
  evidence the work shipped: a git SHA, a live URL, or a file path that exists. If it can't verify,
  **LEAVE IT**. Never guess; never close someone's in-progress work.
- **Split too-big tasks** — decompose a fat / multi-outcome task into linked child tasks, keep the
  parent as the umbrella, and comment the split rationale. Conservative: one verifiable outcome is
  fine as-is — don't over-split.
- **Dedup** — for near-identical pairs, cancel the duplicate and keep the canonical/older one,
  citing the survivor in the reason. Only near-identical pairs; when unsure, leave both and note it.

Standing constraints: a reason on **every** mutation; **reversible only** (status/field changes —
never delete); **never** dispatch a builder or edit any venture's code (it moves tickets, it
doesn't ship features — and a builder in a live operator's tree collides); **work solo**; when
unsure, **leave it**.

## Two tiers, both bash-gated (the gate is what keeps the model affordable)

The model spins up **only** when the cheap bash pre-check finds work. Every mode does its bash
check FIRST and exits 0 without invoking any model when there's nothing to do.

- **`triage`** — frequent, **every 30 min**. Gate: count open inbox tasks (`bin/holdco api:tasks
  --venture __inbox__ --status open` — `__inbox__` is the sentinel that matches no-venture tasks).
  **Zero → log "inbox empty" and exit 0, no model.** The dominant steady state, so the frequent
  tier is almost always free.
- **`sweep`** — full-board close-scan / dedup / split / cleanup, **every 6h**. Gate: the board must
  have **changed since the last successful sweep**. The runner hashes the open-board list and
  compares to a stored signature; **unchanged → skip, no model.** Once the board is swept clean its
  signature stabilizes and we skip until an operator or the owner touches it. (A coarser
  "board non-empty" gate would never skip — the board always has open tasks.)

**Per-pass action cap on the sweep.** A sweep reads the full title list (cheap — one call, global
view for dedup) but **acts on at most ~15–20 tasks per pass**, stalest-first, so cost per run is
bounded and the board is swept incrementally across runs.

## Structure

One `bin/holdco-pm <triage|sweep>` with a mode flag + two cron lines. It gates on
`TASKS_WORKER_URL` (no board ⇒ no janitor), exports the repo-standard PATH line, runs the mode's
bash gate, and on a pass invokes `claude` headless (`-p`, `--permission-mode bypassPermissions`,
the PM persona via `--append-system-prompt`) with a mode-specific instruction, appending to
`logs/pm.log`. Idempotent — safe every N minutes.

Suggested crontab:

```
*/30 * * * * /path/to/holdco/bin/holdco-pm triage
0 */6 * * *  /path/to/holdco/bin/holdco-pm sweep
```

## PATH / first-run proof

Bare cron gives a minimal PATH (`/usr/bin:/bin`). The runner exports the repo-standard PATH line
(via `$HOME`, no hardcoded user path) so `claude`/`ruby`/`git` resolve. Prove it under
`env -i PATH=/usr/bin:/bin HOME=$HOME bin/holdco-pm triage` — no `command not found`.

## Scope

Holdco-only — the template and venture-operator personas are untouched; venture operators still
work their own boards. When the fleet uses the local git `tasks/` backlog instead of the board,
there is no PM cron and holdco keeps hygiene light itself.
