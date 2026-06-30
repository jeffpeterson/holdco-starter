# The Dream Cycle — sleep-time memory consolidation & context hygiene

## What it is, and why

Every animal sleeps to consolidate memory and shed the day's noise. An autonomous agent that
accumulates memories, WORKLOG entries, and persona rules forever — without ever pruning — drifts
toward higher entropy: stale facts crowd out live ones, near-duplicate memories pile up, verbose
notes burn context on every turn, and the same tool mistakes recur because nobody wrote down the
right invocation. The **dream cycle** is the maintenance routine that fights that entropy.

It runs on a **cheap model** (Sonnet or Haiku — never Opus), on idle, so it costs little. It is
explicitly **not product work**: it consolidates and prunes, then commits a journal and stops.

## The steps

A dream works through six steps in order:

1. **Memory consolidation** — read every memory file (`~/.claude/projects/<slug>/memory/*.md`);
   archive stale/one-time-event entries to `_archive/`, shorten verbose ones to their essential
   assertion, merge near-duplicates, then rebuild the `MEMORY.md` index to match the live files.
2. **WORKLOG mining** — read the last ~20 `WORKLOG.md` entries and capture any uncaptured durable
   lesson as a new memory file (Reflexion-style self-reflection), adding it to the index.
3. **Tool-error triage** — scan recent WORKLOG entries and prior dream journals for recurring
   tool/command failures, and classify each:
   - **Fixable now** — small, clearly-safe patches (add a `--help`, fix a wrong default or a stale
     usage example). Applied directly. *Canonical example: `bin/email` had no `--help` flag, so
     agents kept guessing its args — a dream should add the flag or file a task.*
   - **Usage error** — the tool is correct but keeps getting called wrong → document the right
     invocation in the persona / `AGENTS.md`.
   - **Too complex for a dream** — file a task (`bin/holdco task` here, `rake tasks:new[...]` in a
     venture).
4. **Persona hygiene review** — read the operator/holdco persona and **flag** bloat,
   contradictions, and dead rules in the journal. The dream **never edits the persona
   unilaterally** — flagged items become filed "consider" tasks (for ventures:
   `rake tasks:new["Consider: ...",P3,Ops]`; for holdco: `bin/holdco task "Consider: ..."`)
   for deliberate review; a persona is durable behavior, not a target for same-pass reactive
   trims. Note: overlap with global `~/.claude/CLAUDE.md` guidance is not automatically bloat
   — local restatement can be intentional emphasis; flag only pure duplication.
5. **Dream journal** — write `docs/dreams/YYYY-MM-DD.md`: short bullets covering what was
   archived/merged/shortened, lessons mined, tool errors found + classification, and persona flags.
6. **Commit** — stage the journal plus any fixes applied in steps 3–4 and commit (`dream:
   YYYY-MM-DD — <one-liner>`). **It never pushes.**

## Prior art adopted

- **Reflexion** — the agent writes a self-reflective summary after experience accumulates →
  the dream journal + WORKLOG-mined lessons (step 2, step 5).
- **Hierarchical / tiered memory (MemGPT)** — hot (in-context) → warm (memory files) → cold
  (`_archive/`); the dream promotes/demotes between tiers (step 1).
- **Sleep-time compute** — idle inference spent on consolidation/indexing, not task execution;
  hence the cheap model and "maintenance, not product work" framing.
- **Entropy-minimizing pruning** — merge near-duplicates, shorten verbose facts to the essential
  assertion, archive one-time events that are now purely historical (step 1).

## Cadence & model

- **When:** when your context is large AND stale (a good move right before `bin/self-clear`), or
  roughly every 24h. `bin/dream` self-throttles — it skips if the last dream was <12h ago (the
  `docs/dreams/.last` marker); pass `--force` to override.
- **Model:** Sonnet by default; Haiku for the cheapest pass (`DREAM_MODEL=haiku bin/dream`).
  **Never Opus** — this is mechanical maintenance.

## How to run

- **`bin/dream`** — dream for the current repo (holdco, or run inside a venture repo).
  - `bin/dream --dry-run` — print what it would do (memory dir, model, journal path, last run).
  - `bin/dream --force` — run even if a dream ran in the last 12h.
  - `DREAM_MODEL=haiku bin/dream` — cheaper model.
- **`/dream`** — invoke the same cycle in your own live session (no separate process).
- **`bin/holdco dream`** — dream for holdco itself.
- **`bin/holdco dream <id>`** — dream for a registered venture from holdco's perspective: it
  resolves the venture's repo from `ventures/<id>.md` and runs that repo's `bin/dream`. (Don't run
  this against a venture whose operator is **live** — they'd share the working tree; pause it or
  let the operator run its own `/dream` instead.)

## What gets committed vs. stays local

- **Committed** (to the repo): the dream **journal** (`docs/dreams/YYYY-MM-DD.md`), any
  promoted/mined lessons that live in the repo, and any tool-error fixes applied in step 3.
- **Local-only** (never committed): the **memory files** themselves live under `~/.claude/` (not
  in git, not backed up) — the dream edits them in place. The `docs/dreams/.last` cadence marker
  is git-ignored. *Durable lessons worth surviving a memory wipe must be baked into a persona /
  `AGENTS.md` / `docs/` — that's exactly what steps 2–4 push toward.*

## Adding `bin/holdco dream` to a pass

The dream cycle is a periodic, not every-pass, operation. Fold it into holdco's loop like this:
when an operator's (or holdco's own) context is large and stale, or it's been ~24h, run a dream on
a cheap model before clearing — `bin/dream` for holdco, `bin/holdco dream <id>` for a paused/idle
venture. It's cheap, it's idempotent (the 12h skip guard), and it keeps the whole fleet's memory
and tooling from rotting. The template ships `bin/dream` + `/dream` + the dream persona in every
new venture, so every operator can self-dream from day one.
