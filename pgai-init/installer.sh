#!/bin/sh
set -eu

read_secret() {
  secret_file="$1"
  tr -d '\r\n' < "$secret_file"
}

if [ -z "${PGAI_VECTORIZER_WORKER_DB_URL:-}" ]; then
  DB_PASSWORD_FILE="${PGAI_DB_PASSWORD_FILE:-/run/secrets/db_password}"
  DB_PASSWORD="$(read_secret "$DB_PASSWORD_FILE")"
  export PGAI_VECTORIZER_WORKER_DB_URL="postgres://${PGAI_DB_USER}:${DB_PASSWORD}@${PGAI_DB_HOST}:${PGAI_DB_PORT}/${PGAI_DB_DATABASE}"
fi

python -m pgai install -d "$PGAI_VECTORIZER_WORKER_DB_URL"

python - <<'PY'
import os
import psycopg

db_url = os.environ["PGAI_VECTORIZER_WORKER_DB_URL"]
with open("/pgai-init/vectorizer.sql", "r", encoding="utf-8") as f:
    sql = f.read()

with psycopg.connect(db_url, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute(sql)

print("pgai installed and vectorizer SQL applied")
PY
