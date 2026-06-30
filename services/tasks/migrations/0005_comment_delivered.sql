-- Track which task comments have been pushed into a live operator's session.
-- NULL = not yet delivered; a timestamp = delivered (idempotent, never re-pushed).
-- Mirrors the email channel's read-marker so board→operator delivery is exactly-once.
-- Apply: wrangler d1 migrations apply holdco-tasks --remote

ALTER TABLE comments ADD COLUMN delivered_at TEXT;

CREATE INDEX IF NOT EXISTS comments_undelivered ON comments(delivered_at);
