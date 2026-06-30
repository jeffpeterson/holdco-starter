#!/usr/bin/env bash
# Deploy holdco-tasks Worker + apply D1 migrations.
# Reads CLOUDFLARE_TASKS_TOKEN from ~/code/holdco/.env (never committed).
#
# Usage: bin/deploy.sh [--migrate-only | --deploy-only]
set -euo pipefail

ENV_FILE="$HOME/code/holdco/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found" >&2
  exit 1
fi

export CLOUDFLARE_API_TOKEN
CLOUDFLARE_API_TOKEN=$(grep '^CLOUDFLARE_TASKS_TOKEN=' "$ENV_FILE" | cut -d= -f2-)

if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
  echo "Error: CLOUDFLARE_TASKS_TOKEN not set in $ENV_FILE" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

case "${1:-}" in
  --migrate-only)
    npx wrangler d1 migrations apply holdco-tasks --remote
    ;;
  --deploy-only)
    npx wrangler deploy
    ;;
  *)
    npx wrangler d1 migrations apply holdco-tasks --remote
    npx wrangler deploy
    ;;
esac
