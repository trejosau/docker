#!/usr/bin/env bash
set -Eeuo pipefail

required_variables=(
  POSTGRES_USER
  MISVALES_DEV_DB
  MISVALES_DEV_USER
  MISVALES_DEV_PASSWORD
  MISVALES_TEST_DB
  MISVALES_TEST_USER
  MISVALES_TEST_PASSWORD
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Required PostgreSQL initialization variable is empty: ${variable_name}" >&2
    exit 1
  fi
done

ensure_role() {
  local role_name="$1"
  local role_password="$2"

  psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --set=role_name="$role_name" --set=role_password="$role_password" <<'SQL'
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  :'role_name',
  :'role_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name') \gexec

ALTER ROLE :"role_name"
  WITH LOGIN PASSWORD :'role_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
SQL
}

ensure_database() {
  local database_name="$1"
  local owner_name="$2"

  psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --set=database_name="$database_name" --set=owner_name="$owner_name" <<'SQL'
SELECT format(
  'CREATE DATABASE %I OWNER %I ENCODING %L TEMPLATE template0',
  :'database_name',
  :'owner_name',
  'UTF8'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'database_name') \gexec

ALTER DATABASE :"database_name" OWNER TO :"owner_name";
ALTER DATABASE :"database_name" SET timezone TO 'UTC';
REVOKE ALL ON DATABASE :"database_name" FROM PUBLIC;
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE :"database_name" TO :"owner_name";
SQL

  psql --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database_name" \
    --set=owner_name="$owner_name" <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"owner_name";
ALTER SCHEMA public OWNER TO :"owner_name";
SQL
}

ensure_role "$MISVALES_DEV_USER" "$MISVALES_DEV_PASSWORD"
ensure_role "$MISVALES_TEST_USER" "$MISVALES_TEST_PASSWORD"
ensure_database "$MISVALES_DEV_DB" "$MISVALES_DEV_USER"
ensure_database "$MISVALES_TEST_DB" "$MISVALES_TEST_USER"

echo "MisVales development and test databases are initialized."
