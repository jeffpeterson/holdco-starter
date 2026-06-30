# Skills and Commands — what they are and how holdco should use them

*Research date: 2026-06-26. Docs reviewed:
[code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills),
[code.claude.com/docs/en/slash-commands](https://code.claude.com/docs/en/slash-commands)
(redirected from docs.anthropic.com). CLI verified v2.1.191+.*

---

## 1 — What each thing is

### Custom slash commands (legacy name) → merged into skills

Commands defined as `.claude/commands/<name>.md` still work. As of 2025,
**custom commands have been merged into skills** — they're the same mechanism. Both create
the same `/name` invocation. Skills (`.claude/skills/<name>/SKILL.md`) are the recommended
format because they support a directory of supporting files; commands are still fine for
one-liners. This doc says "skill" for both.

### Skills

A skill is a **Markdown file with optional YAML frontmatter** that gives Claude a named,
invocable procedure or chunk of reference knowledge. Stored at:

| Level | Path | Scope |
|---|---|---|
| User-global | `~/.claude/skills/<name>/SKILL.md` | every project for this user |
| Project | `.claude/skills/<name>/SKILL.md` | this repo only, committed to git |
| Command (legacy) | `.claude/commands/<name>.md` | this repo only, committed to git |

The directory name (or file basename for commands) becomes the `/name` you type to invoke.
A project skill overrides a user-global skill of the same name; an enterprise policy
overrides both.

**How skills work at runtime:**

- Claude Code loads every skill's `description` field into context at session start (so
  Claude knows what's available without loading the body).
- When invoked — by the user typing `/name`, or by Claude recognising relevance — the full
  skill body loads as a message in the conversation and stays for the rest of the session.
- `$ARGUMENTS` substitution: `/board-review acme` makes `$ARGUMENTS` = `"acme"`.
- `!`bash command`` syntax: runs a shell command and inlines its output before Claude sees
  the skill. Use for live context (fleet status, diff, issue list).
- `context: fork` frontmatter: runs the skill in a clean subagent (no conversation history),
  returns a result. Right for self-contained analysis.
- `disable-model-invocation: true`: only the user can invoke, not Claude. Use for anything
  with side effects or timing you want to control.
- `allowed-tools: Bash(git *)`: pre-approves tool calls without a permission prompt.

**Full frontmatter fields** (all optional):

```yaml
---
name: display name in /skills menu
description: what it does, when to use it — Claude reads this to decide when to auto-invoke
when_to_use: additional trigger context, appended to description
argument-hint: "[venture-id]"   # shown during tab-complete
disable-model-invocation: true  # user-only, never auto-triggered by Claude
user-invocable: false           # Claude only, hidden from / menu
context: fork                   # run in a clean subagent
agent: graybeard                # which agent type the subagent uses (with context: fork)
model: sonnet                   # model override for this invocation
effort: high                    # effort level override
allowed-tools: Bash Read        # pre-approve without prompts
disallowed-tools: Edit Write    # block while this skill is active
hooks: ...                      # skill-scoped lifecycle hooks
paths: "ventures/**"            # only auto-trigger for these globs
---
```

### bin/holdco (the Ruby CLI)

Deterministic shell operations: tmux spawning, YAML parsing, file indexing, email dispatch,
Rake invocation. It has no LLM. It cannot reason about context, pick a panel voice, or
synthesize findings. It runs instantly and deterministically every time.

---

## 2 — The boundary: script vs. skill vs. neither

```
                        ┌────────────────────────────────────────┐
                        │                                        │
     deterministic      │  bin/holdco (Ruby/shell)               │
     mechanical ops     │                                        │
                        │  tmux spawn/check, file indexing,      │
                        │  YAML parse, email, rake bridge        │
                        │                                        │
                        └────────────────────────────────────────┘

                        ┌────────────────────────────────────────┐
                        │                                        │
     LLM workflows      │  skills / commands (.claude/)          │
                        │                                        │
     repeatable         │  board review, audit, portfolio pass,  │
     multi-step         │  venture initialization, research      │
     procedures         │                                        │
                        └────────────────────────────────────────┘

                        ┌────────────────────────────────────────┐
                        │                                        │
     knowledge          │  user-invocable: false skills,         │
     reference          │  or CLAUDE.md sections                 │
                        │                                        │
     facts/conventions  │  load only when relevant, cost         │
     Claude applies     │  nothing when unused                   │
                        │                                        │
                        └────────────────────────────────────────┘
```

**The rule:** if it requires judgment, synthesis, or orchestrating subagents — that's a
skill. If it pushes bits predictably (launch tmux, parse YAML, run rake, cat a file) —
that's `bin/holdco` or a direct Bash call.

**Do NOT replace bin/holdco subcommands with skills.** The script does the right thing.
Skills are the *other* layer. A few subcommands (`fleet`, `asks`) make sense as thin skill
wrappers — not to move logic, but for ergonomics: typing `/fleet` in session vs. a terminal
`bin/holdco fleet` is faster when you're already in Claude. The skill would just run
`!`bin/holdco fleet`` and present the output. Logic stays in Ruby.

---

## 3 — Recommended skills for holdco

### Which to build, where, and when

| Skill | Format | Location | Who invokes | What it does |
|---|---|---|---|---|
| `/board-review` | skill | holdco `.claude/` | user | convene panel on a venture or portfolio |
| `/audit` | skill | holdco `.claude/` | user | focused audit: pick 2–3 panel voices for a specific concern |
| `/portfolio-pass` | command | holdco `.claude/` | user | one explicit holdco operating pass (assess → delegate → log) |
| `/fleet` | command | holdco `.claude/` | user | thin wrapper: `!bin/holdco fleet` for in-session convenience |
| `/asks` | command | holdco `.claude/` | user | thin wrapper: `!bin/holdco asks` for in-session convenience |
| `/board-review` | skill | `templates/new-venture/` | operator | venture-level panel: run on the venture's own code |
| `/launch-check` | skill | `templates/new-venture/` | operator | pre-launch checklist: counsel + redteam + graybeard before going live |

**Why `/board-review` in both places:** holdco's version targets cross-venture or the whole
portfolio; the template version targets the venture's own repo and is how each operator's
autonomous loop runs its own reviews. Different targets, same pattern.

**Why `/portfolio-pass` exists:** `bin/holdco operate` boots a full autonomous loop, but
sometimes you want one explicit pass from inside an already-running session — "do a pass now
and tell me what you did" — without launching a new process. A skill gives you that.

**Skip for now:** `/new-venture` is tempting but `bin/holdco new` + manual thesis editing
is already a clean two-step. An LLM wrapper adds friction if it tries to be clever. Revisit
when the scaffold is stable enough to automate the thesis.

---

## 4 — Interplay with subagents, agent teams, and bin/holdco

Skills and agent-team mechanics complement each other cleanly:

- **A `/board-review` skill is the trigger.** It sets up the prompt that launches panel
  voices. The actual voices run as Agent tool calls (today) or as agent teammates (when
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is stable and the pattern is proven — see
  `docs/AGENT-TEAMS-evaluation.md`).
- **`context: fork` inside a skill creates a clean subagent.** Use it for the full-panel
  synthesis path: the skill forks a subagent that launches all panel voices in parallel and
  returns a synthesized report, without cluttering the holdco main context.
- **`bin/holdco` is still the mechanical layer.** A `/fleet` skill that runs
  `!`bin/holdco fleet`` doesn't duplicate logic — it surfaces the output in-session while
  the Ruby code remains the single source of truth.
- **`!`command`` injection is the glue.** Skills can pull live data (fleet status, portfolio
  frontmatter, current diff, Linear issues) directly into the prompt before Claude sees it.
  This is how a `/board-review` skill can load the target venture's frontmatter without Claude
  having to know where to look.

---

## 5 — Starter examples (proposed only — not installed)

### Example A: `.claude/commands/board-review.md`

The simplest format. A command file is a flat Markdown file — no SKILL.md directory needed.
Use a command when there are no supporting files and the body fits in one file.

```markdown
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

$ARGUMENTS — if this is a venture ID, the target is ~/code/$ARGUMENTS. If "portfolio" or
blank, the target is the full fleet.

### Instructions

Run all six panel voices in parallel as subagents (subagent_type: graybeard, green-eyeshade,
counsel, bullhorn, hipster, redteam), pointed at the target. Each voice should:
- Read the target repo's AGENTS.md (or PORTFOLIO.md + WORKLOG.md for a portfolio sweep)
- Apply its own lens: correctness/debt, unit economics, legal risk, growth/conversion,
  UX/brand, security/abuse
- Return: top 3 findings, severity tag (critical/high/medium), and one explicit call to
  action

After all voices return:
1. Surface any finding where two or more voices disagree (these are the real trade-offs).
2. Make a recommendation for each disagreement — or flag it as needing owner input.
3. Log the synthesis to the target venture's WORKLOG.md (or holdco WORKLOG.md for a
   portfolio sweep).

Keep the synthesis under 400 words. The voices are already picky — don't re-summarize their
reports, synthesize where they conflict.
```

**What this does:**
- `disable-model-invocation: true` — you trigger it, never auto-triggered
- `!`bin/holdco fleet`` and `!`bin/holdco asks`` inject live state before Claude sees anything
- `$ARGUMENTS` passes the venture ID or "portfolio"
- Claude orchestrates six parallel Agent calls and returns a synthesized board memo

---

### Example B: `.claude/skills/audit/SKILL.md`

A focused audit: you name 2–3 voices and a specific concern, rather than all six on
everything. Use when you want speed and targeted depth (e.g., "redteam + counsel before
we add social login").

```markdown
---
description: Focused audit of a venture or feature. Pass voices and a target, e.g.
  "redteam counsel auth flow". Runs the named panel voices in parallel on the target and
  synthesizes findings. Faster and cheaper than a full board review; use for pre-commit
  spot checks or targeted concerns.
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
```

---

## 6 — Template recommendation (for every new venture)

Add to `templates/new-venture/.claude/commands/`:

**`board-review.md`** (venture-scoped version):
```markdown
---
description: Convene the review panel on this venture. Runs the full panel in parallel and
  synthesizes findings. Use before launch, after a risky change, or for a periodic sweep.
disable-model-invocation: true
---

## Board review

Run all six panel voices in parallel (graybeard, green-eyeshade, counsel, bullhorn, hipster,
redteam) on this venture's codebase. Point each at: AGENTS.md, WORKLOG.md, and any recent
changes. Each voice: top 3 findings + severity + one action. Synthesize where voices
disagree. Log to WORKLOG.md. Under 400 words.
```

**`launch-check.md`** (venture-scoped — pre-launch gate):
```markdown
---
description: Pre-launch checklist. Runs counsel, redteam, and graybeard on the codebase
  before going live. Use when "launching" or "shipping" is imminent.
disable-model-invocation: true
---

## Pre-launch check

Run three voices in parallel before shipping:
- counsel: ToS, privacy policy, consumer-protection exposure, GDPR basics
- redteam: auth, payment integrity, secrets, injection, abuse vectors
- graybeard: deployment config, error handling, data integrity, migration safety

Each returns: blockers (must fix before launch), warnings (fix soon), and one green light
confirmation. If any blocker exists, stop and surface it. Synthesize in ≤200 words.
```

These two commands give every venture operator a `/board-review` and `/launch-check`
it can invoke in its own autonomous loop without any extra setup.

---

## 7 — Installation notes (when you're ready to wire these in)

1. Create `.claude/commands/board-review.md` and `.claude/skills/audit/SKILL.md` in this
   repo (committed to git — project scope, available in every holdco session).
2. Add `board-review.md` and `launch-check.md` to `templates/new-venture/.claude/commands/`
   (so every new venture inherits them at scaffold time).
3. Verify with `/board-review portfolio` in a holdco session — check that `!`bin/holdco
   fleet`` injects correctly and six panel agents fire in parallel.
4. When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` stabilizes, update `/board-review` to
   use agent teammates instead of independent Agent calls — the voices will then see each
   other's findings and can debate. See `docs/AGENT-TEAMS-evaluation.md` §1 for the exact
   upgrade path.

---

## Sources

- [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills) — skills format,
  frontmatter reference, `context: fork`, `!` injection, `$ARGUMENTS`, project vs user scope
- [agentskills.io](https://agentskills.io) — the open standard Claude Code's skills implement
- `docs/AGENT-TEAMS-evaluation.md` in this repo — the board-review pattern via agent teams
- `docs/ORCHESTRATION.md` in this repo — the fleet model and subagent delegation mechanics
- `.claude/agents/README.md` in this repo — the review panel and how to invoke them
