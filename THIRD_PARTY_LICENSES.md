# Third-Party Licenses

This project depends on third-party software and container images. The list below summarizes the primary components and their upstream licenses.

## Core runtime components

1. `pgedge-postgres-mcp` (included as source under `./pgedge-postgres-mcp`)
- License: PostgreSQL License
- Source: https://github.com/pgEdge/pgedge-postgres-mcp
- License file: `pgedge-postgres-mcp/LICENSE.md`

2. `timescale/timescaledb-ha:pg17` (Docker image/repo)
- License: Apache License 2.0 (image repository)
- Source: https://github.com/timescale/timescaledb-docker-ha
- License file: https://github.com/timescale/timescaledb-docker-ha/blob/master/LICENSE

3. TimescaleDB extension (inside the Timescale image)
- License model: mixed
- Apache License 2.0 for code outside `tsl/`
- Timescale License for code in `tsl/`
- Source: https://github.com/timescale/timescaledb
- License file: https://github.com/timescale/timescaledb/blob/master/LICENSE

4. PostgreSQL
- License: PostgreSQL License
- Source: https://github.com/postgres/postgres
- Copyright/License:
  https://github.com/postgres/postgres/blob/master/COPYRIGHT

5. `timescale/pgai-vectorizer-worker:latest` / `pgai`
- License: PostgreSQL License
- Source: https://github.com/timescale/pgai
- License file: https://github.com/timescale/pgai/blob/main/LICENSE

6. `pgvector`
- License: PostgreSQL License
- Source: https://github.com/pgvector/pgvector
- License file: https://github.com/pgvector/pgvector/blob/master/LICENSE

7. `prodrigestivill/postgres-backup-local:17`
- License: MIT License
- Source: https://github.com/prodrigestivill/docker-postgres-backup-local
- License file:
  https://github.com/prodrigestivill/docker-postgres-backup-local/blob/master/LICENSE

8. `alpine:3.20` (used by `fs-init`)
- Alpine is a Linux distribution containing many packages with different licenses.
- Source: https://www.alpinelinux.org/
- Package license metadata: https://pkgs.alpinelinux.org/

## Notes

- This file is informational and does not replace the full license terms from each upstream project.
- If you redistribute images/binaries, review each upstream license in full and include required notices.
