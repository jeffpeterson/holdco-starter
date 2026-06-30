---
description: File a research request on the tasks board. Takes free text — question or
  topic and optional detail. Files as kind=research, status=open under this venture.
  Does NOT run the research itself — use the built-in /deep-research for that.
argument-hint: "<question or topic> [— optional detail]"
disable-model-invocation: true
allowed-tools: Bash
---

## File research request: $ARGUMENTS

### Current API state

!`source ${CLAUDE_PROJECT_DIR}/.env 2>/dev/null; echo "VENTURE_ID=${TASKS_VENTURE_ID:-{{VENTURE}}}" && echo "TASKS_WORKER_URL=${TASKS_WORKER_URL}" && echo "TOKEN_SET=$([ -n "$TASKS_AGENT_TOKEN" ] && echo yes || echo MISSING)"`

### Instructions

File the research request from $ARGUMENTS as a new task on the tasks board.

- `venture_id`: read from `TASKS_VENTURE_ID` in `.env` (shown above); fall back to `{{VENTURE}}`
- `kind`: `research`
- `status`: `open`

Use the first sentence of $ARGUMENTS as the `title`. Use any remaining text as `description`.
Append to the description: "To execute, run the built-in /deep-research on this question."

Run this to POST (substitute real venture_id, title, and description as JSON strings):

```bash
source ${CLAUDE_PROJECT_DIR}/.env
curl -sf -X POST "${TASKS_WORKER_URL}/api/v1/tasks" \
  -H "Authorization: Bearer ${TASKS_AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"venture_id":"<VENTURE_ID>","kind":"research","status":"open","title":"<TITLE>","description":"<DESC> To execute, run the built-in /deep-research on this question."}'
```

Confirm the created task ID. If TASKS_AGENT_TOKEN is missing from `.env`, say so and stop.
