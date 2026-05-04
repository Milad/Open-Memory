#!/bin/sh
set -eu

MCP_DB_USER="${PGEDGE_MCP_DB_USER:?Missing PGEDGE_MCP_DB_USER}"
MCP_DB_PASSWORD="${PGEDGE_MCP_DB_PASSWORD:?Missing PGEDGE_MCP_DB_PASSWORD}"

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=mcp_user="$MCP_DB_USER" \
  --set=mcp_password="$MCP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'mcp_user', :'mcp_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'mcp_user') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'mcp_user', :'mcp_password')
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'mcp_user') \gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'mcp_user') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'mcp_user') \gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.memory_nodes TO %I', :'mcp_user') \gexec
SELECT format('GRANT USAGE, SELECT ON SEQUENCE public.memory_nodes_id_seq TO %I', :'mcp_user') \gexec
SELECT format('REVOKE ALL ON SCHEMA ai FROM %I', :'mcp_user')
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'ai') \gexec
SELECT format('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA ai FROM %I', :'mcp_user')
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'ai') \gexec
SELECT format('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ai FROM %I', :'mcp_user')
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'ai') \gexec
SELECT format('REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA ai FROM %I', :'mcp_user')
WHERE EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'ai') \gexec
SELECT format('ALTER ROLE %I IN DATABASE %I SET search_path = public', :'mcp_user', current_database()) \gexec
SQL
