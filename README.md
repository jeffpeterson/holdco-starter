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
>
> Run it only on a box you control and are willing to let an agent operate, with
> credentials scoped to exactly what you intend. This is the design — autonomy is
> the point — but you must opt into it knowingly. Start in a throwaway VM if unsure.

## Prerequisites

- **[Claude Code](https://docs.claude.com/en/docs/claude-code)** — logged in, on a
  plan that can run your chosen model. The fleet defaults to **Sonnet**; Opus is
  opt-in (see `docs/COST.md`).
- **tmux**, **Ruby + Rake**, **git** — required.
- Optional: **bun** (email channel + Worker dev), **gh** (push venture repos),
  **whois** (`bin/holdco domain`), **codex** (second engine + image generation).
- Linux is recommended — the supervisor's orphan-reaping uses `/proc`.

## Install

**This repo IS your holdco.** Clone it to **`~/code/holdco`** — that exact path is
strongly recommended:

```
git clone <your-repo-url> ~/code/holdco
cd ~/code/holdco
bin/bootstrap
```

The operator personas and fleet tooling reference holdco by the absolute path
`~/code/holdco` (e.g. `~/code/holdco/bin/email`, `~/code/holdco/bin/holdco`, and
sourcing `~/code/holdco/.env`). Venture repos are created as **siblings** under
`~/code/` by default (e.g. `~/code/acme`). If you install holdco anywhere else,
those cross-repo paths in operator personas won't resolve and fleet tooling calls
will break — so `~/code/holdco` is the canonical home. `bin/bootstrap` warns if it
detects holdco living elsewhere.

## Setup

```
bin/bootstrap        # checks prereqs, walks you through config, writes .env, seeds state
```

`bin/bootstrap` is idempotent — re-run it any time. The **core works with zero
optional features**; the email channel and the two Cloudflare Workers are opt-in
(it only collects their keys if you say yes). Run `bin/bootstrap --check` for a
non-interactive prerequisite check.

## First launch

```
./holdco                                              # boot the autonomous portfolio operator
bin/holdco new acme "Acme" "one-line tagline"         # scaffold your first venture
bin/holdco ls                                          # show the portfolio
bin/holdco fleet                                       # status of every venture's operator
bin/holdco                                             # help — every command
```

For the supervisor to survive reboots and crashes, add the self-healing cron
(`bin/bootstrap` prints the exact lines):

```
@reboot      /path/to/holdco/bin/holdco-up
*/10 * * * * /path/to/holdco/bin/holdco-up
```

`bin/holdco` is the CLI for everything — plain Ruby + Rake under the hood, no
framework. `./holdco` is a shim for `bin/holdco operate`.

## Layout

| Path | What it is |
|------|------------|
| `bin/holdco` | The CLI — ventures, tasks, fleet, and booting the operator. Start here. |
| `bin/bootstrap` | One-command idempotent setup. |
| `holdco` | Thin shim that boots the operator (`./holdco` → `bin/holdco operate`). |
| `.claude/agents/` | The portfolio operator persona (`holdco`) + builders + the review panel. |
| `ventures/` | Portfolio registry, one file per business. Indexed by `PORTFOLIO.md` (generated). |
| `templates/new-venture/` | The scaffold every new business is stamped from. **Edit it to improve all future ventures.** |
| `tasks/` | Portfolio-level backlog, one file per task. Indexed by `TASKS.md` (generated). |
| `lib/tasks/` | The Rake machinery: `tasks.rake` (backlog, shared with every venture) + `ventures.rake` (registry + scaffold). |
| `services/` | Optional Cloudflare Workers (inbox + tasks board) and the email-channel MCP server. |
| `docs/` | `PLAYBOOK.md` (start-and-run flow), `CONFIG.md` (every env knob), `COST.md`, `EMAIL.md`, and more. |
| `AGENTS.md` | The holdco working agreement (also `CLAUDE.md`). |
| `WORKLOG.md` | Running narrative of each operating pass. |

## How it works

Read **`docs/PLAYBOOK.md`** for the full flow. In short: `bin/holdco new` clones
the template into a new repo, fills placeholders, git-inits it, and registers it.
That repo's `./<name>` launcher boots an autonomous operator that runs its own
assess → delegate → review → log loop. `./holdco` runs the operator one level up,
keeping the whole fleet alive and operating well. Configuration lives in `.env`
(see `docs/CONFIG.md`); nothing required beyond a sane `OWNER_EMAIL`.

## License

MIT — see [LICENSE](LICENSE).
