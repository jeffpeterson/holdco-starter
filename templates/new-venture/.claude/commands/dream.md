---
description: Run the dream cycle in-session — consolidate memory, mine WORKLOG for lessons, triage
  recurring tool errors, flag persona bloat, and commit a dated journal to docs/dreams/. Cheap
  maintenance, not product work.
argument-hint: ""
---

## Dream cycle (in-session maintenance)

You're running the dream cycle in your current session — like sleep, consolidating memory and
shedding noise. **Use minimum tokens: this is maintenance, not product work. Don't push.**

Your memory dir is `~/.claude/projects/<slug>/memory/`, where `<slug>` is this repo's absolute path
with every non-alphanumeric char replaced by `-` (e.g. `/path/to/foo` →
`-path-to-foo`). Each memory is a `.md` with YAML frontmatter; `MEMORY.md` indexes them. If
the memory dir doesn't exist yet, skip steps 1–2.

Work through these steps in order, then stop:

1. **Memory consolidation** — read every `<mem>/*.md`; archive stale/one-time entries to
   `<mem>/_archive/`, shorten verbose ones to their essential assertion, merge near-duplicates,
   then rebuild `<mem>/MEMORY.md` to match the live files.
2. **WORKLOG mining** — read the last ~20 `WORKLOG.md` entries; capture any uncaptured durable
   lesson as a new memory file + index line. Skip one-offs.
3. **Tool-error triage** — scan those entries (and prior `docs/dreams/*.md`) for recurring
   tool/command failures. Fix small safe ones directly (e.g. add a missing `--help`, like
   `bin/email` once lacked), document usage errors in the persona/`AGENTS.md`, file anything
   complex as a task (`rake tasks:new[...]`).
4. **Persona hygiene** — read your operator persona; FLAG bloat/contradictions/dead rules in the
   journal (don't edit the persona).
5. **Dream journal** — write `docs/dreams/YYYY-MM-DD.md`: short bullets of what was
   archived/merged/shortened, lessons mined, tool errors found + classification, persona flags.
6. **Commit** — stage the journal + any files you fixed, `git commit -m "dream: YYYY-MM-DD —
   <one-liner>"`. Don't push.

Touch `docs/dreams/.last` when done.
