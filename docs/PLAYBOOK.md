# The Playbook — starting & running a business

This is the repeatable flow holdco exists to run: one autonomous operator per business, a
one-file-per-task backlog, a panel of opinionated reviewer sub-agents, and a `./<name>` launcher
that boots the operator with full autonomy. holdco sits above all of them.

## Venture lifecycle

```
incubating → building → launching → live
                ↘         ↘
              shuttered  (pause/kill)
```

Every new venture starts as **incubating**. The operator writes `BUSINESS-PLAN.md` before
touching any code. holdco reviews the plan — using the panel if useful — and either:

- **Greenlights:** edit `ventures/<id>.md`, set `status: building`, run `bin/holdco index`.
  The operator resumes normal operation.
- **Shutters:** `bin/holdco shutter <id>` — stops the operator, marks the venture shuttered,
  appends a postmortem stub. The repo is preserved (archived in place).

**holdco does NOT write the business plan.** That is the operator's job — the self-validation
step. holdco scaffolds, reviews, and decides; the operator researches and writes.

## 1. Start a new business (one command)

```
bin/holdco new <name> "Display Title" "one-line tagline"
```

This stamps `templates/new-venture/` into `~/code/<name>` (override the location with
`VENTURES_ROOT`), fills in the placeholders, `git init`s it, seeds its `TASKS.md`, makes the
first commit, and registers it in `ventures/<name>.md` + `PORTFOLIO.md` with status
**`incubating`**.

What you get in the new repo:
- **`AGENTS.md`** (+ `CLAUDE.md` symlink) — the business's working agreement. **Edit this first**
  to describe what the business is, its stack, and the exact lint/test/deploy commands.
- **`.claude/agents/`** — the operator persona (`operator.md`) + builders (`coder`, `designer`)
  + the review panel (`graybeard`, `hipster`, `green-eyeshade`, `counsel`, `bullhorn`, `redteam`).
- **`BUSINESS-PLAN.md`** — the incubation stub the operator fills before any building begins
  (Thesis / Market & Competition / Model & Unit Economics / MVP / Risks / Go/No-Go).
- **`tasks/`** + generated **`TASKS.md`** — the one-file-per-task backlog machinery.
- **`./<name>`** — the launcher that boots the autonomous operator.
- **`docs/LAUNCH.md`**, **`WORKLOG.md`**, **`README.md`** — the durable state docs.

### Pushing to GitHub (use the safe helper)

If the venture needs a GitHub remote, use:

```
bin/holdco push-remote <name> <owner/repo>
```

This checks that the target GitHub repo either does not exist or has no commits before pushing.
It refuses and aborts if the repo already has content — so you can never accidentally overwrite
an existing project. **Never run `git push --force` / `-f` to a venture's origin during
scaffolding**, and never run `gh repo create` bare and then push manually without this check.
If `gh repo create` fails because the name is taken, stop and choose a different name or ask
the owner.

## 2. Shape the thesis

Edit the venture's `AGENTS.md` (what/who/why, stack, check commands) and seed its backlog:
the first `tasks/` files should be the path to a first dollar — the smallest thing a customer
would pay for, plus the funnel to reach them. Capture the thesis in `ventures/<name>.md`.

## 3. Incubation: operator writes the business plan

```
cd ~/code/<name>
./<name>            # operator's first job: fill BUSINESS-PLAN.md
```

The operator persona checks for `BUSINESS-PLAN.md` first. If it's unfilled, the operator
researches and writes the plan — thesis, branding/domain, market, competition, model, unit
economics, MVP scope, risks, honest go/no-go.

**Naming includes a domain check.** For every name candidate the operator proposes it runs
`whois <domain>` across `.com`, `.ai`, and `.co` (available ≈ "No match" / "NOT FOUND").
The quick tool is `bin/holdco domain <name>` — it prints AVAILABLE/taken for all three TLDs
at once. The plan records results in a table and recommends the domain to register. When done,
it logs the result and pauses.

**holdco then reviews** — run the panel (`green-eyeshade` for economics, `graybeard` for tech
risk, `redteam` to poke holes) or read the plan directly. Then:

- **Greenlight:** update `ventures/<name>.md` status to `building`, run `bin/holdco index`.
  The operator resumes its normal loop on next run — its **first build step is to author
  `BRAND.md`** (the brand-voice guide, while positioning is fresh), after which every
  customer-visible string runs through the voice gate (`/copy`) against it. See
  `docs/COPYWRITING.md`.
- **Shutter:** `bin/holdco shutter <name>` — stops the operator, marks it shuttered, appends
  a postmortem stub. The repo is preserved for reference.

Once greenlit, the operator runs its normal loop: assess → pick highest-leverage task →
delegate to `coder`/`designer` → review with the panel → log → rest. (See the per-venture
`AGENTS.md` and `.claude/agents/operator.md` for the full loop.)

## 4. holdco oversees the fleet

From this repo, `./holdco` runs the portfolio operator. Each pass it assesses every venture,
puts its attention on the highest-leverage one, delegates business work down to that venture's
operator, runs cross-venture reviews, and decides what to start / double down on / pause / kill.
It does **not** reach into a venture's code — it manages operators, not functions.

It drives operators as **background agents** (Claude Code's `claude --bg` + `claude agents`):

```bash
bin/holdco run <id>        # dispatch a background operator pass in the venture's repo
bin/holdco fleet           # status of every venture's operator session(s)
# steer: claude logs <id> · claude attach <id> · bin/holdco stop <id>
```

**How holdco drives operators is `docs/ORCHESTRATION.md`** (the verified decision record).

## 5. Improve the machine, not just the output

The leverage of a holding company is that one improvement compounds across the whole fleet.
When you learn something running one business — a better operator loop, a sharper reviewer, a
missing guardrail — **bake it back into `templates/new-venture/`** so the next business is born
with it. After editing the template, prove it still works:

```
VENTURES_ROOT=/tmp/holdco-smoke bin/holdco new smoke "Smoke Test" "scaffold sanity check"
cd /tmp/holdco-smoke/smoke && rake tasks:index && ls -la
```

## Conventions worth keeping (why they're here)

- **One file per task / per venture.** Parallel agents creating/finishing *different* entries
  touch *different* files, so they never race on a push. The `TASKS.md` / `PORTFOLIO.md` indexes
  are generated, never hand-edited.
- **Persona panel as productive tension.** The reviewers are picky on purpose and pull in
  conflicting directions (correctness vs. speed, margin vs. growth, legal caution vs. reach).
  The synthesis across that tension is the deliverable — run a "board review" before anything
  risky.
- **Builders own disjoint files, lint/test the whole repo, commit, and push themselves.** The
  operator stays out of the editor and reviews what comes back.
- **Durable state over chat.** tasks/, ventures/, docs, git, and memory survive a context clear;
  the in-session reply does not. Write it down or it's lost.
