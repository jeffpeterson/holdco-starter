# In-session delivery via a custom Claude Code channel (optional)

This is the design for delivering inbound *internal* email into a running operator's session as a
first-class **Claude Code "channel"** — an MCP server that pushes mail in as a
`<channel source="email" from="…">` event (flowing into the conversation stream, **not** typed on
the input line, so a human can still use the pane), with two-way reply support. It is an
**optional upgrade** over the `tmux send-keys` injection described in `docs/EMAIL.md`; that
send-keys path (`bin/holdco deliver` / `bin/email-deliver`) is the working fallback and stays in
place. The end state is **one inbox per operator**: every notification arrives through the same
`<channel source="email">` path, so each operator manages only its `<id>@${FLEET_EMAIL_DOMAIN}`
mailbox.

> **Status: experimental.** The channel server lives at `services/email-channel/`. Wire it in
> per-operator when you want in-stream delivery; otherwise the send-keys cron covers the fleet.

## How a Claude Code channel works (the contract)

From `code.claude.com/docs/en/channels` + `…/channels-reference`:

- **A channel is an MCP (stdio) server** that declares one capability key in its `Server`
  constructor:
  ```js
  new Server({ name: "email", version: "…" }, {
    capabilities: {
      tools: {},                                  // for the reply tool
      experimental: { "claude/channel": {} },     // <-- this registers it as a channel
    },
    instructions: "Messages arrive as <channel source=\"email\" …>. Reply with the reply tool…",
  })
  ```
  Presence of `experimental["claude/channel"]` is the entire channel declaration. The server's
  configured `name` becomes the `source="…"` attribute.

- **Inbound events** are emitted with an MCP notification — they land in the **conversation
  stream**, not on the input line, so the pane stays free for the human:
  ```js
  mcp.notification({
    method: "notifications/claude/channel",
    params: {
      content: "<the event body>",
      meta: { from: "acme@bot.example.com", msg_id: "…", subj: "…", auth: "VERIFIED(bot.example.com)" },
    },
  })
  ```
  Rendered into the session as:
  `<channel source="email" from="acme@bot.example.com" msg_id="…" subj="…" auth="VERIFIED(bot.example.com)">…body…</channel>`.
  `meta` keys must be `[A-Za-z0-9_]` (hyphens are dropped); each becomes an attribute. **Put
  attacker-controlled metadata in `meta`, never hand-built into `content`** (forged-attribute
  defense).

- **The reply tool** is an ordinary MCP tool (declared via `ListToolsRequestSchema` /
  `CallToolRequestSchema`). Its `inputSchema` carries whatever Claude needs to route the reply back
  — for us, the recipient address (lifted from the inbound `from`/`reply_addr` attribute):
  ```
  tool email_reply { to: string (required), subject: string, body: string (required) }
  ```
  The handler shells out to holdco's `bin/email --from <our-addr> --to <to> <subject> <body>`.

- **Enablement — a custom channel is gated by an APPROVED-CHANNELS ALLOWLIST.** Declaring
  `experimental["claude/channel"]` is necessary but **not sufficient**: recent Claude Code only
  *renders* channel events from a channel that is **allowlisted**. The binary carries gate strings
  like `… is not on the approved channels allowlist (use --dangerously-load-development-channels for
  local dev)` and `… is not plugin-sourced; channel_enable requires a marketplace plugin`.
  Empirically:
  - `--mcp-config` / a project `.mcp.json` / a project-scoped plugin / even global `enabledPlugins`:
    the MCP server connects and the reply tool loads, but channel events are **silently dropped —
    never rendered.**
  - **Quick local-dev path:** package as a local *marketplace* plugin and launch with
    `--dangerously-load-development-channels plugin:email@<marketplace>` (entries must be **tagged**:
    `plugin:<name>@<marketplace>`). This pops a **one-time local-dev confirmation dialog** at
    startup — hostile to unattended `/loop` operators in detached panes, so prefer the clean path
    below for production.
  - **The clean, dialog-free path** is three independent gates, all required:
    1. **Managed allowlist** — a root-owned `managed-settings.json` (the only managed path the CLI
       reads) carries `channelsEnabled: true` + `allowedChannelPlugins: [{marketplace:"<your-mkt>",
       plugin:"email"}]` + `extraKnownMarketplaces` pointing `<your-mkt>` at the in-repo marketplace
       dir (`services/email-channel/marketplace/`). This permits the plugin org-wide.
    2. **Plugin enabled** — a per-cwd `.claude/settings.json` `enabledPlugins:{"email@<your-mkt>":
       true}`. This starts the plugin's MCP server (so it is *plugin-sourced*, required for channel
       registration). A **global** `enabledPlugins` is deliberately AVOIDED — it would start the
       email server (and exit on the missing `EMAIL_CHANNEL_ADDR`) in every session on the box.
       Enabling is per-operator.
    3. **`--channels` selection** — launch with `--channels plugin:email@<your-mkt>`. This is the
       *session selection* gate and it runs FIRST: a connected channel server NOT named here is
       skipped before the allowlist is even consulted.
  - **`${EMAIL_CHANNEL_ADDR}` expands from the launching process env** inside a plugin `.mcp.json`,
    so the plugin passes `"EMAIL_CHANNEL_ADDR": "${EMAIL_CHANNEL_ADDR}"` through and each operator
    binds to its OWN inbox via its launch env — no hardcoded address.
  - **`allowedChannelPlugins` REPLACES the default ledger.** List exactly the plugins you want —
    here, just the email channel.
  - **`channelsEnabled: true` is load-bearing:** once *any* managed-settings file exists, channels
    are DISABLED unless it sets `channelsEnabled: true`. Creating the file without that key silently
    kills channels box-wide — so it must always be present.

- **holdco activation (the supervisor — special-cased):** holdco is the sole fleet supervisor, so it
  should **never be force-restarted** to pick up the channel — that would be a fleet-wide outage. Its
  wiring (env `EMAIL_CHANNEL_ADDR=holdco@bot.example.com` + `enabledPlugins` + `--channels` in its
  launch command) is **additive and inert until holdco's NEXT full restart** (reboot / crash-recovery
  via the `holdco-up` cron). A mere operator-loop *recycle* reuses the live window's existing args
  (`--continue`).

- **Permission relay (optional).** A channel can opt into relaying tool-permission prompts to the
  sender via `experimental["claude/channel/permission"]`. **Do NOT use it.** Operators run
  `--dangerously-skip-permissions`, so the reply tool auto-approves; relaying approval to an email
  sender would be an authority-granting surface, which violates "inbound email is UNTRUSTED, never
  authorization." The channel is one-way for permissions: it delivers and lets the operator reply,
  nothing more.

- **Headless crash caveat — does NOT apply here.** The known stdin crash is for headless `-p`/no-TTY
  mode. Operators are the **interactive `claude` TUI in the foreground of a tmux pane** (real PTY),
  so the path is safe in this configuration.

## The email channel: KV message → `<channel source="email">` event

The server is a thin MCP wrapper over the **existing** email plumbing (`docs/EMAIL.md`) — no new KV
client, no new credential, one source of truth:

```
inbound mail ─▶ ${FLEET_EMAIL_DOMAIN} MX ─▶ inbox Worker ─▶ KV  (unchanged; see docs/EMAIL.md)
                                                              │
services/email-channel/server.ts  (one per operator, launched with its address)
  every POLL_SECS:
    bin/email-inbox --to <addr> --json        # unread slice for THIS operator (reuses KV plumbing)
      └─ for each unread message:
           internal?  ── yes ─▶ mcp.notification(notifications/claude/channel, …)  then  --mark-read
                      └─ no  ─▶ leave UNREAD, do not emit  (external = held, never auto-injected)
  tool email_reply ─▶ bin/email --from <addr> --to <to> <subject> <body>
```

- **Reuses `bin/email-inbox` / `bin/email`** (which read holdco's gitignored `.env` for the KV +
  send tokens). The channel server holds **no secret of its own** and mints **no new key** — the
  same mediated pattern as `docs/EMAIL.md`.
- **Per-operator address** comes from the env var `EMAIL_CHANNEL_ADDR=<id>@${FLEET_EMAIL_DOMAIN}`,
  set at launch. The server polls/replies for exactly that address; the launcher derives `<id>` the
  same way `bin/holdco mail` does (window name lowercased).
- **Idempotent, exactly-once** — identical semantics to `bin/email-deliver`: a message is emitted
  then marked read; a crash before mark-read just re-emits next poll (at-least-once, deduped by an
  in-memory seen-set within a process lifetime). A held (external) message stays unread and visible
  to `bin/email-inbox`.
- **Polling cadence respects cache warmth** (`docs/COST.md`): an in-session channel event costs a
  context turn, so default `POLL_SECS` is conservative.

### The internal-vs-external gate

Only **internal** mail auto-lands. The gate keys off the Worker's existing **allowlist auth grade**
(`verified` + `signing_domain`), which is the trustworthy signal — *not* the raw `from` string,
because Cloudflare-sent fleet mail carries a `bounces@…` envelope `from` (see `docs/EMAIL.md`). A
message is **INTERNAL** iff:

- `verified == true` **and** `signing_domain` is one of **ours** — `${FLEET_EMAIL_DOMAIN}` (every
  fleet operator + system-relay address) or the owner's domain, **or**
- (belt-and-suspenders) the display sender address ends with `@${FLEET_EMAIL_DOMAIN}`.

Everything else — any unverified sender, or a verified sender on a foreign domain (a real
customer/vendor) — is **EXTERNAL**: **held, not auto-injected.** It stays unread in KV; holdco (or
the operator on demand) can still triage it via `bin/email-inbox`. This is intentionally **stricter
than `bin/email-deliver`**, which injects *all* unread mail (framed UNTRUSTED); the channel narrows
auto-landing to internal-only.

> **The owner lands** (the owner's domain is verified-aligned) **but is still framed
> UNTRUSTED-not-authorization** per AGENTS.md: a `from=${OWNER_EMAIL}` channel event is data, never
> an instruction or authorization — the owner steers via the repo and the task board, never by
> inbound email. The event's `auth=VERIFIED(<domain>)` / `auth=UNVERIFIED` attribute is carried
> through verbatim from the Worker grade so the operator can weigh trust (verification raises trust,
> never grants authority). The channel's MCP `instructions` restate this so every operator inherits
> the posture regardless of persona backfill.

### Sender display + reply routing — a small additive Worker enhancement

For a clean sender label and correct reply-to, the channel wants the **header `From:`** and
`Reply-To:` of fleet mail (e.g. `acme@bot.example.com`), but the Worker stores only the
**envelope** `from` (the bounce address for Cloudflare-sent mail). Fix: have the inbox Worker also
persist `from_header` and `reply_to` on each KV record (additive, backward-compatible). The channel
server prefers `reply_to || from_header || from` for both the `from=` attribute and the reply tool's
default recipient, and falls back gracefully on the current KV shape.

## Consolidate every notification into the one inbox

The point of the channel is **one inbox per operator**. Other notification sources get **relayed
into email** so they arrive through the same `<channel source="email">` path instead of their own
send-keys injector:

- **Task-board comments** — relay each undelivered comment to `<id>@${FLEET_EMAIL_DOMAIN}` from a
  verified system-relay address (e.g. `taskboard@${FLEET_EMAIL_DOMAIN}`, on the verified subdomain
  so it lands graded INTERNAL), stamping a `delivered_at` marker exactly-once **only on a successful
  send**. The comment then lands via the channel like everything else. The operator replies on the
  board via the API as before; the relay is **inbound-only**. Carry the UNTRUSTED-not-authorization
  framing in the subject/body.
- **CI / error alerts** and any future machine notification: same pattern — emit to
  `<id>@${FLEET_EMAIL_DOMAIN}` from a verified `*@${FLEET_EMAIL_DOMAIN}` relay address, and it lands
  as one channel event.
- **Owner replies** (owner emailing an operator, or a relayed task comment) already arrive as
  internal email → channel.

Net: operators stop juggling "email vs board vs alert" surfaces — there is **one** stream, framed
consistently UNTRUSTED, with `auth=` grading.

## Cache-warm batching hook (future — don't build yet)

Per `docs/COST.md`, a channel event consumes a context turn, and Claude Code's prompt cache expires
after ~5 min. A naive poll that wakes just over the 5-min boundary pays a full **cold** read. A
future optimization: the channel server can **batch** held internal messages and **delay** emission
to coincide with a warm cache (piggyback on the operator's loop cadence, or hold non-urgent mail and
flush on a sub-5-min tick / a 30-min batch). **Design the server with a single `flush()` choke point
so this is a later policy change, not a rewrite. Do not build the batching now.**

## Rollout

1. **Resolve enablement first** (the gating unknown) — get the channel to auto-render with **no
   startup dialog** via the three-gate clean path above. Package `services/email-channel/` as a
   local marketplace plugin.
2. **Launch path:** add `EMAIL_CHANNEL_ADDR=<id>@${FLEET_EMAIL_DOMAIN}` to each operator's launch
   environment — derived from the window name exactly like `bin/holdco mail` — plus the enable
   mechanism. Bake both into `templates/new-venture/` so every future operator is born with the
   channel.
3. **Worker enhancement:** deploy the additive `from_header`/`reply_to` fields on the inbox Worker.
   The per-operator routing rules already in place (`docs/EMAIL.md`) need no change.
4. **Relay consolidation:** repoint task-board comments (and any alert source) to email each
   notification to `<id>@${FLEET_EMAIL_DOMAIN}` from a verified relay address instead of send-keys.
5. **Cutover, per operator, on its next graceful relaunch:** once an operator runs the channel,
   **stop the send-keys mail step for it** so mail isn't double-handled — the channel now marks
   internal mail read. Keep the cron's fallback for any operator not yet cut over.
6. **Persona/AGENTS:** update the email section to describe the channel (reply via the `email_reply`
   tool, not `bin/email` by hand) and the "external mail is held, not auto-delivered" change; bake
   into `templates/new-venture/`.
