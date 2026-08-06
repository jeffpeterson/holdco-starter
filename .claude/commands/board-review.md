---
description: Convene the review panel on a venture or the whole portfolio. Pass a venture ID
  to target one business; pass "portfolio" or omit to review the whole fleet. Launches
  graybeard, green-eyeshade, counsel, bullhorn, hipster, and redteam in parallel, then
  synthesizes where the voices disagree. Use before a launch, after a major change, or for
  a periodic portfolio sweep.
argument-hint: "[venture-id | portfolio]"
disable-model-invocation: true
---

## Board review: $ARGUMENTS

### Portfolio context

!`bin/holdco fleet`

!`bin/holdco asks`

### Target

$ARGUMENTS — if this is a venture ID, the target is its `repo:` path in `ventures/<id>.md`
(never assume ~/code). If "portfolio" or
blank, the target is the full fleet (read PORTFOLIO.md + recent commit log, `git log
--oneline -30`).

### Instructions

Run all six panel voices in parallel as subagents (graybeard, green-eyeshade, counsel,
bullhorn, hipster, redteam), pointed at the target. Each voice should:
- Read the target repo's AGENTS.md (or PORTFOLIO.md + its recent commit log for a portfolio
  sweep)
- Apply its own lens: correctness/debt, unit economics, legal risk, growth/conversion,
  UX/brand, security/abuse
- Return: top 3 findings, severity tag (critical/high/medium), and one explicit call to
  action

After all voices return:
1. Surface any finding where two or more voices disagree (these are the real trade-offs).
2. Make a recommendation for each disagreement — or flag it as needing owner input.
3. Log the synthesis in your commit message for this pass.

Keep the synthesis under 400 words. Synthesize where they conflict — don't re-summarize
their individual reports.
