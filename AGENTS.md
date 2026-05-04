Rules:

- `.env` is production-sensitive. Never print or expose secret values from `.env` in logs, commits, screenshots, or responses.
- Do not commit real credentials. Keep the real `.env` untracked and set it to `0600` on live servers.
- Do not reintroduce `./secrets`-based runtime wiring unless explicitly requested.
- Do not add Docker Compose default-value fallbacks for required application settings. Required env vars must be set explicitly in `.env`.
- Run Docker Compose commands from the project root (`open-memory/`) only, or pass both `-f docker-compose.yml` and `--project-directory` explicitly.
- Do not expose Postgres port `5432` to host unless explicitly requested.
- Preserve current bootstrap flow:
  - `fs-init` prepares host-mounted directories.
  - `mcp` depends on `fs-init` completion and `db` health.
- `mcp` must mount `./postgres/mcp-data:/app/data` for persistent `tokens.json`, `users.json`, and conversation DB.
- Keep the two-role database model:
  - `DB_ADMIN_USER` is the primary/admin database role and may be used by PostgreSQL bootstrap, pgai install, vectorizer creation, and the vectorizer worker.
  - `MCP_DB_USER` is the restricted MCP application role and should only have the privileges needed for `public.memory_nodes`.
- If authentication behaves unexpectedly, first check:
  - `docker compose exec -T mcp ls -al /app/data`
  - `docker compose exec -T mcp env | grep ^PGEDGE_DB | sort`
  - `docker compose logs --tail=120 mcp`
- Keep changes minimal and targeted; avoid unrelated refactors when fixing operational issues.
