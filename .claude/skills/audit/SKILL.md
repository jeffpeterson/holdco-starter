---
description: Focused audit of a venture or feature. Pass panel voices and a target, e.g.
  "redteam counsel auth flow". Runs the named voices in parallel and synthesizes findings.
  Faster and cheaper than a full board review; use for pre-commit spot checks or targeted
  concerns. Defaults to graybeard + redteam if no voices named.
argument-hint: "[voice voice ...] [target]"
disable-model-invocation: true
allowed-tools: Bash(bin/holdco *)
---

## Focused audit: $ARGUMENTS

### Context

!`bin/holdco fleet`

### Instructions

Parse $ARGUMENTS as: zero or more panel voice names (graybeard, green-eyeshade, counsel,
bullhorn, hipster, redteam) followed by a target description or file path.

If no voices are named, default to: graybeard + redteam.

Run the named voices in parallel as subagents, pointed at the target. Each voice returns:
- Top findings with severity (critical / high / medium)
- One concrete action

Synthesize in ≤200 words. Surface any disagreement between voices. Done.
