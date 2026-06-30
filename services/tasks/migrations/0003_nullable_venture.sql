-- Make venture_id nullable so tasks can exist without a venture ("inbox" / unsorted).
-- SQLite cannot DROP NOT NULL directly, so we recreate the table.

PRAGMA foreign_keys=OFF;

CREATE TABLE tasks_v2 (
  id              TEXT PRIMARY KEY,
  venture_id      TEXT REFERENCES ventures(id),   -- nullable: NULL = inbox/unsorted
  title           TEXT NOT NULL,
  description     TEXT,
  priority        TEXT NOT NULL DEFAULT 'P2',
  status          TEXT NOT NULL DEFAULT 'open',
  domain          TEXT,
  assignee        TEXT,
  blocked_on_user INTEGER NOT NULL DEFAULT 0,
  kind            TEXT NOT NULL DEFAULT 'task',
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO tasks_v2 SELECT * FROM tasks;
DROP TABLE tasks;
ALTER TABLE tasks_v2 RENAME TO tasks;

CREATE INDEX IF NOT EXISTS tasks_venture ON tasks(venture_id);
CREATE INDEX IF NOT EXISTS tasks_status  ON tasks(status);
CREATE INDEX IF NOT EXISTS tasks_blocked ON tasks(blocked_on_user) WHERE blocked_on_user = 1;
CREATE INDEX IF NOT EXISTS tasks_kind    ON tasks(kind);

PRAGMA foreign_keys=ON;
