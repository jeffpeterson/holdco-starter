# holdco-tasks

Cloudflare Worker + D1-backed kanban board for the holdco task portfolio.

- **Board URL:** https://your-tasks-worker.example.workers.dev
- **Worker name:** `holdco-tasks`
- **D1 database:** `holdco-tasks` (`<YOUR_D1_DATABASE_ID>`)

## Layout

```
src/worker.ts          — Cloudflare Worker (API + auth)
public/index.html      — Single-page kanban UI (served as static asset)
migrations/            — D1 SQL migrations (applied in order)
bin/deploy.sh          — One-command redeploy (migrate + deploy)
wrangler.toml          — Worker config (no secrets)
```

## Secrets

Set via `wrangler secret put` — never in git or wrangler.toml:

| Secret       | Purpose                                      |
|-------------|----------------------------------------------|
| `OWNER_TOKEN` | Browser session cookie; submit at `/login`  |
| `AGENT_TOKEN` | Bearer token for agents / `bin/holdco` CLI  |

The deploy token (`CLOUDFLARE_TASKS_TOKEN`) lives in `$HOLDCO_ROOT/.env` (gitignored).
The ambient `CLOUDFLARE_API_TOKEN` in the environment is read-only and cannot deploy.

## Redeploy

```bash
cd services/tasks
bin/deploy.sh            # migrate + deploy
bin/deploy.sh --migrate-only
bin/deploy.sh --deploy-only
```

The script reads `CLOUDFLARE_TASKS_TOKEN` from `$HOLDCO_ROOT/.env` automatically.

## API

All routes require `Authorization: Bearer <AGENT_TOKEN>` or the owner session cookie.

| Method | Path               | Description                                 |
|--------|--------------------|---------------------------------------------|
| GET    | `/api/v1/tasks`    | List tasks. Filters: `?venture=`, `?status=`, `?priority=`, `?kind=`, `?assignee=`, `?blocked_on_user=1`, `?venture=__inbox__` (no venture) |
| POST   | `/api/v1/tasks`    | Create task. Only `title` required.         |
| GET    | `/api/v1/tasks/:id` | Get task                                   |
| PATCH  | `/api/v1/tasks/:id` | Update task fields                         |
| DELETE | `/api/v1/tasks/:id` | Delete task                                |
| GET    | `/api/v1/tasks/:id/comments` | List a task's comment thread (Q&A / owner replies) |
| POST   | `/api/v1/tasks/:id/comments` | Add a comment (`body` required, `author` defaults `owner`) |
| GET    | `/api/v1/comments` | Comments for the operator-delivery loop. Filters: `?undelivered=1`, `?venture=`. Joins `venture_id` + `task_title`. |
| POST   | `/api/v1/comments/:id/delivered` | Stamp a comment `delivered_at` (exactly-once guard; powers `bin/holdco comments`) |
| GET    | `/api/v1/ventures` | List ventures                               |
| POST   | `/api/v1/ventures` | Register a venture                          |
| GET    | `/api/v1/asks`     | Tasks blocked on the user (blocked_on_user=1, status!=done) |

### Assignees

`owner`, `holdco`, plus one handle per operator (e.g. `acme`) — or `null` = unassigned.

### Inbox tasks

Tasks created without a `venture_id` land in the Inbox. Filter with `?venture=__inbox__`.
The board shows an "Inbox (no venture)" option in the venture dropdown.
