# Token economics — how cost actually works on the fleet

The mental model for managing cost across holdco + every operator. Companion to
`docs/TOKEN-MONITOR.md` (which covers the `bin/holdco tokens` tooling). Verified against the
`claude-api` skill + Anthropic docs (2026-06).

## The one reframe: "running vs stopped" is not the cost axis

An idle Claude Code session costs **nothing** — no tokens burn while it waits. The API is
stateless, so the whole conversation is re-sent every turn. Cost, per turn, is:

> **context size re-sent  ×  (warm cache @ 0.1× or cold @ 1.0×)  ×  model price**

## Cached vs uncached (relative to normal input price)

| token class            | cost   |
|------------------------|--------|
| normal/uncached input  | 1.0×   |
| **cache read (hit)**   | **0.1×** (90% off) |
| cache write, 5-min TTL | 1.25×  |
| cache write, 1-hr TTL  | 2.0×   |
| output                 | separate (Opus 4.8 = 5× input) |

- The cache stores the prompt **prefix** (render order: tools → system → CLAUDE.md → history).
  It's a **prefix match** — any byte change anywhere in the prefix (a timestamp, reordered tool
  list, model switch) invalidates everything after it.
- **TTL in Claude Code defaults to 5 minutes** (sliding — each turn refreshes it). Idle past it
  and the entry expires.
- Min cacheable prefix: 4096 tokens on Opus 4.8 / 2048 on Sonnet 4.6.

## Keep vs clear — the 5-minute hinge

- **Act again within ~5 min** → big stable context is a 0.1× cache *read*; resuming is nearly
  free. **Keep it.**
- **Idle past 5 min** → cache expired; next turn re-reads everything at full price *whether or
  not the session stayed running*. A long-idle session pays the same cold penalty as a fresh one.
- **Clear/compact when context is big AND stale** — finished work re-sent every turn. The win is
  shrinking size, not "stopping."
- **Don't clear a lean, still-relevant context** — you'd pay a cold re-read to rebuild it.

Rule of thumb: **clear when big-and-done, keep when lean-and-soon.**

## Plan vs API billing — what "cost" means for us

The fleet runs on a Claude Code **subscription plan**, not pay-as-you-go.

- The **`$/day` from `ccusage` is an ESTIMATE**, not a bill — it prices our tokens at public API
  rates as a gauge. Nobody charges it.
- On the plan, "cost" = **how fast we burn the rolling 5-hour and 7-day caps** (the `%` in
  `bin/holdco tokens`). The bucket is shared across Claude Code / claude.ai / Cowork.
- Caching and clearing reduce **real cap-burn** (both cut tokens processed), so the dollar
  estimate tracks reality directionally.
- **Known:** cache-read tokens do NOT count against the API's input-per-minute rate limit.
  **Unconfirmed:** the exact plan-cap weighting isn't published — cache reads very likely burn
  far less plan-cap too (consistent, well-supported), but treat the multiplier as unofficial.

## Operating rules for the always-on fleet

- **Lean personas > fat prompts.** Every turn re-sends the whole context, across every operator.
  The single highest-leverage knob. Compact/clear operators whose context ballooned with done work.
- **The idle-loop trap.** An operator that wakes every N min and re-reads a big context: if
  **N > 5 min, every wake is a full-price cold re-read** (zero cache benefit). Either **poll
  sub-5-min** (stay warm — only if work is near-continuous) **or sleep long and batch** (30+ min —
  cold anyway, so don't pay for frequent cold wakes). Worst case is waking *just over* 5 min: all
  cost, no cache.
- **Model is the biggest dial.** Opus ≈ 5× Haiku / ~1.7× Sonnet per token. Default operators to
  **Sonnet**; Haiku for mechanical loops; Opus only for genuinely hard reasoning.
- **Lower reasoning effort** on routine passes — output tokens are the pricey class (5× input).
- **Fan out only when work is truly independent.** N parallel agents = N× concurrent draw on the
  shared caps; same-prefix parallel calls all miss cache (fire one to warm it, then release the rest).
- **Verify caching works.** `usage.cache_read_input_tokens` should be non-zero across turns. Always
  zero ⇒ a silent invalidator (timestamp/UUID/unsorted JSON/shifting tools) is forcing cold reads.

Bottom line: it's never running-vs-stopped — idle is free. Cost is context size × cache warmth ×
model, and on a plan it burns the 5h/7-day caps, not dollars.
