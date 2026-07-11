# holdco

A **meta-manager for a portfolio of businesses, run by autonomous Claude agents.**
Each business is its own self-contained operator repo — its own working agreement,
persona panel, backlog, and `./<name>` launcher — that runs autonomously. holdco
sits above them: it keeps every operator running, allocates attention, runs
cross-venture reviews, and **stamps out new ventures from a template with one
command**.

> [!WARNING]
> ## Read this before you run anything
>
> holdco runs **autonomous Claude Code agents with `--dangerously-skip-permissions`**
> — full tool access, no per-action prompts — in long-lived `tmux` sessions on a
> persistent machine. Those agents can run shell commands, edit and push code, send
> email, and call any MCP server you've authorized, **without asking you first.**
> (The very first `bin/bootstrap` launch is the one exception: it defaults to
> Claude Code's safer `acceptEdits` mode until it hands off to the persistent
> operator — see `bin/bootstrap --help` for the full-autonomy opt-in.)
>
> Run it only on a box you control and are willing to let an agent operate, with
> credentials scoped to exactly what you intend. This is the design — autonomy is
> the point — but you must opt into it knowingly. Start in a throwaway VM if unsure.

## Prerequisites

- **[Claude Code](https://docs.claude.com/en/docs/claude-code)** — logged in, on a
  plan that can run **Opus**, the fleet's default (see `docs/COST.md` for cheaper
  opt-in models on a smaller plan).
- **tmux**, **Ruby + Rake**, **git** — required.
- Optional (holdco uses these when present): **bun** (email channel + Worker dev),
  **gh** (push venture repos), **whois** (domain-availability checks), **codex**
  (second engine + image generation).
- Linux is recommended — the supervisor's orphan-reaping uses `/proc`.

## Run it — one command, then it just starts working

**holdco doesn't interview you.** The CLI tools in this repo (`bin/holdco`, the
board client, email, the scaffold) are *holdco's own implements* — holdco runs
them on your behalf. The only thing you ever run is the launch:

```
git clone <your-repo-url> ~/code/holdco   # anywhere — it's location-independent
cd ~/code/holdco
bin/bootstrap
```

`bin/bootstrap` does a bare prerequisite check and then launches Claude with the
holdco persona. There's no config Q&A: holdco greets you in one short paragraph,
defaults its own config itself (**Opus**, always — never a model question), writes
`.env`, and gets straight to work — the **core works with zero optional
features** — moving itself into a persistent `tmux` session along the way. As it
hits a feature that needs something only you can supply (a domain, Cloudflare
access, …), it tells you then, in context — never as an upfront checklist.
`bin/bootstrap --check` runs just the prerequisite check.

**It deploys its own infrastructure.** Run **`/mcp`** and authorize `cloudflare-api`
in your browser — Claude Code's own auth grant, the one step only you can do — give
holdco a domain, and it stands up the fleet *itself*: creating the D1 database,
deploying the task-board and inbox/email Workers, and wiring DNS + email routing —
instead of handing you a setup checklist. It provisions each feature as soon as it
has the resource, and skips gracefully (noting what's pending) for anything you
haven't supplied yet. Runbook: `docs/PROVISIONING.md`.

After that, **you never type a command — except `/mcp`**, Claude Code's built-in MCP
auth flow, which only you can run and which is the one CLI step holdco can never do
for you. Everything else, you talk to holdco and it does the work:

- *"Start a new venture called Acme — an on-demand widget shop."* → it scaffolds the
  repo, registers it, and boots its operator.
- *"How's the fleet doing?"* → it reports every venture's status.
- *"Pause the trading venture."* / *"What are you waiting on me for?"* → it acts, or
  tells you.

Reach holdco any time by attaching to its tmux session (it tells you the name in
its first update), and — once email is on — just by emailing it. On first run,
holdco installs the self-healing cron itself (`@reboot` + `*/10` →
`bin/holdco-up`) so the supervisor survives reboots and crashes — the one bit of
host wiring, done without asking, since running `bin/bootstrap` is the ask.

## Layout

You don't operate these directly — this is a map of what holdco works with.

| Path | What it is |
|------|------------|
| `bin/` | holdco's own implements — the CLI, scaffold, email, supervisor scripts. holdco runs these; you don't. |
| `.claude/agents/` | The portfolio operator persona (`holdco`) + builders + the review panel. |
| `ventures/` | Portfolio registry, one tracked file per business, plus each scaffolded venture's own repo dir by default (gitignored — see `.gitignore`). Indexed by `PORTFOLIO.md` (generated). |
| `templates/new-venture/` | The scaffold every new business is stamped from. **Edit it to improve all future ventures.** |
| `tasks/` | Portfolio-level backlog, one file per task. Indexed by `TASKS.md` (generated). |
| `lib/tasks/` | The Rake machinery: `tasks.rake` (backlog, shared with every venture) + `ventures.rake` (registry + scaffold). |
| `services/` | Optional Cloudflare Workers (inbox + tasks board) and the email-channel MCP server. |
| `docs/` | `PLAYBOOK.md` (start-and-run flow), `PROVISIONING.md` (how holdco deploys its own infra), `CONFIG.md` (every env knob), `COST.md`, `EMAIL.md`, and more — reference material for holdco itself. |
| `AGENTS.md` | The holdco working agreement (also `CLAUDE.md`). |
| `WORKLOG.md` | Running narrative of each operating pass. |

## How it works

**This repo IS your holdco** — location-independent, so clone it anywhere; on first
run holdco records its own path as `HOLDCO_ROOT` in `.env`. New venture repos
scaffold **inside this checkout** by default, under `ventures/<id>/` (gitignored,
computed from `HOLDCO_ROOT` — never hardcoded, and overridable via
`VENTURES_ROOT`/`VENTURE_PATH`); an existing venture can live anywhere — its path
is recorded per-venture in `ventures/<id>.md`.

Under the hood (holdco's job, not yours): when you ask for a new venture, it clones
the template into a fresh repo, fills placeholders, git-inits, and registers it; that
repo boots its own autonomous operator running an assess → delegate → review → log
loop. holdco runs one level up, keeping the whole fleet alive and operating well.
Read **`docs/PLAYBOOK.md`** for the full flow and `docs/CONFIG.md` for every knob.

## License

MIT — see [LICENSE](LICENSE).
