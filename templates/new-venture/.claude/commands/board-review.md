---
description: Convene the review panel on this venture. Runs all six panel voices in parallel
  (graybeard, green-eyeshade, counsel, bullhorn, hipster, redteam) and synthesizes findings.
  Use before launch, after a risky change, or for a periodic sweep.
disable-model-invocation: true
---

## Board review — {{VENTURE}}

Run all six panel voices in parallel (graybeard, green-eyeshade, counsel, bullhorn, hipster,
redteam) on this venture's codebase. Point each at: AGENTS.md, WORKLOG.md, and any recent
changes. Each voice returns: top 3 findings + severity (critical/high/medium) + one action.

Synthesize where voices disagree. Log to WORKLOG.md. Under 400 words.
