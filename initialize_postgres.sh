#!/bin/bash

# Import CSV data into PostgreSQL
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

PG_CONTAINER_NAME=${POSTGRES_HOST:-pangolin-postgres}
PG_IP=$(docker network inspect pangolin 2>/dev/null | \
    awk "/\"Name\": \"$PG_CONTAINER_NAME\"/,/IPv4Address/" | \
    grep '"IPv4Address"' | \
    sed -E 's/.*"IPv4Address": "([^/]+)\/.*",/\1/')

if [ -z "$PG_IP" ]; then
    echo "Error: Could not find IP address for container '$PG_CONTAINER_NAME'"
    exit 1
fi

echo "PostgreSQL container IP: $PG_IP"

EXPORT_DIR="${1:-./postgres_export}"
PG_HOST=$PG_IP
PG_PORT="5432"
PG_USER=$POSTGRES_USER
PG_PASS=$POSTGRES_PASSWORD
PG_DB="postgres"

echo "Creating PostgreSQL schema..."

# Function to create PostgreSQL database structure
create_postgres_structure() {
    local pg_host=$PG_HOST
    local pg_port=$PG_PORT
    local pg_user=$PG_USER
    local pg_pass=$PG_PASS
    local pg_db=$PG_DB

    # Create database if it doesn't exist
    PGPASSWORD="$pg_pass" $PSQL -h "$pg_host" -p "$pg_port" -U "$pg_user" -d postgres -c "CREATE DATABASE $PG_DB;" 2>/dev/null || true

    # Create Pangolin tables based on the actual schema
    PGPASSWORD="$pg_pass" $PSQL -h "$pg_host" -p "$pg_port" -U "$pg_user" -d "$pg_db" <<'EOF'
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Domains table
CREATE TABLE IF NOT EXISTS domains (
    "domainId" TEXT PRIMARY KEY,
    "baseDomain" TEXT NOT NULL,
    "configManaged" BOOLEAN NOT NULL DEFAULT FALSE,
    "type" TEXT,
    "verified" BOOLEAN DEFAULT false NOT NULL,
    "failed" BOOLEAN DEFAULT false NOT NULL,
    "tries" INTEGER DEFAULT 0 NOT NULL    
);

-- Organizations table
CREATE TABLE IF NOT EXISTS orgs (
    "orgId" TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    subnet TEXT
);

-- Organization domains table
CREATE TABLE IF NOT EXISTS "orgDomains" (
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "domainId" TEXT NOT NULL REFERENCES domains("domainId") ON DELETE CASCADE
);

-- Exit nodes table
CREATE TABLE IF NOT EXISTS "exitNodes" (
    "exitNodeId" SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    "publicKey" TEXT NOT NULL,
    "listenPort" INTEGER NOT NULL,
    "reachableAt" TEXT,
    "maxConnections" INTEGER
);

-- Sites table
CREATE TABLE IF NOT EXISTS sites (
    "siteId" SERIAL PRIMARY KEY,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "niceId" TEXT NOT NULL,
    "exitNode" INTEGER REFERENCES "exitNodes"("exitNodeId") ON DELETE SET NULL,
    name TEXT NOT NULL,
    "pubKey" TEXT,
    subnet TEXT NOT NULL,
    "bytesIn" INTEGER DEFAULT 0,
    "bytesOut" INTEGER DEFAULT 0,
    "lastBandwidthUpdate" TEXT,
    type TEXT NOT NULL,
    online BOOLEAN NOT NULL DEFAULT FALSE,
    "address" TEXT,
    "endpoint" TEXT,
    "publicKey" TEXT,
    "lastHolePunch" BIGINT,
    "listenPort" INTEGER,
    "dockerSocketEnabled" BOOLEAN NOT NULL DEFAULT TRUE
);

-- Resources table
CREATE TABLE IF NOT EXISTS resources (
    "resourceId" SERIAL PRIMARY KEY,
    "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    name TEXT NOT NULL,
    subdomain TEXT,
    "fullDomain" TEXT,
    "domainId" TEXT REFERENCES domains("domainId") ON DELETE SET NULL,
    ssl BOOLEAN NOT NULL DEFAULT FALSE,
    "blockAccess" BOOLEAN NOT NULL DEFAULT FALSE,
    sso BOOLEAN NOT NULL DEFAULT TRUE,
    http BOOLEAN NOT NULL DEFAULT TRUE,
    protocol TEXT NOT NULL,
    "proxyPort" INTEGER,
    "emailWhitelistEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "applyRules" BOOLEAN NOT NULL DEFAULT FALSE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    "stickySession" BOOLEAN NOT NULL DEFAULT FALSE,
    "tlsServerName" TEXT,
    "setHostHeader" TEXT
);

-- Targets table
CREATE TABLE IF NOT EXISTS targets (
    "targetId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    ip TEXT NOT NULL,
    method TEXT,
    port INTEGER NOT NULL,
    "internalPort" INTEGER,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

-- Identity providers table
CREATE TABLE IF NOT EXISTS idp (
    "idpId" SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    "defaultRoleMapping" TEXT,
    "defaultOrgMapping" TEXT,
    "autoProvision" BOOLEAN NOT NULL DEFAULT FALSE
);

-- Users table
CREATE TABLE IF NOT EXISTS "user" (
    id TEXT PRIMARY KEY,
    email TEXT,
    username TEXT NOT NULL,
    name TEXT,
    type TEXT NOT NULL,
    "idpId" INTEGER REFERENCES idp("idpId") ON DELETE CASCADE,
    "passwordHash" TEXT,
    "twoFactorEnabled" BOOLEAN NOT NULL DEFAULT FALSE,
    "twoFactorSecret" TEXT,
    "emailVerified" BOOLEAN NOT NULL DEFAULT FALSE,
    "dateCreated" TEXT NOT NULL,
    "serverAdmin" BOOLEAN NOT NULL DEFAULT FALSE,
    "twoFactorSetupRequested" BOOLEAN DEFAULT false
);

-- Newt table
CREATE TABLE IF NOT EXISTS newt (
    id TEXT PRIMARY KEY,
    "secretHash" TEXT NOT NULL,
    "dateCreated" TEXT NOT NULL,
    "siteId" INTEGER REFERENCES sites("siteId") ON DELETE CASCADE,
    "version" TEXT
);

-- Two factor backup codes table
CREATE TABLE IF NOT EXISTS "twoFactorBackupCodes" (
    id SERIAL PRIMARY KEY,
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "codeHash" TEXT NOT NULL
);

-- Sessions table
CREATE TABLE IF NOT EXISTS session (
    id TEXT PRIMARY KEY,
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "expiresAt" BIGINT NOT NULL
);

-- Newt sessions table
CREATE TABLE IF NOT EXISTS "newtSession" (
    id TEXT PRIMARY KEY,
    "newtId" TEXT NOT NULL REFERENCES newt(id) ON DELETE CASCADE,
    "expiresAt" BIGINT NOT NULL
);

-- User organizations table
CREATE TABLE IF NOT EXISTS "userOrgs" (
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "roleId" INTEGER NOT NULL,
    "isOwner" BOOLEAN NOT NULL DEFAULT FALSE
);

-- Email verification codes table
CREATE TABLE IF NOT EXISTS "emailVerificationCodes" (
    id SERIAL PRIMARY KEY,
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    "expiresAt" BIGINT NOT NULL
);

-- Password reset tokens table
CREATE TABLE IF NOT EXISTS "passwordResetTokens" (
    id SERIAL PRIMARY KEY,
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" BIGINT NOT NULL
);

-- Actions table
CREATE TABLE IF NOT EXISTS actions (
    "actionId" TEXT PRIMARY KEY,
    name TEXT,
    description TEXT
);

-- Roles table
CREATE TABLE IF NOT EXISTS roles (
    "roleId" SERIAL PRIMARY KEY,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "isAdmin" BOOLEAN,
    name TEXT NOT NULL,
    description TEXT
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'userOrgs_roleId_fkey'
    ) THEN
        ALTER TABLE "userOrgs"
        ADD CONSTRAINT "userOrgs_roleId_fkey"
        FOREIGN KEY ("roleId") REFERENCES "roles"("roleId");
    END IF;
END
$$;

-- Role actions table
CREATE TABLE IF NOT EXISTS "roleActions" (
    "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE,
    "actionId" TEXT NOT NULL REFERENCES actions("actionId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE
);

-- User actions table
CREATE TABLE IF NOT EXISTS "userActions" (
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "actionId" TEXT NOT NULL REFERENCES actions("actionId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE
);

-- Role sites table
CREATE TABLE IF NOT EXISTS "roleSites" (
    "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE,
    "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE
);

-- User sites table
CREATE TABLE IF NOT EXISTS "userSites" (
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE
);

-- Role resources table
CREATE TABLE IF NOT EXISTS "roleResources" (
    "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE
);

-- User resources table
CREATE TABLE IF NOT EXISTS "userResources" (
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE
);

-- Limits table
CREATE TABLE IF NOT EXISTS limits (
    "limitId" SERIAL PRIMARY KEY,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    name TEXT NOT NULL,
    value INTEGER NOT NULL,
    description TEXT
);

-- User invites table
CREATE TABLE IF NOT EXISTS "userInvites" (
    "inviteId" TEXT PRIMARY KEY,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    email TEXT NOT NULL,
    "expiresAt" BIGINT NOT NULL,
    token TEXT NOT NULL,
    "roleId" INTEGER NOT NULL REFERENCES roles("roleId") ON DELETE CASCADE
);

-- Resource pincode table
CREATE TABLE IF NOT EXISTS "resourcePincode" (
    "pincodeId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    "pincodeHash" TEXT NOT NULL,
    "digitLength" INTEGER NOT NULL
);

-- Resource password table
CREATE TABLE IF NOT EXISTS "resourcePassword" (
    "passwordId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    "passwordHash" TEXT NOT NULL
);

-- Resource access token table
CREATE TABLE IF NOT EXISTS "resourceAccessToken" (
    "accessTokenId" TEXT PRIMARY KEY,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    "tokenHash" TEXT NOT NULL,
    "sessionLength" BIGINT NOT NULL,
    "expiresAt" BIGINT,
    title TEXT,
    description TEXT,
    "createdAt" BIGINT NOT NULL
);

-- Resource whitelist table
CREATE TABLE IF NOT EXISTS "resourceWhitelist" (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE
);

-- Resource sessions table
CREATE TABLE IF NOT EXISTS "resourceSessions" (
    id TEXT PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    "expiresAt" BIGINT NOT NULL,
    "sessionLength" BIGINT NOT NULL,
    "doNotExtend" BOOLEAN NOT NULL DEFAULT FALSE,
    "isRequestToken" BOOLEAN,
    "userSessionId" TEXT REFERENCES session(id) ON DELETE CASCADE,
    "passwordId" INTEGER REFERENCES "resourcePassword"("passwordId") ON DELETE CASCADE,
    "pincodeId" INTEGER REFERENCES "resourcePincode"("pincodeId") ON DELETE CASCADE,
    "whitelistId" INTEGER REFERENCES "resourceWhitelist"(id) ON DELETE CASCADE,
    "accessTokenId" TEXT REFERENCES "resourceAccessToken"("accessTokenId") ON DELETE CASCADE
);

-- Resource OTP table
CREATE TABLE IF NOT EXISTS "resourceOtp" (
    "otpId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    email TEXT NOT NULL,
    "otpHash" TEXT NOT NULL,
    "expiresAt" BIGINT NOT NULL
);

-- Version migrations table
CREATE TABLE IF NOT EXISTS "versionMigrations" (
    version TEXT PRIMARY KEY,
    "executedAt" BIGINT NOT NULL
);

-- Resource rules table
CREATE TABLE IF NOT EXISTS "resourceRules" (
    "ruleId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    priority INTEGER NOT NULL,
    action TEXT NOT NULL,
    match TEXT NOT NULL,
    value TEXT NOT NULL
);

-- Supporter key table
CREATE TABLE IF NOT EXISTS "supporterKey" (
    "keyId" SERIAL PRIMARY KEY,
    key TEXT NOT NULL,
    "githubUsername" TEXT NOT NULL,
    phrase TEXT,
    tier TEXT,
    valid BOOLEAN NOT NULL DEFAULT FALSE
);

-- IDP OIDC config table
CREATE TABLE IF NOT EXISTS "idpOidcConfig" (
    "idpOauthConfigId" SERIAL PRIMARY KEY,
    "idpId" INTEGER NOT NULL REFERENCES idp("idpId") ON DELETE CASCADE,
    "clientId" TEXT NOT NULL,
    "clientSecret" TEXT NOT NULL,
    "authUrl" TEXT NOT NULL,
    "tokenUrl" TEXT NOT NULL,
    "identifierPath" TEXT NOT NULL,
    "emailPath" TEXT,
    "namePath" TEXT,
    scopes TEXT NOT NULL
);

-- License key table
CREATE TABLE IF NOT EXISTS "licenseKey" (
    "licenseKeyId" TEXT PRIMARY KEY NOT NULL,
    "instanceId" TEXT NOT NULL,
    token TEXT NOT NULL
);

-- Host meta table
CREATE TABLE IF NOT EXISTS "hostMeta" (
    "hostMetaId" TEXT PRIMARY KEY NOT NULL,
    "createdAt" BIGINT NOT NULL
);

-- API keys table
CREATE TABLE IF NOT EXISTS "apiKeys" (
    "apiKeyId" TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    "apiKeyHash" TEXT NOT NULL,
    "lastChars" TEXT NOT NULL,
    "dateCreated" TEXT NOT NULL,
    "isRoot" BOOLEAN NOT NULL DEFAULT FALSE
);

-- API key actions table
CREATE TABLE IF NOT EXISTS "apiKeyActions" (
    "apiKeyId" TEXT NOT NULL REFERENCES "apiKeys"("apiKeyId") ON DELETE CASCADE,
    "actionId" TEXT NOT NULL REFERENCES actions("actionId") ON DELETE CASCADE
);

-- API key org table
CREATE TABLE IF NOT EXISTS "apiKeyOrg" (
    "apiKeyId" TEXT NOT NULL REFERENCES "apiKeys"("apiKeyId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE
);

-- IDP org table
CREATE TABLE IF NOT EXISTS "idpOrg" (
    "idpId" INTEGER NOT NULL REFERENCES idp("idpId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "roleMapping" TEXT,
    "orgMapping" TEXT
);

CREATE TABLE IF NOT EXISTS "clientSites" (
    "clientId" integer NOT NULL,
    "siteId" integer NOT NULL,
    "isRelayed" boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS "clients" (
    "id" serial PRIMARY KEY NOT NULL,
    "orgId" varchar NOT NULL,
    "exitNode" integer,
    "name" varchar NOT NULL,
    "pubKey" varchar,
    "subnet" varchar NOT NULL,
    "bytesIn" integer,
    "bytesOut" integer,
    "lastBandwidthUpdate" varchar,
    "lastPing" varchar,
    "type" varchar NOT NULL,
    "online" boolean DEFAULT false NOT NULL,
    "endpoint" varchar,
    "lastHolePunch" integer,
    "maxConnections" integer
);

CREATE TABLE IF NOT EXISTS "clientSession" (
    "id" varchar PRIMARY KEY NOT NULL,
    "olmId" varchar NOT NULL,
    "expiresAt" integer NOT NULL
);

CREATE TABLE IF NOT EXISTS "olms" (
    "id" varchar PRIMARY KEY NOT NULL,
    "secretHash" varchar NOT NULL,
    "dateCreated" varchar NOT NULL,
    "clientId" integer
);

CREATE TABLE IF NOT EXISTS "roleClients" (
    "roleId" integer NOT NULL,
    "clientId" integer NOT NULL
);

CREATE TABLE IF NOT EXISTS "webauthnCredentials" (
    "credentialId" varchar PRIMARY KEY NOT NULL,
    "userId" varchar NOT NULL,
    "publicKey" varchar NOT NULL,
    "signCount" integer NOT NULL,
    "transports" varchar,
    "name" varchar,
    "lastUsed" varchar NOT NULL,
    "dateCreated" varchar NOT NULL,
    "securityKeyName" varchar
);

CREATE TABLE IF NOT EXISTS "userClients" (
    "userId" varchar NOT NULL,
    "clientId" integer NOT NULL
);

CREATE TABLE IF NOT EXISTS "webauthnChallenge" (
    "sessionId" varchar PRIMARY KEY NOT NULL,
    "challenge" varchar NOT NULL,
    "securityKeyName" varchar,
    "userId" varchar,
    "expiresAt" bigint NOT NULL
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sites_org_id ON sites("orgId");
CREATE INDEX IF NOT EXISTS idx_resources_site_id ON resources("siteId");
CREATE INDEX IF NOT EXISTS idx_resources_org_id ON resources("orgId");
CREATE INDEX IF NOT EXISTS idx_targets_resource_id ON targets("resourceId");
CREATE INDEX IF NOT EXISTS idx_user_email ON "user"(email);
CREATE INDEX IF NOT EXISTS idx_session_user_id ON session("userId");
CREATE INDEX IF NOT EXISTS idx_newt_site_id ON newt("siteId");
CREATE INDEX IF NOT EXISTS idx_user_orgs_user_id ON "userOrgs"("userId");
CREATE INDEX IF NOT EXISTS idx_user_orgs_org_id ON "userOrgs"("orgId");
EOF

}

# Start by delete all the tables that are there

#PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<EOF
#DROP TABLE public."actions" CASCADE;
#DROP TABLE public."apiKeyActions" CASCADE;
#DROP TABLE public."apiKeyOrg" CASCADE;
#DROP TABLE public."apiKeys" CASCADE;
#DROP TABLE public."clientSession" CASCADE;
#DROP TABLE public."clientSites" CASCADE;
#DROP TABLE public."clients" CASCADE;
#DROP TABLE public."domains" CASCADE;
#DROP TABLE public."emailVerificationCodes" CASCADE;
#DROP TABLE public."exitNodes" CASCADE;
#DROP TABLE public."hostMeta" CASCADE;
#DROP TABLE public."idp" CASCADE;
#DROP TABLE public."idpOidcConfig" CASCADE;
#DROP TABLE public."idpOrg" CASCADE;
#DROP TABLE public."licenseKey" CASCADE;
#DROP TABLE public."limits" CASCADE;
#DROP TABLE public."newt" CASCADE;
#DROP TABLE public."newtSession" CASCADE;
#DROP TABLE public."olms" CASCADE;
#DROP TABLE public."orgDomains" CASCADE;
#DROP TABLE public."orgs" CASCADE;
#DROP TABLE public."passwordResetTokens" CASCADE;
#DROP TABLE public."resourceAccessToken" CASCADE;
#DROP TABLE public."resourceOtp" CASCADE;
#DROP TABLE public."resourcePassword" CASCADE;
#DROP TABLE public."resourcePincode" CASCADE;
#DROP TABLE public."resourceRules" CASCADE;
#DROP TABLE public."resourceSessions" CASCADE;
#DROP TABLE public."resourceWhitelist" CASCADE;
#DROP TABLE public."resources" CASCADE;
#DROP TABLE public."roleActions" CASCADE;
#DROP TABLE public."roleClients" CASCADE;
#DROP TABLE public."roleResources" CASCADE;
#DROP TABLE public."roleSites" CASCADE;
#DROP TABLE public."roles" CASCADE;
#DROP TABLE public."session" CASCADE;
#DROP TABLE public."sites" CASCADE;
#DROP TABLE public."supporterKey" CASCADE;
#DROP TABLE public."targets" CASCADE;
#DROP TABLE public."twoFactorBackupCodes" CASCADE;
#DROP TABLE public."user" CASCADE;
#DROP TABLE public."userActions" CASCADE;
#DROP TABLE public."userClients" CASCADE;
#DROP TABLE public."userInvites" CASCADE;
#DROP TABLE public."userOrgs" CASCADE;
#DROP TABLE public."userResources" CASCADE;
#DROP TABLE public."userSites" CASCADE;
#DROP TABLE public."webauthnChallenge" CASCADE;
#DROP TABLE public."webauthnCredentials" CASCADE;
#EOF

# Create PostgreSQL structure
create_postgres_structure "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DB"

TABLES=(
    "domains" "orgs" "orgDomains" "exitNodes" "sites" "resources" "targets"
    "idp" "user" "newt" "twoFactorBackupCodes" "session" "newtSession"
    "actions" "roles" "userOrgs" "emailVerificationCodes" "passwordResetTokens"
    "roleActions" "userActions" "roleSites" "userSites" "roleResources"
    "userResources" "limits" "userInvites" "resourcePincode" "resourcePassword"
    "resourceAccessToken" "resourceWhitelist" "resourceSessions" "resourceOtp"
    "versionMigrations" "resourceRules" "supporterKey" "idpOidcConfig"
    "licenseKey" "hostMeta" "apiKeys" "apiKeyActions" "apiKeyOrg" "idpOrg"
    "clientSession" "clientSites" "clients" "olms" "roleClients" "userClients"
    "webauthnChallenge" "webauthnCredentials"
)

echo "Importing CSV data into PostgreSQL database: $PG_DB"

for table in "${TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/$table.csv"
    if [[ -f "$CSV_FILE" && $(wc -l < "$CSV_FILE") -gt 1 ]]; then
        echo "Importing $table from $CSV_FILE"
        PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "TRUNCATE TABLE \"$table\" RESTART IDENTITY CASCADE;"
        
        if [[ "$table" == "userOrgs" ]]; then
            # Special handling for userOrgs - get the actual user ID and update CSV on the fly
            echo "Special handling for userOrgs table - updating userId with actual system user ID"
            ACTUAL_USER_ID=$(PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -c "SELECT id FROM \"user\" LIMIT 1;" | xargs)
            
            # Create a temporary CSV with the correct userId
            TEMP_CSV="/tmp/userOrgs_temp.csv"
            head -n 1 "$CSV_FILE" > "$TEMP_CSV"  # Copy header
            tail -n +2 "$CSV_FILE" | sed "s/^[^,]*/$ACTUAL_USER_ID/" >> "$TEMP_CSV"  # Replace first column (userId) with actual ID
            
            PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "\COPY \"$table\" FROM '$TEMP_CSV' WITH CSV HEADER;"
            rm "$TEMP_CSV"  # Clean up temp file
        else
            # Normal import for other tables
            PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "\COPY \"$table\" FROM '$CSV_FILE' WITH CSV HEADER;"
        fi
    else
        echo "Skipped $table (file missing or empty)"
    fi
done

echo "Updating userOrg mapping."

# Add this line to your script after the COPY commands:
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "UPDATE \"userOrgs\" SET \"userId\" = (SELECT id FROM \"user\" LIMIT 1);"

#Reset Sequence After Import
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('resources', 'resourceId'), COALESCE((SELECT MAX(\"resourceId\") FROM resources), 1), true);"
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('targets', 'targetId'), COALESCE((SELECT MAX(\"targetId\") FROM targets), 1), true);"
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('sites', 'siteId'), COALESCE((SELECT MAX(\"siteId\") FROM sites), 1), true);"
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT setval(pg_get_serial_sequence('roles', 'roleId'), COALESCE((SELECT MAX(\"roleId\") FROM roles), 1), true);"

echo "Import complete."