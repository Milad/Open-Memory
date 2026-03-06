#!/bin/sh
set -eu

read_secret() {
  secret_file="$1"
  tr -d '\r\n' < "$secret_file"
}

DB_PASSWORD_FILE="${PGAI_DB_PASSWORD_FILE:-/run/secrets/db_password}"
VOYAGE_API_KEY_FILE="${VOYAGE_API_KEY_FILE:-/run/secrets/voyage_api_key}"

if [ -z "${PGAI_VECTORIZER_WORKER_DB_URL:-}" ]; then
  DB_PASSWORD="$(read_secret "$DB_PASSWORD_FILE")"
  export PGAI_VECTORIZER_WORKER_DB_URL="$(
    PGAI_DB_HOST="$PGAI_DB_HOST" \
    PGAI_DB_PORT="$PGAI_DB_PORT" \
    PGAI_DB_DATABASE="$PGAI_DB_DATABASE" \
    PGAI_DB_USER="$PGAI_DB_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    python3 - <<'PY'
from psycopg.conninfo import make_conninfo
import os

print(
    make_conninfo(
        host=os.environ["PGAI_DB_HOST"],
        port=os.environ["PGAI_DB_PORT"],
        dbname=os.environ["PGAI_DB_DATABASE"],
        user=os.environ["PGAI_DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )
)
PY
  )"
fi

if [ -f "$VOYAGE_API_KEY_FILE" ]; then
  export VOYAGE_API_KEY="$(read_secret "$VOYAGE_API_KEY_FILE")"
fi

exec python -m pgai vectorizer worker "$@"
