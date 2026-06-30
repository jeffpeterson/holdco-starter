-- Add kind column to tasks: task | idea | bug | feedback
-- Apply: wrangler d1 migrations apply holdco-tasks --remote

ALTER TABLE tasks ADD COLUMN kind TEXT NOT NULL DEFAULT 'task';
CREATE INDEX IF NOT EXISTS tasks_kind ON tasks(kind);
