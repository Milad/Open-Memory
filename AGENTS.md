Rules:

- No changes are allowed in `pgedge-postgres-mcp` folder, because it's a 3rd-party dependency.
- Run Docker Compose commands from the project root (`open-brain/`) only, or pass both `-f docker-compose.yml` and `--project-directory` explicitly.
- Never print or expose secret values from `./secrets/*` or `.env` in logs, commits, screenshots, or responses.
- Do not commit real credentials. Keep `.env` non-sensitive and use secret files in `./secrets/`.
- Keep `./secrets` mounted read-only in services (`:ro`).
- Do not expose Postgres port `5432` to host unless explicitly requested.
- Preserve current bootstrap flow:
  - `fs-init` prepares directories and seeds `postgres/mcp-data/tokens.json` from `secrets/init_tokens`.
  - `mcp` depends on `fs-init` completion and `db` health.
- `mcp` must mount `./postgres/mcp-data:/app/data` for persistent `tokens.json`, `users.json`, and conversation DB.
- If authentication behaves unexpectedly, first check:
  - `docker compose exec -T mcp ls -al /app/data`
  - `docker compose exec -T mcp env | grep ^PGEDGE_DB_1_ | sort`
  - `docker compose logs --tail=120 mcp`
- Keep changes minimal and targeted; avoid unrelated refactors when fixing operational issues.
