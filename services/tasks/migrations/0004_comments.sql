-- Add comments table for task Q&A / async reply thread
-- Apply: wrangler d1 migrations apply holdco-tasks --remote

CREATE TABLE IF NOT EXISTS comments (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id    TEXT    NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  author     TEXT    NOT NULL DEFAULT 'owner',
  body       TEXT    NOT NULL,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS comments_task ON comments(task_id, created_at);
