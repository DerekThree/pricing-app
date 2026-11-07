#!/usr/bin/env bash
set -eu

: "${ACCOUNT_PASSWORD:?ACCOUNT_PASSWORD is required}"
: "${RECOMMENDATION_PASSWORD:?RECOMMENDATION_PASSWORD is required}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=ON_ERROR_STOP=1 <<'SQL'
\getenv account_password ACCOUNT_PASSWORD
SELECT 'CREATE ROLE accountuser LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'accountuser')
\gexec
SELECT format('ALTER ROLE accountuser PASSWORD %L', :'account_password')
\gexec
SELECT format('GRANT accountuser TO %I', current_user)
\gexec
SELECT 'CREATE DATABASE accountdb OWNER accountuser'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'accountdb')
\gexec
\getenv recommendation_password RECOMMENDATION_PASSWORD
SELECT 'CREATE ROLE recommendationuser LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'recommendationuser')
\gexec
SELECT format('ALTER ROLE recommendationuser PASSWORD %L', :'recommendation_password')
\gexec
SELECT format('GRANT recommendationuser TO %I', current_user)
\gexec
SELECT 'CREATE DATABASE recommendationdb OWNER recommendationuser'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'recommendationdb')
\gexec
SQL
