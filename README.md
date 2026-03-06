# Open Memory (PostgreSQL + MCP + Auto Embeddings + Daily Backups)

Self-hosted memory service built on PostgreSQL (`pgvector` + `pgai`), an MCP server, and a scheduled backup container.

## Why

The goal is to run one MCP memory service that all your agents and LLM-powered tools can use together.
Instead of each tool keeping isolated memory "islands", this setup provides a shared memory/context layer across clients.

It combines:

- PostgreSQL for durable shared storage
- `pgvector` + `pgai` for semantic retrieval via embeddings
- MCP as the common access protocol for different agents/services
- scheduled backups for operational safety

## Credits

Inspired by [AI News & Strategy Daily | Nate B Jones](https://www.youtube.com/@NateBJones) and this video:

[![You Don't Need SaaS. The $0.10 System That Replaced My AI Workflow (45 Min No-Code Build)](https://i.ytimg.com/vi/2JiMmye2ezg/hqdefault.jpg)](https://youtu.be/2JiMmye2ezg)

This is my intepretation of his idea of Open Brain. I didn't see his own implemention.

## Services

- `db`: PostgreSQL 17 (Timescale HA image with pgvector/pgai support)
- `pgai-installer`: one-shot setup that installs pgai DB objects and creates vectorizer
- `vectorizer-worker`: background worker that auto-generates/updates embeddings
- `mcp`: Postgres MCP server exposed on `http://localhost:8080`
- `pgbackups`: daily dump backups written to `./postgres/backups`
- `postgres/mcp-data`: persistent MCP files (`tokens.json`, `users.json`, conversations)

## Prerequisites

- Docker Engine 24+
- Docker Compose v2+
- `git`
- I tested this on Ubuntu only, feel free to test it if you use other systems.

Check:

```bash
docker --version
docker compose version
```

## Install

1. Clone and enter the repo:

```bash
git clone https://github.com/Milad/open-memory.git open-memory
cd open-memory
```

2. Clone the MCP server dependency at `v1.0.0-beta3` (shallow):

```bash
git clone --depth 1 --branch v1.0.0-beta3 https://github.com/pgEdge/pgedge-postgres-mcp.git
```

3. Create env file:

```bash
cp .env.example .env
```

4. Create secret files (used by runtime wrappers):

```bash
mkdir -p secrets
printf '%s' 'your_db_password' > secrets/db_password
printf '%s' 'your_mcp_db_password' > secrets/mcp_db_password
printf '%s' 'your_voyage_key' > secrets/voyage_api_key
printf '%s' 'your_anthropic_key' > secrets/anthropic_api_key
printf '%s' 'token1,token2' > secrets/init_tokens
printf '%s' 'admin:strong_password' > secrets/init_users
chmod 600 secrets/*
```

5. Edit `.env` for non-secret settings only. The file uses generic names like `DB_NAME`, `DB_ADMIN_USER`, `MCP_DB_USER`, `LLM_MODEL`, and `HTTP_ADDRESS`; Docker Compose maps those into the internal `PGEDGE_*` variables required by the MCP runtime. Existing `.env` files that still use the older `PGEDGE_*` names continue to work.

Fresh installs create two database roles by default:

- `memory_admin`: owner/admin role used by PostgreSQL setup, pgai install, and the vectorizer worker
- `memory_mcp`: least-privilege role used only by the MCP server, granted access to `public.memory_nodes` and explicitly revoked from `ai`

`memory_mcp` is created during the initial PostgreSQL bootstrap from `init-db/02-mcp-role.sh`. If `secrets/mcp_db_password` is omitted, the stack falls back to `secrets/db_password`, but the role separation still applies.

## Run

Start all services in background:

```bash
docker compose up -d --build
```

Check status:

```bash
docker compose ps
```

Tail logs:

```bash
docker compose logs -f db pgai-installer vectorizer-worker mcp pgbackups
```

## Automatic embeddings (pgai Vectorizer)

This stack enables automatic embedding sync for `public.memory_nodes.content`:

- `pgai-installer` runs once, executes `pgai install`, then applies `pgai-init/vectorizer.sql`
- `vectorizer-worker` continuously processes queue jobs
- new/updated rows are embedded asynchronously into `memory_nodes.embedding`

The `ai` schema remains installed for pgai/vectorizer internals, but the MCP server connects with the restricted `memory_mcp` role and is explicitly revoked from `ai`, so schema discovery stays focused on `public.memory_nodes`.

Check vectorizer status:

```bash
docker compose logs -f vectorizer-worker
```

Ready SQL checks:

```sql
-- 1) pgai installed
SELECT extname FROM pg_extension WHERE extname IN ('ai', 'vector') ORDER BY extname;

-- 2) vectorizer registered
SELECT id, name FROM ai.vectorizer ORDER BY id;

-- 3) embeddings present
SELECT id, content, embedding IS NOT NULL AS has_embedding
FROM public.memory_nodes
ORDER BY id DESC
LIMIT 20;
```

Run them from host shell if you want:

```bash
DBPASS="$(tr -d '\r\n' < secrets/db_password)"
DBUSER="${DB_ADMIN_USER:-$(grep '^DB_ADMIN_USER=' .env | cut -d= -f2-)}"
DBNAME="${DB_NAME:-$(grep '^DB_NAME=' .env | cut -d= -f2-)}"
docker compose exec -T -e PGPASSWORD="$DBPASS" db psql \
  -U "$DBUSER" -d "$DBNAME" \
  -c "SELECT extname FROM pg_extension WHERE extname IN ('ai', 'vector') ORDER BY extname;" \
  -c "SELECT id, name FROM ai.vectorizer ORDER BY id;" \
  -c "SELECT id, content, embedding IS NOT NULL AS has_embedding FROM public.memory_nodes ORDER BY id DESC LIMIT 20;"
```

If query 3 returns zero rows, there is nothing to embed yet. Insert/update rows in `memory_nodes` and check again after a short delay.

## Use the MCP endpoint

The MCP server is exposed at:

- `http://localhost:8080/mcp/v1`

Auth header format:

- `Authorization: Bearer <token-from-secrets/init_tokens>`

### Codex MCP config example

Add/update this block in `~/.codex/config.toml`:

```toml
[mcp_servers.openmemory]
enabled = true
startup_timeout_sec = 30
command = "npx"
args = [
  "-y", "mcp-remote", "http://localhost:8080/mcp/v1",
  "--allow-http", "--transport", "http-only",
  "--header", "Authorization:${OPENMEMORY_AUTH_HEADER}",
  "--silent"
]
env = {"OPENMEMORY_AUTH_HEADER" = "Bearer <your-token>"}
```

After editing config, restart your Codex client/session.

## Self-host behind Nginx (`/open-memory`)

If you want to expose this service at:

- `https://mcp.example.com/open-memory`

use Nginx as a reverse proxy and forward the path prefix to the local MCP service (`mcp:8080` or `127.0.0.1:8080`).

Example Nginx server block:

```nginx
server {
    listen 443 ssl http2;
    server_name mcp.example.com;

    # TLS config (cert paths, ciphers, etc.) goes here

    # Redirect /open-memory -> /open-memory/
    location = /open-memory {
        return 301 /open-memory/;
    }

    # Proxy prefix path to MCP service root
    location /open-memory/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Authorization $http_authorization;

        # Strip "/open-memory/" prefix
        rewrite ^/open-memory/(.*)$ /$1 break;
        proxy_pass http://127.0.0.1:8080;
    }
}
```

With this setup, your public MCP endpoint becomes:

- `https://mcp.example.com/open-memory/mcp/v1`

Codex MCP config example for reverse proxy:

```toml
[mcp_servers.openbrain]
enabled = true
startup_timeout_sec = 30
command = "npx"
args = [
  "-y", "mcp-remote", "https://mcp.example.com/open-memory/mcp/v1",
  "--transport", "http-only",
  "--header", "Authorization:${OPENBRAIN_AUTH_HEADER}",
  "--silent"
]
env = {"OPENBRAIN_AUTH_HEADER" = "Bearer <your-token>"}
```

## Backups

`pgbackups` uses:

- `SCHEDULE="@daily"`
- retention:
  - `BACKUP_KEEP_DAYS=15`
  - `BACKUP_KEEP_WEEKS=4`
  - `BACKUP_KEEP_MONTHS=6`

Backup files are stored in:

- `./postgres/backups`

## Restore from backup

1. Pick a backup file from `./postgres/backups`.
2. Restore into the running DB:

```bash
DBPASS="$(tr -d '\r\n' < secrets/db_password)"
DBUSER="${DB_ADMIN_USER:-$(grep '^DB_ADMIN_USER=' .env | cut -d= -f2-)}"
DBNAME="${DB_NAME:-$(grep '^DB_NAME=' .env | cut -d= -f2-)}"
cat ./postgres/backups/<backup-file.sql.gz> | gunzip | docker exec -i -e PGPASSWORD="$DBPASS" open-memory-db psql -U "$DBUSER" -d "$DBNAME"
```

If your dump is plain `.sql` (not gzipped), use:

```bash
DBPASS="$(tr -d '\r\n' < secrets/db_password)"
DBUSER="${DB_ADMIN_USER:-$(grep '^DB_ADMIN_USER=' .env | cut -d= -f2-)}"
DBNAME="${DB_NAME:-$(grep '^DB_NAME=' .env | cut -d= -f2-)}"
cat ./postgres/backups/<backup-file.sql> | docker exec -i -e PGPASSWORD="$DBPASS" open-memory-db psql -U "$DBUSER" -d "$DBNAME"
```

## Project structure

- `docker-compose.yml`: service orchestration
- `.env.example`: required environment variables
- `init-db/01-init.sql`: DB extension/table/index bootstrap
- `pgai-init/installer.sh`: runs `pgai install` and applies vectorizer SQL
- `pgai-init/vectorizer.sql`: pgai vectorizer creation SQL
- `scripts/runtime/*.sh`: secret-file loaders and service startup wrappers
- `postgres/data/`: local PostgreSQL bind-mounted data directory
- `postgres/backups/`: local backup directory
- `postgres/mcp-data/`: persistent MCP runtime state (`tokens.json`, `users.json`, conversations)
- `pgedge-postgres-mcp/`: MCP server source/build context

## Common operations

Stop stack:

```bash
docker compose down
```

Stop and remove volumes (deletes DB data):

```bash
docker compose down -v
```

Rebuild only MCP service:

```bash
docker compose up -d --build mcp
```

Re-run pgai installer (idempotent):

```bash
docker compose up --force-recreate pgai-installer
```

## Security notes

- Do not commit `.env` with real secrets.
- Keep secret values out of `.env` and only in `./secrets/*`.
- Rotate tokens/keys if they were ever exposed.
- Keep `db` unexposed to host unless you explicitly need host-side SQL access.
- Third-party license inventory: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
- Read [pgEdge Postgres MCP Server: Best Practices - Querying the Server](https://docs.pgedge.com/pgedge-postgres-mcp-server/v1-0-0-beta3/guide/querying/)

## Production auth posture

Current observed state in this setup:

- `password_encryption = scram-sha-256`
- DB user password hash is SCRAM
- `pg_hba.conf` has:
  - `local all all scram-sha-256`
  - `host all all all scram-sha-256`
- `ssl = off` inside Postgres server (acceptable only if traffic stays inside a trusted private Docker network on one host, and external access is protected by HTTPS at your reverse proxy (Nginx/Caddy/Traefik).)

What to do for stricter policy:

1. This compose file sets strict init auth:
   `POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=scram-sha-256`
2. If you cannot reinitialize, edit `pg_hba.conf` in the data directory and reload config:
   `SELECT pg_reload_conf();`

## Secret files setup

This compose stack mounts `./secrets` as `/run/secrets` and reads files at startup.

- `db`: `POSTGRES_PASSWORD_FILE=/run/secrets/db_password`
- `pgai-installer`: reads `/run/secrets/db_password`
- `vectorizer-worker`: reads `/run/secrets/db_password` and `/run/secrets/voyage_api_key`
- `mcp`: reads `mcp_db_password` first, then falls back to `db_password`; it also reads `init_tokens`, `init_users`, `anthropic_api_key`, and `voyage_api_key`
- `pgbackups`: reads `/run/secrets/db_password`

Why this is different from `.env`:

- `.env` values are injected as container environment variables.
- Secret files are mounted as files, consumed at process startup, and can be rotated without rewriting `.env`.

Required files in `./secrets`:

- `db_password`
- `mcp_db_password`
- `voyage_api_key`
- `anthropic_api_key`
- `init_tokens`
- `init_users`
