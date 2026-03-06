#!/bin/bash
set -euo pipefail

read_secret() {
  secret_file="$1"
  if [ -f "$secret_file" ]; then
    tr -d '\r\n' < "$secret_file"
  fi
}

require_env() {
  var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    echo "Missing required environment variable: $var_name" >&2
    exit 1
  fi
}

mcp_uid() {
  id -u mcp 2>/dev/null || echo 1001
}

mcp_gid() {
  id -g mcp 2>/dev/null || echo 1001
}

urlencode() {
  local raw="$1"
  local length="${#raw}"
  local encoded=""
  local i ch hex

  for ((i = 0; i < length; i++)); do
    ch="${raw:i:1}"
    case "$ch" in
      [a-zA-Z0-9.~_-])
        encoded+="$ch"
        ;;
      *)
        printf -v hex '%%%02X' "'$ch"
        encoded+="$hex"
        ;;
    esac
  done

  printf '%s' "$encoded"
}

write_tokens_file() {
  local token_file="$1"
  local tokens="$2"
  local uid gid first token token_hash

  uid="$(mcp_uid)"
  gid="$(mcp_gid)"
  mkdir -p "$(dirname "$token_file")"

  {
    echo "{"
    echo "  \"tokens\": {"
    first=true
    IFS=','
    for token in $tokens; do
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

  chown "$uid:$gid" "$token_file"
  chmod 600 "$token_file"
}

bootstrap_auth_files() {
  local data_dir token_file users_file tokens users uid gid user_entry username password count

  data_dir="${PGEDGE_DATA_DIR:-/app/data}"
  token_file="${PGEDGE_TOKEN_FILE:-${data_dir}/tokens.json}"
  users_file="${PGEDGE_USERS_FILE:-${data_dir}/users.json}"
  uid="$(mcp_uid)"
  gid="$(mcp_gid)"

  echo "Starting pgEdge Natural Language Agent..."
  echo "Data directory: $data_dir"
  mkdir -p "$data_dir"
  chown "$uid:$gid" "$data_dir"
  export PGEDGE_DATA_DIR="$data_dir"
  export PGEDGE_TOKEN_FILE="$token_file"
  export PGEDGE_USERS_FILE="$users_file"

  if [ -f /run/secrets/init_tokens ]; then
    tokens="$(read_secret /run/secrets/init_tokens)"
    if [ -n "$tokens" ]; then
      echo "Initializing tokens from INIT_TOKENS environment variable..."
      write_tokens_file "$token_file" "$tokens"
      echo "Created token file with $(printf '%s' "$tokens" | tr ',' '\n' | wc -l | tr -d ' ') tokens"
      echo "Token file contents:"
      echo "***REDACTED***"
    else
      printf '{"tokens": {}}\n' > "$token_file"
      chown "$uid:$gid" "$token_file"
      chmod 600 "$token_file"
      echo "Created empty token file (no tokens initialized)"
    fi
  elif [ ! -f "$token_file" ]; then
    printf '{"tokens": {}}\n' > "$token_file"
    chown "$uid:$gid" "$token_file"
    chmod 600 "$token_file"
    echo "Created empty token file (no tokens initialized)"
  fi

  if [ -f /run/secrets/init_users ]; then
    users="$(read_secret /run/secrets/init_users)"
    if [ -n "$users" ]; then
      echo "Initializing users from INIT_USERS environment variable..."
      printf '{}\n' > "$users_file"
      chown "$uid:$gid" "$users_file"
      chmod 600 "$users_file"
      count=0
      IFS=','
      for user_entry in $users; do
        username="$(printf '%s' "$user_entry" | cut -d: -f1)"
        password="$(printf '%s' "$user_entry" | cut -d: -f2-)"
        /app/pgedge-postgres-mcp -add-user -username "$username" -password "$password" -user-file "$users_file" -user-note "Auto-generated user"
        count=$((count + 1))
      done
      echo "Created users file with $count user(s)"
      chown "$uid:$gid" "$users_file"
    fi
  fi
}

write_runtime_config() {
  local config_file password encoded_password password_file allow_writes auth_enabled

  require_env PGEDGE_DB_1_HOST
  require_env PGEDGE_DB_1_PORT
  require_env PGEDGE_DB_1_DATABASE
  require_env PGEDGE_DB_1_USER

  password_file="${PGEDGE_DB_1_PASSWORD_FILE:-/run/secrets/db_password}"
  if [ ! -f "$password_file" ] && [ "$password_file" != "/run/secrets/db_password" ] && [ -f /run/secrets/db_password ]; then
    password_file="/run/secrets/db_password"
  fi

  password=""
  if [ -f "$password_file" ]; then
    password="$(read_secret "$password_file")"
  fi
  encoded_password="$(urlencode "$password")"

  auth_enabled="${PGEDGE_AUTH_ENABLED:-true}"
  allow_writes="${PGEDGE_DB_1_ALLOW_WRITES:-false}"
  config_file="${PGEDGE_SERVER_CONFIG_FILE:-/app/data/server-config.yaml}"

  cat > "$config_file" <<EOF
http:
  enabled: true
  address: ":8080"
  auth:
    enabled: ${auth_enabled}
    token_file: "${PGEDGE_TOKEN_FILE}"
    user_file: "${PGEDGE_USERS_FILE}"
databases:
  - name: "${PGEDGE_DB_1_NAME:-database}"
    host: "${PGEDGE_DB_1_HOST}"
    port: ${PGEDGE_DB_1_PORT}
    database: "${PGEDGE_DB_1_DATABASE}"
    user: "${PGEDGE_DB_1_USER}"
    password: "${encoded_password}"
    sslmode: "${PGEDGE_DB_1_SSLMODE:-prefer}"
    allow_writes: ${allow_writes}
EOF

  chown "$(mcp_uid):$(mcp_gid)" "$config_file"
  chmod 600 "$config_file"
  printf '%s\n' "$config_file"
}

start_server() {
  local config_file args
  config_file="$(write_runtime_config)"
  args=(/app/pgedge-postgres-mcp -config "$config_file")
  echo "Starting MCP server with arguments: -config $config_file"
  exec runuser mcp /bin/sh -c "exec /app/pgedge-postgres-mcp -config '$config_file'"
}

if [ -f /run/secrets/anthropic_api_key ]; then
  export PGEDGE_ANTHROPIC_API_KEY="$(read_secret /run/secrets/anthropic_api_key)"
fi

if [ -f /run/secrets/voyage_api_key ]; then
  export PGEDGE_VOYAGE_API_KEY="$(read_secret /run/secrets/voyage_api_key)"
fi

bootstrap_auth_files
start_server
