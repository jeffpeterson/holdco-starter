#!/usr/bin/env bash
# trim-bash-output.sh — PostToolUse hook: trims large Bash output before it enters context.
#
# Claude Code PostToolUse hooks receive JSON on stdin and may return JSON on stdout.
# Returning { "hookSpecificOutput": { "hookEventName": "PostToolUse",
#             "updatedToolOutput": "..." } } replaces what Claude sees.
# Returning {} (or nothing) leaves the output untouched.
#
# Policy (conservative):
#   - Outputs <= 4000 chars:  pass through unchanged.
#   - Outputs >  4000 chars:  keep the last 200 lines; prepend a one-line notice.
#   - Always exit 0 so the hook never blocks tool execution.
#
# Requires: jq (installed on every venture host via the holdco setup).

set -euo pipefail

THRESHOLD=4000   # chars — below this, never trim
KEEP_LINES=200   # lines to keep from the tail of large output

input=$(cat)

# Extract tool_output from the hook payload.
output=$(printf '%s' "$input" | jq -r '.tool_output // empty' 2>/dev/null)

# If we can't parse the payload or there's no tool_output, pass through.
if [ -z "$output" ]; then
  echo '{}'
  exit 0
fi

len=${#output}

if [ "$len" -le "$THRESHOLD" ]; then
  # Short output — no-op.
  echo '{}'
  exit 0
fi

# Count total lines for the notice.
total_lines=$(printf '%s' "$output" | wc -l | tr -d ' ')

# Keep the last KEEP_LINES lines.
trimmed=$(printf '%s' "$output" | tail -n "$KEEP_LINES")

kept_lines=$(printf '%s' "$trimmed" | wc -l | tr -d ' ')
omitted=$(( total_lines - kept_lines ))

notice="[...${len} chars / ${total_lines} lines — ${omitted} lines omitted to save context; last ${kept_lines} lines below...]"
result="${notice}"$'\n'"${trimmed}"

# Emit the replacement payload.
jq -n --arg out "$result" \
  '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": $out}}'

exit 0
