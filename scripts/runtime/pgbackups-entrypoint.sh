#!/bin/sh
set -eu

read_secret() {
  secret_file="$1"
  tr -d '\r\n' < "$secret_file"
}

DB_PASSWORD_FILE="${POSTGRES_PASSWORD_FILE:-/run/secrets/db_password}"

if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -f "$DB_PASSWORD_FILE" ]; then
  export POSTGRES_PASSWORD="$(read_secret "$DB_PASSWORD_FILE")"
fi

exec /init.sh
