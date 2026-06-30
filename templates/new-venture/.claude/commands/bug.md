---
description: File a bug report on the tasks board. Takes free text — title and optional
  detail. Files as kind=bug, priority=P1 (high), status=open under this venture.
argument-hint: "<title> [— optional detail]"
disable-model-invocation: true
allowed-tools: Bash
---

## File bug: $ARGUMENTS

### Current API state

!`source ${CLAUDE_PROJECT_DIR}/.env 2>/dev/null; echo "VENTURE_ID=${TASKS_VENTURE_ID:-{{VENTURE}}}" && echo "TASKS_WORKER_URL=${TASKS_WORKER_URL}" && echo "TOKEN_SET=$([ -n "$TASKS_AGENT_TOKEN" ] && echo yes || echo MISSING)"`

### Instructions

File the bug from $ARGUMENTS as a new task on the tasks board.

- `venture_id`: read from `TASKS_VENTURE_ID` in `.env` (shown above); fall back to `{{VENTURE}}`
- `kind`: `bug`
- `priority`: `P1`
- `status`: `open`

Use the first sentence of $ARGUMENTS as the `title`. Use any remaining text as `description`.

Run this to POST (substitute real venture_id, title, and description as JSON strings):

```bash
source ${CLAUDE_PROJECT_DIR}/.env
curl -sf -X POST "${TASKS_WORKER_URL}/api/v1/tasks" \
  -H "Authorization: Bearer ${TASKS_AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"venture_id":"<VENTURE_ID>","kind":"bug","priority":"P1","status":"open","title":"<TITLE>","description":"<DESC or null>"}'
```

Confirm the created task ID. If TASKS_AGENT_TOKEN is missing from `.env`, say so and stop.
