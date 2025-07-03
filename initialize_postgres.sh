#!/bin/bash

# Import CSV data into PostgreSQL
set -e

# The orchestrator passes the DB host as the first argument.
if [ -z "$1" ]; then
    echo "Error: Database host not provided." >&2
    exit 1
fi

# Set path to psql
PSQL="/usr/bin/psql"
PG_HOST=$1
PG_PORT="5432"
PG_USER=${POSTGRES_USER}
PG_PASS=${POSTGRES_PASSWORD}
PG_DB="postgres"
EXPORT_DIR="/app/postgres_export"

# Check if credentials are provided
if [ -z "$PG_USER" ] || [ -z "$PG_PASS" ]; then
    echo "Error: POSTGRES_USER and POSTGRES_PASSWORD must be set." >&2
    exit 1
fi

echo "PostgreSQL host: $PG_HOST"

# --- User Existence Check ---
echo "Checking for existing user..."
ACTUAL_USER_ID=$(PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -c "SELECT id FROM \"user\" LIMIT 1;" | xargs)
if [ -z "$ACTUAL_USER_ID" ]; then
    echo "ERROR: No user found in the database. A user must be created before data can be initialized." >&2
    exit 1
fi
echo "User found with ID: $ACTUAL_USER_ID. Proceeding with initialization."

# --- Schema Creation ---
# This section creates tables only if they don't exist.
# The 'NOTICE' messages from this are normal and can be ignored.
echo "Creating PostgreSQL schema if it doesn't exist..."
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<'EOF'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE TABLE IF NOT EXISTS domains ( "domainId" TEXT PRIMARY KEY, "baseDomain" TEXT NOT NULL, "configManaged" BOOLEAN NOT NULL DEFAULT FALSE );
CREATE TABLE IF NOT EXISTS orgs ( "orgId" TEXT PRIMARY KEY, name TEXT NOT NULL );
CREATE TABLE IF NOT EXISTS "orgDomains" ( "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, "domainId" TEXT NOT NULL REFERENCES domains("domainId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "exitNodes" ( "exitNodeId" SERIAL PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL, endpoint TEXT NOT NULL, "publicKey" TEXT NOT NULL, "listenPort" INTEGER NOT NULL, "reachableAt" TEXT );
CREATE TABLE IF NOT EXISTS sites ( "siteId" SERIAL PRIMARY KEY, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, "niceId" TEXT NOT NULL, "exitNode" INTEGER REFERENCES "exitNodes"("exitNodeId") ON DELETE SET NULL, name TEXT NOT NULL, "pubKey" TEXT, subnet TEXT NOT NULL, "bytesIn" INTEGER, "bytesOut" INTEGER, "lastBandwidthUpdate" TEXT, type TEXT NOT NULL, online BOOLEAN NOT NULL DEFAULT FALSE, "dockerSocketEnabled" BOOLEAN NOT NULL DEFAULT TRUE );
CREATE TABLE IF NOT EXISTS resources ( "resourceId" SERIAL PRIMARY KEY, "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, name TEXT NOT NULL, subdomain TEXT, "fullDomain" TEXT, "domainId" TEXT REFERENCES domains("domainId") ON DELETE SET NULL, ssl BOOLEAN NOT NULL DEFAULT FALSE, "blockAccess" BOOLEAN NOT NULL DEFAULT FALSE, sso BOOLEAN NOT NULL DEFAULT TRUE, http BOOLEAN NOT NULL DEFAULT TRUE, protocol TEXT NOT NULL, "proxyPort" INTEGER, "emailWhitelistEnabled" BOOLEAN NOT NULL DEFAULT FALSE, "isBaseDomain" BOOLEAN, "applyRules" BOOLEAN NOT NULL DEFAULT FALSE, enabled BOOLEAN NOT NULL DEFAULT TRUE, "stickySession" BOOLEAN NOT NULL DEFAULT FALSE, "tlsServerName" TEXT, "setHostHeader" TEXT );
CREATE TABLE IF NOT EXISTS targets ( "targetId" SERIAL PRIMARY KEY, "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE, ip TEXT NOT NULL, method TEXT, port INTEGER NOT NULL, "internalPort" INTEGER, enabled BOOLEAN NOT NULL DEFAULT TRUE );
CREATE TABLE IF NOT EXISTS idp ( "idpId" SERIAL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, "defaultRoleMapping" TEXT, "defaultOrgMapping" TEXT, "autoProvision" BOOLEAN NOT NULL DEFAULT FALSE );
CREATE TABLE IF NOT EXISTS "user" ( id TEXT PRIMARY KEY, email TEXT, username TEXT NOT NULL, name TEXT, type TEXT NOT NULL, "idpId" INTEGER REFERENCES idp("idpId") ON DELETE CASCADE, "passwordHash" TEXT, "twoFactorEnabled" BOOLEAN NOT NULL DEFAULT FALSE, "twoFactorSecret" TEXT, "emailVerified" BOOLEAN NOT NULL DEFAULT FALSE, "dateCreated" TEXT NOT NULL, "serverAdmin" BOOLEAN NOT NULL DEFAULT FALSE );
CREATE TABLE IF NOT EXISTS newt ( id TEXT PRIMARY KEY, "secretHash" TEXT NOT NULL, "dateCreated" TEXT NOT NULL, "siteId" INTEGER REFERENCES sites("siteId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "twoFactorBackupCodes" ( id SERIAL PRIMARY KEY, "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "codeHash" TEXT NOT NULL );
CREATE TABLE IF NOT EXISTS session ( id TEXT PRIMARY KEY, "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "expiresAt" BIGINT NOT NULL );
CREATE TABLE IF NOT EXISTS "newtSession" ( id TEXT PRIMARY KEY, "newtId" TEXT NOT NULL REFERENCES newt(id) ON DELETE CASCADE, "expiresAt" BIGINT NOT NULL );
CREATE TABLE IF NOT EXISTS roles ( "roleId" SERIAL PRIMARY KEY, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, "isAdmin" BOOLEAN, name TEXT NOT NULL, description TEXT );
CREATE TABLE IF NOT EXISTS "userOrgs" ( "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE RESTRICT, "isOwner" BOOLEAN NOT NULL DEFAULT FALSE );
CREATE TABLE IF NOT EXISTS "emailVerificationCodes" ( id SERIAL PRIMARY KEY, "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, email TEXT NOT NULL, code TEXT NOT NULL, "expiresAt" BIGINT NOT NULL );
CREATE TABLE IF NOT EXISTS "passwordResetTokens" ( id SERIAL PRIMARY KEY, "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, email TEXT NOT NULL, "tokenHash" TEXT NOT NULL, "expiresAt" BIGINT NOT NULL );
CREATE TABLE IF NOT EXISTS actions ( "actionId" TEXT PRIMARY KEY, name TEXT, description TEXT );
CREATE TABLE IF NOT EXISTS "roleActions" ( "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE, "actionId" TEXT NOT NULL REFERENCES actions("actionId") ON DELETE CASCADE, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "userActions" ( "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "actionId" TEXT NOT NULL REFERENCES actions("actionId") ON DELETE CASCADE, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "roleSites" ( "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE, "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "userSites" ( "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "roleResources" ( "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE, "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS "userResources" ( "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE, "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE );
CREATE TABLE IF NOT EXISTS limits ( "limitId" SERIAL PRIMARY KEY, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, name TEXT NOT NULL, value INTEGER NOT NULL, description TEXT );
CREATE TABLE IF NOT EXISTS "userInvites" ( "inviteId" TEXT PRIMARY KEY, "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE, email TEXT NOT NULL, "expiresAt" BIGINT NOT NULL, token TEXT NOT NULL, "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE );
-- Add other tables here...
EOF

# --- Data Import ---
echo "Importing CSV data non-destructively..."

# Function to import data for a table with a simple primary key
import_with_pk() {
    local table=$1
    local pk_column=$2
    local csv_file="$EXPORT_DIR/$table.csv"
    if [[ -f "$csv_file" && $(wc -l < "$csv_file") -gt 1 ]]; then
        echo "Importing data for $table..."
        PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<-"EOF"
            CREATE TEMP TABLE tmp_$table (LIKE "$table" INCLUDING DEFAULTS);
            \copy tmp_$table FROM '$csv_file' WITH CSV HEADER;
            INSERT INTO "$table" SELECT * FROM tmp_$table ON CONFLICT ("$pk_column") DO NOTHING;
            DROP TABLE tmp_$table;
EOF
    else
        echo "Skipped $table (file missing or empty)"
    fi
}

# Import tables with simple primary keys
import_with_pk "orgs" "orgId"
import_with_pk "roles" "roleId"
import_with_pk "resources" "resourceId"
import_with_pk "sites" "siteId"
import_with_pk "targets" "targetId"

# Special handling for userOrgs
USERORGS_CSV="$EXPORT_DIR/userOrgs.csv"
if [[ -f "$USERORGS_CSV" && $(wc -l < "$USERORGS_CSV") -gt 1 ]]; then
    echo "Importing data for userOrgs..."
    TEMP_CSV="/tmp/userOrgs_temp.csv"
    head -n 1 "$USERORGS_CSV" > "$TEMP_CSV"
    tail -n +2 "$USERORGS_CSV" | sed "s/^[^,]*/$ACTUAL_USER_ID/" >> "$TEMP_CSV"
    
    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<-"EOF"
        CREATE TEMP TABLE tmp_userOrgs (LIKE "userOrgs" INCLUDING DEFAULTS);
        \copy tmp_userOrgs FROM '$TEMP_CSV' WITH CSV HEADER;
        INSERT INTO "userOrgs" ("userId", "orgId", "roleId", "isOwner")
        SELECT "userId", "orgId", "roleId", "isOwner" FROM tmp_userOrgs
        ON CONFLICT ("userId", "orgId") DO NOTHING;
        DROP TABLE tmp_userOrgs;
EOF
    rm "$TEMP_CSV"
else
    echo "Skipped userOrgs (file missing or empty)"
fi

# Add unique constraint to userOrgs to support ON CONFLICT
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "ALTER TABLE \"userOrgs\" ADD CONSTRAINT userOrgs_userId_orgId_key UNIQUE (\"userId\", \"orgId\");" || true

#Reset Sequence After Import
echo "Resetting sequences for serial columns..."
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('resources', 'resourceId'), COALESCE((SELECT MAX(\"resourceId\") FROM resources), 1), true);"
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('targets', 'targetId'), COALESCE((SELECT MAX(\"targetId\") FROM targets), 1), true);"

echo "Import complete."
