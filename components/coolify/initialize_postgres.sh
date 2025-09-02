#!/bin/bash

# Coolify PostgreSQL initialization script
# This script can be used to modify Coolify's postgres database after deployment
# if needed for custom configurations or data seeding

set -e

# Load environment variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Determine which psql to use
if [[ -x /usr/bin/psql ]]; then
  PSQL="/usr/bin/psql"
else
  echo "psql executable not found, installing postgresql-client..."
  apt-get update -qq && apt-get install -y postgresql-client -qq
  PSQL="/usr/bin/psql"
  if [[ ! -x $PSQL ]]; then
    echo "Error: Failed to install psql. Please install postgresql-client manually."
    exit 1
  fi
fi

PG_CONTAINER_NAME=${PG_CONTAINER_NAME:-coolify-db}
PG_IP=$(docker network inspect coolify 2>/dev/null | \
    awk "/\"Name\": \"$PG_CONTAINER_NAME\"/,/IPv4Address/" | \
    grep '"IPv4Address"' | \
    sed -E 's/.*"IPv4Address": "([^/]+)\/.*",/\1/')

if [ -z "$PG_IP" ]; then
    echo "Error: Could not find IP address for container '$PG_CONTAINER_NAME'"
    exit 1
fi

echo "Coolify PostgreSQL container IP: $PG_IP"

PG_HOST=$PG_IP
PG_PORT="5432"
PG_USER=${DB_USERNAME}
PG_PASS=${DB_PASSWORD}
PG_DB=${DB_DATABASE:-coolify}

echo "Connecting to Coolify PostgreSQL database..."

# Example: Add custom configurations or data modifications here
# PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<'EOF'
# -- Add your custom SQL here
# -- For example, to modify Coolify settings or add custom data
# EOF

echo "Coolify PostgreSQL initialization complete."
