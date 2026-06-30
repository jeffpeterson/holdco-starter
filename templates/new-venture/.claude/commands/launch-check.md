---
description: Pre-launch checklist. Runs counsel, redteam, and graybeard on the codebase
  before going live. Use when launch or shipping is imminent.
disable-model-invocation: true
---

## Pre-launch check — {{VENTURE}}

Run three voices in parallel before shipping:
- **counsel**: ToS, privacy policy, consumer-protection exposure, GDPR basics
- **redteam**: auth, payment integrity, secrets, injection, abuse vectors
- **graybeard**: deployment config, error handling, data integrity, migration safety

Each returns: blockers (must fix before launch), warnings (fix soon), and one green light
confirmation. If any blocker exists, stop and surface it. Synthesize in ≤200 words.

**Voice gate (copy):** confirm every customer-visible string — landing copy, product UI,
buttons, empty states, error messages, transactional/marketing email — has passed the voice gate
(`/copy`) against `BRAND.md`. Any string a customer reads ships only after that pass. Treat
unswept customer-facing copy as a launch blocker.
