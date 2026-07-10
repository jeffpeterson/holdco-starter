# Provisioning — holdco stands up its own infrastructure

holdco doesn't hand you a setup checklist — **when you give it the resources, it deploys the
features itself.** Given Cloudflare MCP auth and a domain, holdco creates the D1 database, deploys
the task-board and inbox Workers, wires DNS + email routing, and flips each feature on in `.env`.
This doc is the runbook holdco follows; you never run these steps by hand.

The rule: **provision each feature the moment its resources are available; gracefully skip a
feature whose resource isn't provided yet, and note what's pending** so holdco can finish it later
when you supply the missing piece.

## The target state (what "fully set up" means)

The known-good arrangement holdco drives toward:

1. **Task board live** — the D1-backed board Worker (`services/tasks/`) deployed, `TASKS_WORKER_URL`
   set, `AGENT_TOKEN`/`OWNER_TOKEN` minted. Then the PM board-janitor cron (`bin/holdco-pm`) runs.
2. **Inbox/email worker live** — the inbox Worker (`services/inbox-worker/`) deployed with its KV
   namespace, the sending path configured (Resend or Cloudflare Email), and Cloudflare **Email
   Routing** pointing `<id>@<FLEET_EMAIL_DOMAIN>` at the inbox Worker — so holdco and every operator
   have a working address.
3. **The fleet running** — holdco in its tmux session (`bin/holdco-up`), the self-heal cron
   (`@reboot` + `*/10`), the PM cron, all personas in place.

Until a resource arrives, the corresponding tier is skipped and the fleet runs at the level it
can: **with no Cloudflare auth and no domain, the core still runs fully** on the local git `tasks/`
backlog with email disabled.

## Resource → feature map

| You provide | holdco can then provision |
|-------------|---------------------------|
| **Cloudflare MCP auth** (or a scoped CF API token) | the D1 database + both Workers |
| **A domain on Cloudflare** | email addresses + Email Routing + a public board URL |
| **Resend API key** *(or Cloudflare Email Sending)* | outbound mail (`bin/email`) |
| **GitHub PAT** | pushing venture repos to GitHub |

Detect what's present (`.env`, whether the `cloudflare-api` MCP answers, whether a zone exists for
the domain) and provision accordingly. Missing one → note it as pending, do the rest.

**Getting the Cloudflare MCP auth is the one step only the owner can perform.** MCP OAuth is a
grant Claude Code runs in the owner's browser and stores in its own credential store — holdco
never constructs, fetches, or guesses at an OAuth URL itself; there is no such thing as holdco
generating an auth link. Ask the owner to run **`/mcp`** and authorize `cloudflare-api`, wait for
them to confirm it's connected, then holdco takes it from there automatically. This is the one
sanctioned exception to "the owner never touches a CLI" — every other step below is holdco's job.

## How holdco provisions (drive the `cloudflare-api` MCP; wrangler is the equivalent fallback)

Once the MCP auth is granted (above) or a scoped CF **token** is in `.env`, provisioning needs the
`cloudflare-api` MCP, which only a `general-purpose` agent or a fork of holdco carries — so
**delegate the deploy to such a subagent** (that IS you, with the tools), verify what it reports,
and record the result. Where MCP auth is absent but the token is present, the same steps run
through the bundled `wrangler` deploy scripts instead — pick whichever the available resource
supports.

### Feature: task board (needs Cloudflare)

1. Create a D1 database (via the CF MCP, or `wrangler d1 create holdco-tasks`); write its id into
   `services/tasks/wrangler.toml` (`database_id`).
2. Deploy the Worker + apply migrations: `services/tasks/bin/deploy.sh` (uses `CLOUDFLARE_TASKS_TOKEN`
   from `.env`), or the CF MCP deploy.
3. Mint and set the Worker secrets `AGENT_TOKEN` + `OWNER_TOKEN` (`wrangler secret put …`); put the
   same `TASKS_AGENT_TOKEN`/`TASKS_OWNER_TOKEN` and the deployed `TASKS_WORKER_URL` into `.env`.
4. Verify: `bin/holdco api:tasks` returns (empty list is success). Then the PM cron can run.

### Feature: inbox/email worker (needs Cloudflare + a domain)

1. Create a KV namespace (CF MCP or `wrangler kv namespace create`); write its id into
   `services/inbox-worker/wrangler.toml` and `.env` (`HOLDCO_INBOX_KV_NAMESPACE`).
2. Deploy: `cd services/inbox-worker && npx wrangler deploy`.
3. Configure sending: set `RESEND_API_KEY` (Resend) **or** `CLOUDFLARE_EMAIL_TOKEN` (Cloudflare
   Email) + `HOLDCO_CF_ACCOUNT_ID` in `.env`, and set `FLEET_EMAIL_DOMAIN`.
4. Wire **Email Routing** on the domain's zone (CF MCP): MX/verification records + a routing rule
   per address (`<id>@<FLEET_EMAIL_DOMAIN>` → the inbox Worker). See `docs/EMAIL.md`.
5. Verify: `bin/email-inbox` reads; a test `bin/email` send round-trips.

### Feature: DNS / public board URL (needs a domain)

Add the DNS records the enabled features need on the domain's Cloudflare zone (via the CF MCP):
the Email Routing records above, and — if you want the board reachable in a browser — a route/DNS
record for the board Worker. Keep the board private (tailnet or Cloudflare Access) unless you
intend it public.

## Mint keys narrowly — never the account key

Every token holdco sets is **scoped to exactly one job** (a Workers+D1-Edit token for deploys, a
KV-Edit token for the inbox reader, an Email-Send token for sending). Never reuse a full/account
key as a shortcut, and never move a key off this box. See the §Secrets rule in the persona.

## Graceful degradation (never block on a missing resource)

- **No Cloudflare auth** → skip both Workers; run on the local git `tasks/` backlog; note the board
  + email as pending.
- **No domain** → skip Email Routing + public board; if a send key exists, `bin/email` can still
  send from a verified address, otherwise email is off.
- **No send key** → email disabled (`FLEET_EMAIL_DOMAIN` blank); the fleet runs, owner reachable via
  tmux.
- **No GitHub PAT** → venture repos stay local (still git-inited); note push as pending.

Record every pending item so a later pass (or the owner supplying the resource) can finish it —
never treat a missing resource as a reason to stop.
