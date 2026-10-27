#!/usr/bin/env bash
set -eu

: "${ACCOUNT_PASSWORD:?ACCOUNT_PASSWORD is required}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=ON_ERROR_STOP=1 <<'SQL'
\getenv account_password ACCOUNT_PASSWORD
SELECT format('CREATE ROLE accountuser LOGIN PASSWORD %L', :'account_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'accountuser')
\gexec
SELECT format('GRANT accountuser TO %I', current_user)
\gexec
SELECT 'CREATE DATABASE accountdb OWNER accountuser'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'accountdb')
\gexec
SQL
