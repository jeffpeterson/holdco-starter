---
description: File a general task on the tasks board. Takes free text — title and
  optional detail. Files as kind=task, priority=P2, status=open under the holdco venture.
  Use /idea, /bug, /feedback for typed capture; use /task for everything else.
argument-hint: "<title> [— optional detail]"
disable-model-invocation: true
allowed-tools: Bash
---

## File task: $ARGUMENTS

### Current API state

!`source ${CLAUDE_PROJECT_DIR}/.env 2>/dev/null; echo "TASKS_WORKER_URL=${TASKS_WORKER_URL}" && echo "TOKEN_SET=$([ -n "$TASKS_AGENT_TOKEN" ] && echo yes || echo MISSING)"`

### Instructions

File the task from $ARGUMENTS on the tasks board.

- `venture_id`: `holdco`
- `kind`: `task`
- `priority`: `P2`
- `status`: `open`

Use the first sentence of $ARGUMENTS as the `title`. Use any remaining text as `description`.

Run this to POST (substitute real title/description as JSON strings):

```bash
source ${CLAUDE_PROJECT_DIR}/.env
curl -sf -X POST "${TASKS_WORKER_URL}/api/v1/tasks" \
  -H "Authorization: Bearer ${TASKS_AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"venture_id":"holdco","kind":"task","priority":"P2","status":"open","title":"<TITLE>","description":"<DESC or null>"}'
```

Confirm the created task ID. If TASKS_AGENT_TOKEN is missing, say so and stop.
