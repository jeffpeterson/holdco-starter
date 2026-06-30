# Thinking-effort guide for holdco

Research date: 2026-06-26.
Sources: [code.claude.com/docs/en/model-config#adjust-effort-level](https://code.claude.com/docs/en/model-config#adjust-effort-level),
[code.claude.com/docs/en/sub-agents#supported-frontmatter-fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields),
[code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings).

---

## 1. The effort lever

Effort controls **adaptive reasoning**: the model decides, per step, whether and how much to
think based on task complexity. It is not a fixed overhead per message — "high" on a "check git
status" step adds zero tokens; "high" on "design the auth architecture" adds a lot.

### Levels

| Level | When to use | Notes |
|-------|-------------|-------|
| `low` | Latency-sensitive, non-intelligence-sensitive tasks | Rarely think at all |
| `medium` | Cost-sensitive; can trade some intelligence | Light thinking |
| `high` | **Default on Opus 4.8, Sonnet 4.6, Fable 5** | Balanced; right for most tasks |
| `xhigh` | Deeper reasoning, higher spend | Not available on Sonnet 4.6 (falls back to `high`) |
| `max` | Deepest reasoning, no token constraint | No budget cap; prone to overthinking on simple tasks |
| `ultracode` | `xhigh` + dynamic workflow orchestration per task | Claude Code-only; session-only; not settable in frontmatter |

The effort scale is **calibrated per model** — "high" on Haiku is not the same computation as
"high" on Opus. **Haiku 4.5 does not support effort at all** (not listed in the model×level
matrix).

### Model support matrix

| Model | Supported levels | Default |
|-------|-----------------|---------|
| Fable 5 | low, medium, high, xhigh, max | high |
| Opus 4.8 | low, medium, high, xhigh, max | high |
| Sonnet 4.6 | low, medium, high, **max** (no xhigh) | high |
| Opus 4.6 | low, medium, high, max (no xhigh) | high |
| Haiku 4.5 | **none** | n/a |

Sonnet 4.6's ceiling above `high` is `max` — `xhigh` falls back to `high`.

### How effort interacts with model choice

These are orthogonal levers:
- **Model** = which brain (capability ceiling, cost per token)
- **Effort** = how hard that brain thinks (reasoning depth, token budget for thinking)

Upgrading the model raises the ceiling; raising effort pushes toward that ceiling. A small
brain thinking hard still has a lower ceiling than a large brain. The cheapest path to better
results is usually to raise effort before upgrading the model.

### Special: `ultrathink`

Including the word `ultrathink` anywhere in a prompt requests deeper reasoning on **that turn
only** without changing the session effort level. The only recognized keyword — "think", "think
hard", etc. are passed through as ordinary text.

---

## 2. How to set effort per role

Priority order (highest to lowest):

1. `CLAUDE_CODE_EFFORT_LEVEL` env var — one session, overrides everything
2. `effort:` in **subagent/skill frontmatter** — applies when that agent is active, overrides
   session level but not the env var
3. `--effort <level>` CLI flag — one session
4. `effortLevel` in `settings.json` — persisted default (`low`/`medium`/`high`/`xhigh` only;
   `max` and `ultracode` are not accepted here)
5. Model default (`high` on Opus 4.8/Sonnet 4.6)

**The key mechanism for holdco:** the `effort:` frontmatter field in `.claude/agents/*.md`.
It accepts `low`, `medium`, `high`, `xhigh`, `max` (all five, including `max` — unlike
settings.json which rejects `max`). This is the right place to bake per-persona defaults.

For **venture operators** (launched via `bin/holdco run`), there is no frontmatter path — they
are CLI-launched with `--remote-control`. Set effort via `--effort <level>` in the
`bin/holdco run` command, or via `effortLevel` in the venture's `settings.json`.

---

## 3. Effort × model matrix — recommended per role

The fleet **defaults to Sonnet** (friendly to smaller plans); Opus is opt-in per role via
`HOLDCO_MODEL` / `OP_MODEL`. The rows below name the model worth reaching for when a role's work
justifies the cost — read "Opus" as "upgrade to Opus when the reasoning depth pays for itself."

| Role | Model | Effort | Why |
|------|-------|--------|-----|
| **holdco** | Sonnet 4.6 (Opus opt-in) | `high` (session default) | Mixed tasks: coordination, fleet checks, dispatch don't need deep thinking; adaptive handles the balance. Reach for Opus + the `ultrathink` keyword on big calls (kill/start a venture, capital allocation). |
| **venture operators** | Sonnet 4.6 (Opus opt-in) | `high` | Adaptive reasoning handles the tick/strategy split inside an operator automatically — no need to tune per-tick vs strategic passes separately. Set explicitly via `--effort high` in `bin/holdco run` to avoid inheriting a weird session-level override; upgrade to Opus via `OP_MODEL` for genuinely hard ventures. |
| **coder** | Opus 4.8 | `high` | Architecture decisions, edge cases, failure modes, and root-cause fixes all benefit from thinking. Needs `model: opus` in frontmatter (currently unset). |
| **designer** | Opus 4.8 | `medium` | Taste + pattern-matching against a design system; deep adversarial reasoning doesn't add much. Save ~30–40% thinking-token cost vs `high`. Needs `model: opus` in frontmatter (currently unset). |
| **graybeard** | Sonnet 4.6 | `max` | Adversarial audit: the whole job is surfacing what a quick review misses. Unconstrained thinking is exactly right. `max` is Sonnet's ceiling above `high`. |
| **redteam** | Sonnet 4.6 | `max` | Exploit chains require multi-step adversarial reasoning — the task most sensitive to thinking depth. |
| **counsel** | Sonnet 4.6 | `max` | Legal landmines hide in gaps between policy text and what the code actually does. Careful tracing pays. |
| **green-eyeshade** | Sonnet 4.6 | `max` | Hidden arithmetic — recomputing margins from constants, tracing COGS through code paths — benefits from unconstrained step-by-step reasoning. |
| **hipster** | Sonnet 4.6 | `high` | Taste review: reading templates and matching against design standards. Good judgment call, not adversarial depth. |
| **bullhorn** | Sonnet 4.6 | `high` | Funnel reading + channel analysis. Pattern-matching, not exploit chains. |
| **research/scout subagents** | Haiku 4.5 | n/a (not supported) | Haiku doesn't support effort. Breadth gathering is reading + summarizing, not deep reasoning — the right model, right tool. |
| **mechanical tasks** (fleet checks, indexing, status) | inherit | `low` (if dispatched as subagents) | No reasoning benefit. If holdco ever dispatches these as named subagents, pin `effort: low`. |

### Summary rule

> **`max` for adversarial one-shot audits. `high` for everything that builds. `medium` for
> pure pattern-match work. `low` for mechanics. Haiku gets nothing (it doesn't support effort).**

The binary that moves the needle most: pinning `effort: max` on the four adversarial panel
reviewers (graybeard, redteam, counsel, green-eyeshade). They run infrequently, return
high-leverage findings, and are the roles most sensitive to thinking depth.

---

## 4. Are we under- or over-thinking today?

**Current state:** no effort frontmatter set anywhere; all agents inherit the session default
(`high`). No variation across roles.

### Under-thinking

- **Adversarial panel** (graybeard, redteam, counsel, green-eyeshade): `high` is the default,
  but for a one-shot adversarial audit the ceiling is `max` on Sonnet 4.6. That's the biggest
  opportunity.
- **Holdco strategic calls** (kill/start/double-down): `high` is fine for most passes; for
  high-stakes cross-venture decisions, prompt with `ultrathink` or raise the session to `xhigh`
  before the call.

### Not really over-thinking

- **Builders**: `high` with adaptive reasoning is well-calibrated for implementation work. The
  model won't waste tokens on "add a comma" but will think carefully about "which transaction
  boundary here."
- **Operators**: same. Adaptive handles per-tick vs strategic naturally.
- **Haiku scouts**: no effort support anyway; they're not burning thinking tokens.

The one efficiency gain available: `effort: medium` on designer saves tokens on work that is
taste-matching, not deep reasoning. Worth it across long operator sessions where many design
tasks accumulate.

---

## 5. How to bake this into the fleet

### Immediate: persona frontmatter (`.claude/agents/`)

Add `effort:` to the following files. These apply to all current and future ventures that use
the shared panel:

```yaml
# graybeard.md, redteam.md, counsel.md, green-eyeshade.md
effort: max

# coder.md — also add missing model pin
model: opus
effort: high

# designer.md — also add missing model pin
model: opus
effort: medium

# hipster.md, bullhorn.md — already at the right default; leave as-is
```

### Immediate: bin/holdco run

Add `--effort high` to the `claude --remote-control` invocation for venture operators — makes
the default explicit and prevents it from being overridden by a stale session-level setting:

```bash
claude --remote-control "<Full Title> Operator" \
       --model "${OP_MODEL:-sonnet}" \
       --effort high \
       --dangerously-skip-permissions \
       ...
```

### Template: bake into new-venture scaffold

Edit `templates/new-venture/.claude/agents/coder.md` and `designer.md` to include
`model: opus` + the recommended effort. New ventures inherit it at scaffold time.

The template `operator.md` can stay without an explicit effort (it's set at launch in
`bin/holdco run`); the venture's own `settings.json` can carry `"effortLevel": "high"` as a
belt-and-suspenders default.

### Ongoing: strategic passes

For holdco's own high-stakes calls, include `ultrathink` in the prompt:

```text
ultrathink — should we kill the Trading Desk venture or double down?
```

This raises reasoning depth on that one turn without touching the session setting.

---

## 6. Quick-reference

```
Model tier ──────────────────────────────────────────────────────────▶ more capable, pricier
  Haiku      Sonnet      Opus      Fable
  (scouts)   (panel)   (ops/build)  (reserved)

Effort ──────────────────────────────────────────────────────────────▶ more thinking, pricier
  low    medium    high    xhigh    max    ultracode
         (designer) (default) (Opus only) (panel)  (session-only)

Haiku has no effort support. Sonnet's ceiling above high is max (no xhigh).
```

The two cheapest cost levers in order:
1. **Route by model** (Haiku for scouts, Sonnet for panel, Opus for ops/build) — biggest lever.
2. **Pin effort per role** (max for adversarial audits, high for building, medium for pattern
   work) — second lever; bake into frontmatter so it compounds automatically.
