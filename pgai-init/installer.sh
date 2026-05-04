#!/bin/sh
set -eu

if [ -z "${PGAI_VECTORIZER_WORKER_DB_URL:-}" ]; then
  DB_PASSWORD="${PGAI_DB_PASSWORD:-}"
  if [ -z "$DB_PASSWORD" ]; then
    echo "Missing PGAI_DB_PASSWORD." >&2
    exit 1
  fi
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

python -m pgai install -d "$PGAI_VECTORIZER_WORKER_DB_URL"

python - <<'PY'
import os
import psycopg

db_url = os.environ["PGAI_VECTORIZER_WORKER_DB_URL"]
with open("/pgai-init/vectorizer.sql", "r", encoding="utf-8") as f:
    vectorizer_sql = f.read()

with psycopg.connect(db_url, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute(vectorizer_sql)

print("pgai installed and vectorizer SQL applied")
PY
