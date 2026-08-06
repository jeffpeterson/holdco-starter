#!/usr/bin/env bash
# session-snapshot.sh — SessionEnd lifecycle hook.
#
# Fires after the operator session exits, before workspace cleanup. Captures a
# lightweight breadcrumb so holdco can surface unexpectedly-terminated sessions
# that left uncommitted work behind.
#
# Writes (append-mode) to:
#   ~/.cache/claude-usage/<venture>-session-end.log
#
# Captures:
#   - Exit reason (CLAUDE_SESSION_END_REASON env var)
#   - git status --short (dirty-tree files, if any)
#   - Last 5 commits (git log)
#
# Design: always exit 0 (never block teardown); < 1 second; no jq required.

set -euo pipefail

# Derive venture id from the project dir name.
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
venture="$(basename "$project_dir")"

# Build log path; create parent dir if missing.
cache_dir="${HOME}/.cache/claude-usage"
mkdir -p "$cache_dir"
log_file="${cache_dir}/${venture}-session-end.log"

reason="${CLAUDE_SESSION_END_REASON:-unknown}"
ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

{
  echo "=== session-end $ts — venture=$venture reason=$reason ==="

  dirty="$(cd "$project_dir" && git status --short 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    echo "--- dirty tree ---"
    echo "$dirty"
  else
    echo "--- tree clean ---"
  fi

  recent="$(cd "$project_dir" && git log -5 --oneline 2>/dev/null || true)"
  if [ -n "$recent" ]; then
    echo "--- last 5 commits ---"
    echo "$recent"
  fi

  echo ""
} >> "$log_file"

exit 0
