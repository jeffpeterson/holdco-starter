-- holdco-tasks D1 schema
-- Apply: wrangler d1 migrations apply holdco-tasks --remote

CREATE TABLE IF NOT EXISTS ventures (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  tagline    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tasks (
  id              TEXT PRIMARY KEY,
  venture_id      TEXT NOT NULL REFERENCES ventures(id),
  title           TEXT NOT NULL,
  description     TEXT,
  priority        TEXT NOT NULL DEFAULT 'P2',  -- P0 | P1 | P2
  status          TEXT NOT NULL DEFAULT 'open', -- open | wip | done | blocked
  domain          TEXT,
  assignee        TEXT,
  blocked_on_user INTEGER NOT NULL DEFAULT 0,   -- 1 = needs owner decision
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS tasks_venture ON tasks(venture_id);
CREATE INDEX IF NOT EXISTS tasks_status  ON tasks(status);
CREATE INDEX IF NOT EXISTS tasks_blocked ON tasks(blocked_on_user) WHERE blocked_on_user = 1;
