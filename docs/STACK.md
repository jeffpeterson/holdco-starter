# The default backend stack

The durable decision record for what a new venture's backend is built on. holdco reviewed a
cited research report and **settled** this — it's the default every new operator inherits via
`templates/new-venture/AGENTS.md`. This file holds the rationale + a copy-paste starter so the
"why" survives a context clear; the template holds the skimmable version operators read at
venture birth.

**It's a default, not a mandate.** The decision tree exists so an operator picks the right tool
fast, not so every venture is forced onto Workers. The container escape hatch is first-class.

## The one decision: Worker or container?

For any new **node-like service**, default to **Cloudflare Workers**. Take the **container**
escape hatch when the workload genuinely needs a full process. Decide by the criteria below —
don't relitigate the default each time.

```
Does it need ANY of:
  · a full framework (Rails/Django/Spring/Fastify)
  · native C/C++ addons or arbitrary binaries (sharp, FFmpeg, ImageMagick, headless Chrome)
  · a real persistent filesystem
  · a long-lived / daemon process
  · raw TCP / port binding
  · heavy, sustained CPU beyond ~5 min
  · >128 MB working memory
  · a single relational DB >10 GB
      │
   yes ├──────────────► CONTAINER (Render default · Fly.io if idle-cost dominates)
      │                 optionally front it with a Worker for routing/edge/MCP
   no  └──────────────► WORKER (Hono · D1/DO/KV/R2 · Queues/Cron)
```

## Workers default

- **Framework:** [Hono](https://hono.dev) — Web-standard, native to Workers, smallest footprint.
  Scaffold with Cloudflare's own C3: `npm create cloudflare@latest -- <app> --framework=hono`.
- **MCP-server ventures:** the Cloudflare Agents SDK `McpAgent` pattern — Streamable HTTP with
  built-in OAuth. Don't hand-roll the transport.

### Storage — pick by shape

| Need | Use | Notes |
|------|-----|-------|
| Relational / SQLite-scale (≤10 GB/db) | **D1** | SQLite at the edge; the default datastore. |
| Per-entity state + websockets | **Durable Objects** | SQLite-backed; one object per entity. |
| Config / cache | **KV** | Eventually consistent — not for read-after-write. |
| Files / blobs | **R2** | S3-compatible, zero egress fees. |
| Existing external Postgres | **Hyperdrive** | Pools + caches a Postgres you already run. |

### Jobs & schedules

- **Queues** — background work, **at-least-once** delivery, so **consumers must be idempotent**.
- **Cron Triggers** — scheduled work, 1-minute granularity.
- No separate worker process to deploy or supervise.

### Deploy

- `wrangler deploy` ships it.
- Secrets via `wrangler secret put` (never commit them; bindings/config in `wrangler.toml`).
- Local dev via Miniflare/workerd (`wrangler dev`).

## Container escape hatch

When the criteria above say container, **don't bend the workload onto Workers**. Deploy to a
container PaaS; optionally put a Worker in front for routing, edge caching, or an MCP endpoint.

- **Default = [Render](https://render.com)** — steadiest, lowest-ops, ~$7/mo always-on. Reach
  here when reliability and low operational overhead dominate.
- **[Fly.io](https://fly.io)** when idle-cost dominates — cleanest scale-to-zero.
- **Cloudflare Containers (GA Apr 2026) is NOT yet a replacement** for stateful container apps:
  ephemeral disk, no managed volumes. Only consider it for *stateless* container needs.

### Existing container apps stay put

An existing venture already shipped as a container workload (say a **Rails app on Railway**, e.g.
`~/code/acme`) that predates this decision is **not** migrated just to conform: if it's the right
shape for a container and the platform is working, there's no payoff in moving a live app. New
container ventures default to Render/Fly per above; existing ones stay put unless there's a
concrete reason to move.

## Footgun: local ≠ prod query timing

Local D1/KV reads are microseconds; **production adds ~10–50 ms per read** (it's a network hop).
N sequential queries that feel instant in local dev can stack up to hundreds of ms in prod.
**Batch queries**, avoid N+1 round-trips, and **test against a real (remote) D1** before trusting
latency — local Miniflare numbers lie about prod.

## Canonical Hono-on-Workers starter

C3 (`npm create cloudflare@latest -- <app> --framework=hono`) generates this for you. The minimal
shape, for reference:

`package.json`
```json
{
  "name": "<app>",
  "private": true,
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "dependencies": { "hono": "^4" },
  "devDependencies": { "wrangler": "^4" }
}
```

`wrangler.toml`
```toml
name = "<app>"
main = "src/index.ts"
compatibility_date = "2026-01-01"

# [[d1_databases]]
# binding = "DB"
# database_name = "<app>"
# database_id = "<from `wrangler d1 create`>"
```

`src/index.ts`
```ts
import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => c.text("ok"));

export default app;
```

Then `npm install` and `wrangler dev`. Add bindings to `wrangler.toml` as the storage table above
dictates; `wrangler deploy` to ship.
