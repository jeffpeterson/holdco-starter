# Sub-agents

Two kinds: **builders** that do the work, and a **review panel** that audits it. The operator
scopes work and **delegates the building** to a builder, then reviews/verifies what comes back —
running the panel on anything substantial.

## The builders (write code — implementation)

| Agent | Lens | Owns | Pairs / audited by |
|-------|------|------|--------------------|
| `coder` | Engineering / implementation | backend, models, services, integrations, tests | `graybeard`, `redteam` |
| `designer` | Design / UX / brand / assets | marketing pages, app UI, emails, copy, visual assets | `hipster`, `bullhorn` |

Builders have **write tools**: they own a **disjoint set of files** for their task, run the
project's full check suite (lint + tests — see `AGENTS.md` for the exact commands), commit, and
**push** themselves. Run a `coder` and a `designer` in parallel when the work splits cleanly
(logic vs. views/styles/assets). Invoke with the Agent tool, `subagent_type: coder` (or
`designer`), handing over the task file + the conventions it needs. The operator persona is the
builders' manager — it stays out of the editor and lets the builders type.

## The review panel (read-only — audit)

Reusable, opinionated expert sub-agents for auditing the business. Each is **picky on purpose**
and represents one concern that productively **conflicts** with the others — the value comes
from the tension, not from any single voice. Run them on a diff, a subsystem, or the whole app
"from time to time" to catch what day-to-day work overlooks.

| Agent | Lens | Pulls toward | Tension with |
|-------|------|--------------|--------------|
| `graybeard` | Engineering / architecture | correctness, simplicity, low debt | speed, growth |
| `hipster` | Design / UX / brand | craft, polish, delight | cost, eng effort, speed |
| `green-eyeshade` | Finance / unit economics | margin, caution | growth spend, free generosity, craft |
| `counsel` | Legal / compliance / privacy | risk coverage | speed, growth claims |
| `bullhorn` | Marketing / GTM / growth | reach, conversion, speed | margin, legal caution |
| `redteam` | Security / abuse / safety | locking it down | ship speed, convenience |

## How to invoke one

Use the Agent tool with the agent's name as `subagent_type` (e.g. `graybeard`), pointing it at
what to review (a diff, files, or "the whole app"). They're **read-only** — they audit and
report; they don't edit. Pass a stronger `model` for deep audits when it's worth it.

## How to run a "board review" (the synergy)

1. Launch several panelists **in parallel** on the same target (e.g. graybeard + redteam +
   green-eyeshade before a launch).
2. Each returns prioritized, severity-tagged findings plus its stated bias.
3. **Synthesize**: collect the findings, surface where the voices *disagree* (e.g. bullhorn
   wants a more generous free tier, green-eyeshade says it only breaks even at 1-in-5, counsel
   wants a consent gate on uploads) and make the call — or escalate the trade-off to the owner.
   The synthesis across tensions is the deliverable, not six separate reports.

Good cadence: a focused panel before any launch or risky change, and a periodic full-board
sweep. (See the backlog for wiring this into a scheduled audit.)
