# How holdco runs venture operators

Decision record (2026-06-25, verified firsthand against Claude Code v2.1.191). How the manager
(holdco) spawns, drives, monitors, and persists the per-venture operators.

## TL;DR — operators run as named tmux windows

**Each venture's operator runs as a tmux window named after the FIRST WORD of the venture
`title` (e.g. `"Acme Labs"` → tab `"Acme"`, `"Acme"` → tab `"Acme"`)
in the owner's attached session, launched with `claude --remote-control "<Full Title> Operator"`
so it is remote-chattable from claude.ai/code or the mobile app.** The holdco supervisor's own
window is always `"HoldCo"`. The short tab name is what you see in tmux; the long
`"<Title> Operator"` is the remote-control conversation name. holdco wraps launch and monitoring
in two commands:

```bash
bin/holdco run <id>          # open the operator window in tmux (idempotent)
bin/holdco fleet             # status of every venture — tmux windows + claude agents
```

`bin/holdco run` resolves the venture's repo + operator persona and executes:

```bash
tmux new-window -t <session> -n "<first-word-of-title>" -c <repo> \
  claude --remote-control "<Full Title> Operator" \
         --model "${OP_MODEL:-sonnet}" --dangerously-skip-permissions \
         --append-system-prompt-file <repo>/.claude/agents/<operator>.md \
         "/loop /clear Continue <Title> operation."
# then: set-window-option automatic-rename off + a per-venture window colour
```

Operators default to **Sonnet** (friendly to smaller plans); set `OP_MODEL=opus` (or
`HOLDCO_MODEL=opus` for holdco itself) when a venture genuinely needs deeper reasoning.

Operators run a **continuous self-paced loop** — the `/loop /clear` opening prompt enters the
`/loop` skill (same pattern as holdco's own `bin/holdco operate`): wake, do a full pass, reschedule,
rest; repeat indefinitely. Each pass starts with a clean context (`/clear`). If a GOAL is provided via
`GOAL=…`, the prompt becomes `/loop /clear <GOAL>` instead.

Exception: a venture may use a **time-of-day cron cadence** where that fits the domain (e.g. a
market-hours venture runs on market-hours ticks via its own `CronCreate` jobs — leave that mechanism
alone; holdco just supervises the window, not the scheduling).

- **Tab name convention:** `title.split.first` — first word of the venture `title`, capitalised
  as written in the frontmatter. `"Acme Labs"` → `"Acme"`, `"Acme"` → `"Acme"`.
  The holdco window is always `"HoldCo"` (set by `bin/holdco-up`).
- **Target session** defaults to `holdco` (the owner's attached session); override with
  `HOLDCO_TMUX_SESSION`.  If the session doesn't exist (e.g. @reboot), it is created detached.
- **Window colour:** each window's status entry is coloured from the venture's frontmatter
  `color:` (ANSI name, e.g. `green`) or a stable hash-pick from the ANSI palette; `automatic-rename`
  is turned off so the tab label sticks.
- **Idempotent:** if a window with that tab name already exists, `run` is a no-op.
- **`bin/holdco fleet`** matches tmux windows by tab name (first word of title) first, then
  falls back to `claude agents --json --all` (for any remaining `--bg` sessions).

`bin/holdco fleet` shows each operator's tmux window status (running / idle) plus any
`--bg` background agents still visible in `claude agents`.

## The mechanism (verified firsthand)

- **Dispatch:** `tmux new-window -t <session> -n "<first-word-of-title>" -c <repo> claude --remote-control "<Full Title> Operator" …`
  opens a new tmux tab (labelled with the first word of the title, e.g. `"Acme"`) visible to
  the owner. `--remote-control "<Title> Operator"` registers the session under that conversation
  name so it's findable via claude.ai/code or mobile. The session persists as long as the tmux
  window is open. `-c <repo>` sets the working directory so the persona path and all venture
  tooling resolve correctly.
- **Idempotency:** `tmux list-windows -t <session> -F '#{window_name}'` checks for an existing
  window with the tab name (first word of title) before spawning; a second `bin/holdco run` call
  is a no-op.
- **Target session + detached-session guard:** defaults to session `holdco`; override with
  `HOLDCO_TMUX_SESSION`.  `bin/holdco run` (and `bin/operator-up` in each venture) creates the
  session detached if it doesn't exist, so holdco can relaunch an operator from anywhere
  (including before the owner has attached).
- **Reboot resilience — `bin/holdco-up` (the supervision root):** cron guards holdco itself;
  holdco's loop guards the fleet. The installed cron entry is:
  ```
  @reboot ${CLAUDE_PROJECT_DIR}/bin/holdco-up >> ${CLAUDE_PROJECT_DIR}/logs/holdco-up.log 2>&1
  ```
  `bin/holdco-up` idempotently ensures the `"HoldCo"` window exists in the `holdco` tmux
  session (creates the session detached if absent, no-ops if the window is already live). After a
  reboot or power loss cron fires it; holdco's operator loop then detects which venture windows
  are missing and relaunches them via `bin/operator-up`. **holdco is the ONLY thing cron
  *supervises*** — per-venture operators are supervised by holdco, not by additional cron entries.
- **Mechanical mail/comment delivery — `bin/holdco deliver` (NOT supervision):** a second cron
  entry pushes inbound owner messages (email + task-board comments) into live operator sessions on
  a fixed cadence, so a reply lands within minutes regardless of whether a holdco LLM pass is
  running. It is a **pure injector** — it never launches/relaunches windows or touches supervision;
  a dead window just leaves its mail/comments for next pass. The installed entry (note the locale —
  cron has none, but `bin/holdco` reads/writes UTF-8):
  ```
  LANG=C.UTF-8
  LC_ALL=C.UTF-8
  */3 * * * * /usr/bin/ruby ${CLAUDE_PROJECT_DIR}/bin/holdco deliver >> ${CLAUDE_PROJECT_DIR}/logs/deliver.log 2>&1
  ```
  See `docs/EMAIL.md` for the delivery design (idempotent, exactly-once via read/`delivered_at`
  markers). This does **not** weaken "holdco is the sole supervisor" — it does no supervision.
- **Monitor:** `bin/holdco fleet` (or `rake ventures:fleet`) checks tmux windows first, then
  parses `claude agents --json --all` for any `--bg` sessions still in flight (e.g. a venture
  before its next relaunch). Interactive `--remote-control` sessions appear in `claude agents`
  with `kind: "interactive"` and no `id`/`state` — the tmux window is the authoritative signal.
- **Steer:** `tmux attach -t <session>` then navigate to the operator's tab; or chat from
  claude.ai/code / mobile via remote-control. `claude logs <id>` / `claude attach <id>` still
  work if the session ID is known.
- **Persistence:** the session lives inside tmux, survives the launching terminal, and is
  captured in JSONL under `~/.claude/projects/<project>/<sessionId>.jsonl`. The window closes
  only when the process exits or the tmux session is destroyed.

## Why this over the alternatives

| Option | Verdict | Why |
|--------|---------|-----|
| **tmux window + `claude --remote-control`** | ✅ **Primary** | Owner sees every operator as a tab; sessions are remote-chattable from claude.ai/code / mobile; idempotent by window name; survives terminal close; holdco's loop relaunches any window that goes down (`bin/operator-up`), and the detached-session guard means it can do so even before the owner attaches. |
| **`claude --bg` + `claude agents`** | ⚠️ Superseded | Background agents are NOT remote-chattable (`--bg` and `--remote-control` are mutually exclusive); the owner can't talk to them without `claude attach`. Kept in fleet view for backward compat (e.g. a venture until next relaunch). |
| **Headless `claude -p --resume`** | ✅ One-shot variant | Good when holdco wants a *synchronous* single pass and to capture the result inline (it blocks until done). `-p` for "run this and give me the answer now." |
| **Routines** (web — cron ≥1h, `/fire` API, GitHub webhooks) | ✅ Complement | Unattended **cadence** without a human at the keyboard, for GitHub-hosted ventures (cloud-run, no local files). |
| **In-session subagents** (Agent/Task tool) | ❌ Not as operators | Bounded to holdco's session + repo + `CLAUDE.md`; can't be a venture's autonomous operator. Great for fan-out *within* a holdco pass (research, panel reviews). |
| **Agent SDK** (`@anthropic-ai/claude-agent-sdk`) | ❌ Not now | A library to build *one* agent, not a fleet manager. Only worth it if holdco's coordinator later becomes a standalone program with its own queue/dashboard. |
| **Agent Teams** (experimental) | ❌ | Inter-agent messaging + shared task list, but for one codebase, not isolated ventures. |

## Target architecture (layered)

1. **Now — `bin/holdco run` + `bin/holdco fleet`.** holdco opens each operator as a named tmux
   window (`claude --remote-control`, tab name = first word of title) and watches them via tmux
   window list + `claude agents`. Steer with `tmux attach -t <session>` or chat from claude.ai/code.
2. **Supervision — `bin/holdco-up` + holdco's loop.** cron (`@reboot`) fires `bin/holdco-up`
   after reboot/power-loss to recreate the `"HoldCo"` window. holdco's loop then checks that
   every operator's tmux window is alive and relaunches any that are down via `bin/operator-up` /
   `bin/holdco run`. There is NO per-operator cron watchdog — holdco is the sole supervisor.
   For cloud-hosted ventures, use Routines instead.
3. **Scale — graduate the coordinator to the Agent SDK.** Only if the tmux+remote-control model
   stops scaling (real queue, retries, dashboards).

## Memory recycling — `bin/operator-loop` (the proactive layer)

`claude … /loop /clear …` resets the **context window** each pass but NOT the OS process **RSS**,
which creeps up over hours/days — one operator recently ballooned to ~22GB and exhausted the
16GB box, locking the owner out of SSH. So every long-running operator (and holdco itself) is
launched **through `bin/operator-loop`**, a tiny bash supervisor that wraps the `claude` process:

- It runs claude in a **restart loop**. When claude exits — by recycle, crash, or otherwise — it
  relaunches with `--continue`, resuming the **same session thread** (SESSIONS.md links and the
  remote-control conversation stay valid; the operator's loop is unbroken). The relaunch is a
  fresh OS process, so the leaked RSS is reclaimed.
- A **watchdog** polls the claude subtree's RSS and recycles it (graceful SIGTERM → SIGKILL after
  a grace window) when RSS crosses a cap **or** the session outlives a max lifetime — whichever
  first. Operators persist to git/board continuously and `--continue` rehydrates context, so a
  recycle never loses the thread.
- **Config-driven** via `OPERATOR_*` env (defaults baked in): `OPERATOR_RSS_MAX_MB` (3000),
  `OPERATOR_MAX_LIFETIME` (4h), `OPERATOR_GRACE_SECS` (120), `OPERATOR_POLL_SECS` (30),
  `OPERATOR_NO_RECYCLE`/`OPERATOR_NO_LOOP`/`HOLDCO_NO_LOOP` escape hatches.
- **Wiring:** holdco's `bin/holdco operate` and `rake ventures:run` launch claude through
  holdco's `bin/operator-loop` (absolute path — holdco is the sole supervisor box, so this works
  for non-scaffolded ventures too); the new-venture template carries its own copy so a venture's
  own `./<name>` launcher is self-contained. **Off-switch:** the wrapper relaunches on any exit by
  design, so to take an operator offline kill its tmux **window** (`bin/holdco shutter <id>`),
  which kills the wrapper too.

This is the **proactive/graceful** layer; **earlyoom** (`-r 3600`, installed on-box) is the
last-resort backstop that kills a runaway if it somehow still races past the cap.

## Cost / observability
Pay per token, same as interactive Claude Code; no hosting cost when operators run locally
(Routines count against the subscription, daily cap applies). Observe via `claude agents --json`,
`claude logs <id>`, session transcripts under `~/.claude/projects/`, and each venture's
`WORKLOG.md`.

## Delegating within a holdco pass (subagent mechanics)

Fan-out *inside* a holdco pass (research, audits, panel reviews, builders on this repo) is how the
operator stays available. Lessons learned:

- **For "produce a result and hand it back" work, use an unnamed one-shot `Agent` or a `fork`.**
  Both auto-return — a one-shot returns its final message as the tool result; a fork returns via a
  task-notification (and inherits holdco's full conversation history). A subagent spawned **with a
  `name`** is a persistent *teammate*: it spawns **lean** (fresh context, ~same overhead as a
  one-shot — it does **not** inherit the lead's history), but it **must explicitly `SendMessage`
  its output back** — it won't auto-return. Its `idle_notification` with `idleReason:"available"`
  means *"my turn is done,"* **not** *"I failed"* — mistaking that for a failure is what stranded a
  research result in a teammate's terminal this session. Reserve named teammates for genuine
  multi-turn collaboration you'll actively steer; use one-shots/forks for fetches. **Context
  exhaustion is a *fork* risk** (forks carry ~66K+ of parent history), **not** a fresh-teammate one.
- **Don't prime a subagent's context.** They have holdco's full abilities — a different prompt, not
  a lesser one. Brief at the goal level and let them gather their own files/tools. If one can't find
  what it needs, fix its **persona**, not the prompt.
- **Agent type gates tool access.** "Full abilities" holds only for `general-purpose` and a fork of
  holdco — those carry the MCP servers (cloudflare-api, resend, github, linear, railway, stripe,
  whose OAuth grants live in the shared session credential store). The builders (`coder`/`designer`)
  and the read-only panel (graybeard/hipster/green-eyeshade/counsel/bullhorn/redteam) are restricted
  to code tools and **can't see MCP**. Pick `general-purpose`/fork when the job needs an MCP server;
  and never trust a restricted agent's explanation of *why* a tool-gated action failed — verify the
  gate yourself, since the agent can't tell a missing tool from a real error.
- **Route by model tier** (Opus = operators/builders, Sonnet = judgment panel, Haiku = pure
  scouts) — the single biggest cost lever. See `docs/RESEARCH-2026-06-claude-frontier.md`.

## Operator launch + durable scheduling (verified 2026-06-26, CLI 2.1.193)

- **Remote-control is a standing requirement** — the owner must be able to chat any operator. But
  `--bg` and `--remote-control` are **mutually exclusive**: a `--bg` session is not remote-chattable.
  So launch operators with **`claude --remote-control "<Venture Title> Operator"`** (persistent,
  named so it's findable in `claude agents`, remotely steerable), not `--bg`. Bake into `bin/holdco run`.
- **Durable scheduled tasks don't work here.** `CronCreate(durable:true)` is a **no-op** in 2.1.193 —
  it still reports "session-only, dies when Claude exits" and writes no `.claude/scheduled_tasks.json`
  (only a `.lock`). So in-session crons (`CronCreate`, `/loop`) are session-scoped and die with the
  session — unusable for a cadence that must survive. For a durable LOCAL cadence (e.g. a venture that
  needs to act on a schedule with local credentials), drive it from **system `crontab`** (set
  `CRON_TZ` for the right timezone) running a fresh headless `claude -p` per tick. Cloud Routines are
  durable but run in Anthropic's cloud → no access to local CLIs/keys.
- **BUT in-session crons DO fire in a `--remote-control` session** (verified: a probe fired a 1-min
  job 3×; only `--bg` headless doesn't fire them). This enables the **self-healing operator-crons
  pattern** (a market-hours venture uses it — better than dumb system cron when the cadence should adapt): the
  operator runs continuously (`--remote-control` in tmux), owns its cadence via its own `CronCreate`
  jobs, keeps a git-tracked **manifest** (`.claude/crons.md`) as source of truth, and **self-heals**
  on every session start (read manifest → `CronList` → re-create missing, dedupe by cron+prompt since
  `CronCreate` has no `name`). Re-arm daily to beat the 7-day expiry; holdco's loop relaunches
  it (via `bin/operator-up`) if the window is gone — holdco is the supervisor, no cron watchdog.
  Gotcha: `--dangerously-skip-permissions`
  does NOT bypass the "trust this folder?" gate for a fresh dir — pre-trust the repo.

## Sources
Verified firsthand on v2.1.191 (`claude --help`, `claude agents --help`, a live `--bg` dispatch).
Docs: agent view, headless mode, sessions, routines — https://code.claude.com/docs/en/.
