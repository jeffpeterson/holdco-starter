# Configuration reference

Every knob the holdco machine reads, in one place. All are environment variables;
the durable ones live in `.env` (gitignored — `bin/bootstrap` writes it from
`.env.example`). Nothing here is required for the core to run except a sane
`OWNER_EMAIL`; everything else has a built-in default or gates an optional feature.

## Core identity

| Var | Default | What it does |
|-----|---------|--------------|
| `OWNER_EMAIL` | `owner@example.com` | Where the fleet sends owner-facing mail + digests. |
| `FLEET_EMAIL_DOMAIN` | _(blank)_ | Verified sending subdomain every fleet address lives on (e.g. `bot.example.com`). Each operator gets `<id>@<this domain>`. **Blank disables all email features.** |
| `VENTURES_ROOT` | repo's parent dir | Where `bin/holdco new` scaffolds new venture repos. |
| `HOLDCO_TMUX_SESSION` | `holdco` | tmux session name the fleet runs in. |

## Models

The fleet defaults to **Sonnet** to stay affordable on smaller plans. Opus is
available per-role via env var; reserve it for genuinely hard reasoning. See
`docs/COST.md`.

| Var | Default | What it does |
|-----|---------|--------------|
| `HOLDCO_MODEL` | `sonnet` | Model the supervisor session runs on. |
| `OP_MODEL` | `sonnet` | Model each venture operator runs on. |
| `DREAM_MODEL` | `sonnet` | Model the dream/maintenance cycle uses (never Opus). |

## Supervisor loop (`bin/holdco operate`)

| Var | Default | What it does |
|-----|---------|--------------|
| `HOLDCO_LOOP_EVERY` | self-paced | Interval for the supervisor's `/loop`. |
| `HOLDCO_NO_LOOP` | _(unset)_ | Set to disable the self-loop (single pass). |
| `HOLDCO_REMOTE` / `HOLDCO_REMOTE_NAME` | on / "HoldCo Operator" | `--remote-control` toggle + conversation name. |
| `HOLDCO_DRIVE` | _(unset)_ | Override the opening `/loop` prompt. |
| `HOLDCO_GOAL` | _(unset)_ | One-off goal injected into the opening prompt. |
| `HOLDCO_RESUME` | _(unset)_ | Resume a prior session id instead of starting fresh. |

## Operator launch (`rake ventures:run` / `bin/holdco run`)

| Var | Default | What it does |
|-----|---------|--------------|
| `GOAL` | persona-driven | Override the operator's opening goal (prefer leaving blank — let the persona pick the work). |
| `COLD_FALLBACK_EVERY` | `8h` | Self-wake fallback interval for `mode: cold` operators. |
| `OP_LOOP_EVERY`, `OP_NO_LOOP`, `OP_REMOTE`, `OP_REMOTE_NAME`, `OP_RESUME`, `OP_DRIVE` | — | Per-operator equivalents of the `HOLDCO_*` loop knobs. |

## Operator memory recycling (`bin/operator-loop`)

Long-running operators are recycled before their RSS balloons and OOMs the box.

| Var | Default | What it does |
|-----|---------|--------------|
| `OPERATOR_RSS_MAX_MB` | `3000` | Recycle when the claude subtree RSS exceeds this. |
| `OPERATOR_MAX_LIFETIME` | `4h` | Recycle after this long regardless (e.g. `90m`). |
| `OPERATOR_NO_RECYCLE` | _(unset)_ | Disable recycling. |
| `OPERATOR_POLL_SECS`, `OPERATOR_QUIET_SECS`, `OPERATOR_GRACE_SECS` | — | Recycle timing/quiescence tuning. |

## Cost auto-clear watcher (`bin/clear-watch*`)

| Var | Default | What it does |
|-----|---------|--------------|
| `CLEAR_WATCH_ARM` | `1` | `0` = dry-run (logs only, never sends `/clear`). |
| `CLEAR_WATCH_INTERVAL` | — | Tick cadence override. |

## Optional: email channel

Set only if you enable the email channel. Full setup in `docs/EMAIL.md`.

| Var | What it does |
|-----|--------------|
| `CLOUDFLARE_EMAIL_TOKEN` | Cloudflare Email Sending token (or use Resend). |
| `RESEND_API_KEY` | Resend key, if you send via Resend instead. |
| `HOLDCO_CF_ACCOUNT_ID` | Cloudflare account id (used by `bin/email` + inbox reader). |
| `HOLDCO_INBOX_KV_NAMESPACE` | KV namespace id the inbox Worker writes to. |
| `HOLDCO_INBOX_CF_TOKEN` | Token scoped to Workers KV read/write (inbox reader). |
| `EMAIL_CHANNEL_ADDR` | The address an in-session email channel binds to (set automatically per operator). |
| `EMAIL_FROM`, `HOLDCO_EMAIL_TO`, `HOLDCO_EMAIL_REPLY_TO` | Override `bin/email` defaults. |
| `EMAIL_DRY` | `1` = validate the payload without sending. |

## Optional: tasks board Worker

When `TASKS_WORKER_URL` is **blank**, the tool uses the local git-backed `tasks/`
backlog (fully functional). Set these to use the hosted board instead. See
`services/tasks/README.md`.

| Var | What it does |
|-----|--------------|
| `TASKS_WORKER_URL` | Base URL of your deployed tasks Worker. Blank = local backlog. |
| `TASKS_AGENT_TOKEN` | Agent bearer token (task CRUD). Presence of this routes `asks` to the API. |
| `TASKS_OWNER_TOKEN` | Owner bearer token (full read/write/admin). |
| `CLOUDFLARE_TASKS_TOKEN` | Cloudflare token to deploy the Worker (Workers + D1: Edit). |

## Optional: GitHub

| Var | What it does |
|-----|--------------|
| `GITHUB_PAT` | Personal access token (repo + workflow) for pushing venture repos. |

## Standard knobs honored

`EDITOR`/`VISUAL` (for `bin/holdco task` with no args), `NO_COLOR` (disable ANSI),
and `CLAUDE_PROJECT_DIR` (set by Claude Code; the statusline + hooks resolve paths
through it).
