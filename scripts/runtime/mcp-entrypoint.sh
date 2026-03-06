#!/bin/sh
set -eu

read_secret() {
  secret_file="$1"
  if [ -f "$secret_file" ]; then
    tr -d '\r\n' < "$secret_file"
  fi
}

create_token_file_if_missing() {
  token_file="${PGEDGE_TOKEN_FILE:-/app/data/tokens.json}"
  token_secret_file="/run/secrets/init_tokens"

  if [ -f "$token_file" ] || [ ! -f "$token_secret_file" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$token_file")"

  first=true
  {
    echo "{"
    echo "  \"tokens\": {"
    IFS=','
    for token in $(read_secret "$token_secret_file"); do
      [ -n "$token" ] || continue
      if [ "$first" = true ]; then
        first=false
      else
        echo ","
      fi
      token_hash="$(printf '%s' "$token" | sha256sum | cut -d' ' -f1)"
      printf '    "%s": {\n' "$token"
      printf '      "hash": "%s",\n' "$token_hash"
      printf '      "created_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '      "annotation": "Auto-generated token"\n'
      printf '    }'
    done
    echo
    echo "  }"
    echo "}"
  } > "$token_file"

  chmod 600 "$token_file"
}

# Bootstrap tokens quietly, then prevent init-server from logging them.
create_token_file_if_missing
if [ -f /run/secrets/init_tokens ]; then
  unset INIT_TOKENS
fi

# DB credential for generated MCP DB config.
if [ -f /run/secrets/db_password ]; then
  export PGEDGE_DB_1_PASSWORD="$(read_secret /run/secrets/db_password)"
fi

# Backward-compatible DB vars for init-server paths that expect PGEDGE_DB_*.
export PGEDGE_DB_HOST="${PGEDGE_DB_HOST:-${PGEDGE_DB_1_HOST:-}}"
export PGEDGE_DB_PORT="${PGEDGE_DB_PORT:-${PGEDGE_DB_1_PORT:-}}"
export PGEDGE_DB_NAME="${PGEDGE_DB_NAME:-${PGEDGE_DB_1_DATABASE:-}}"
export PGEDGE_DB_USER="${PGEDGE_DB_USER:-${PGEDGE_DB_1_USER:-}}"
export PGEDGE_DB_PASSWORD="${PGEDGE_DB_PASSWORD:-${PGEDGE_DB_1_PASSWORD:-}}"
export PGEDGE_DB_SSLMODE="${PGEDGE_DB_SSLMODE:-${PGEDGE_DB_1_SSLMODE:-prefer}}"

# Auth bootstrap files.
if [ -f /run/secrets/init_users ]; then
  export INIT_USERS="$(read_secret /run/secrets/init_users)"
fi

# Optional provider keys.
if [ -f /run/secrets/anthropic_api_key ]; then
  export PGEDGE_ANTHROPIC_API_KEY="$(read_secret /run/secrets/anthropic_api_key)"
fi

if [ -f /run/secrets/voyage_api_key ]; then
  export PGEDGE_VOYAGE_API_KEY="$(read_secret /run/secrets/voyage_api_key)"
fi

exec /app/init-server.sh
