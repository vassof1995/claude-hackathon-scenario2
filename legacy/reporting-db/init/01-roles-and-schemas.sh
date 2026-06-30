#!/bin/bash
# Bootstrap for the legacy on-prem Postgres.
# Runs once, as the superuser, on first container start (docker-entrypoint-initdb.d).
#
# Creates two schemas and three least-privilege roles:
#   app        owned by app_user      -> the web app's data (RW by web-api)
#   reporting  owned by batch_user    -> reconciliation output (RW by batch, read by teams)
#
#   app_user        LOGIN, owns app schema
#   batch_user      LOGIN, owns reporting schema, SELECT on app
#   report_reader   LOGIN, SELECT-only on reporting   <-- the five teams connect with this
#
# DDL for the tables themselves is owned by Flyway inside each Spring Boot app, not here.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE app_user      LOGIN PASSWORD '${APP_DB_PASSWORD}';
    CREATE ROLE batch_user    LOGIN PASSWORD '${BATCH_DB_PASSWORD}';
    CREATE ROLE report_reader LOGIN PASSWORD '${REPORT_DB_PASSWORD}';

    CREATE SCHEMA app       AUTHORIZATION app_user;
    CREATE SCHEMA reporting AUTHORIZATION batch_user;

    -- batch reads the app schema to reconcile it
    GRANT USAGE ON SCHEMA app TO batch_user;
    ALTER DEFAULT PRIVILEGES FOR ROLE app_user IN SCHEMA app
        GRANT SELECT ON TABLES TO batch_user;

    -- the five teams: read-only on reporting, nothing else
    GRANT USAGE ON SCHEMA reporting TO report_reader;
    ALTER DEFAULT PRIVILEGES FOR ROLE batch_user IN SCHEMA reporting
        GRANT SELECT ON TABLES TO report_reader;
EOSQL

echo "legacy bootstrap: roles app_user / batch_user / report_reader and schemas app / reporting created."
