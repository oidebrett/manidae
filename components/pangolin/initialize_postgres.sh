#!/bin/bash
# Updated initialize_postgres.sh
# - Matches SQLite behavior for missing values and booleans (NULL conversion, t/f -> boolean)
# - Auto-generates resourceGuid when blank (uuid_generate_v4())
# - Uses staging temp tables (text columns) to accept raw CSV values, then inserts into typed tables with safe casts
# - Keeps component-based filtering for resources/targets/roleResources
# - Does NOT reshape CSV columns (user chose option B): CSV header must match DB column names
set -euo pipefail

# Load environment variables from .env if present
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Determine psql location or install client
if [[ -x /usr/bin/psql ]]; then
  PSQL="/usr/bin/psql"
else
  echo "psql not found, installing postgresql-client..."
  apt-get update -qq && apt-get install -y postgresql-client -qq
  PSQL="/usr/bin/psql"
  if [[ ! -x $PSQL ]]; then
    echo "Error: Failed to install psql. Please install postgresql-client manually."
    exit 1
  fi
fi

PG_CONTAINER_NAME=${POSTGRES_HOST:-pangolin-postgres}
PG_IP=$(docker network inspect manidae 2>/dev/null | \
    awk "/\"Name\": \"$PG_CONTAINER_NAME\"/,/IPv4Address/" | \
    grep '"IPv4Address"' | \
    sed -E 's/.*"IPv4Address": "([^/]+)\/.*",/\1/' || true)

if [ -z "$PG_IP" ]; then
    echo "Error: Could not find IP address for container '$PG_CONTAINER_NAME'"
    exit 1
fi

echo "PostgreSQL container IP: $PG_IP"

EXPORT_DIR="${1:-./postgres_export}"
PG_HOST="$PG_IP"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_USER="${POSTGRES_USER:-postgres}"
PG_PASS="${POSTGRES_PASSWORD:-postgres}"
PG_DB="${POSTGRES_DB:-postgres}"

echo "Using PG_HOST=$PG_HOST PG_PORT=$PG_PORT PG_USER=$PG_USER PG_DB=$PG_DB"
echo "CSV export dir: $EXPORT_DIR"

# --- SQL to create the schema (adds proxyProtocol and proxyProtocolVersion fields) ---
create_postgres_structure() {
  PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d postgres -c "CREATE DATABASE $PG_DB;" 2>/dev/null || true

  PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" <<'EOF'
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
    subnet TEXT,
    settings TEXT
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
    "bytesIn" DOUBLE PRECISION DEFAULT 0,
    "bytesOut" DOUBLE PRECISION DEFAULT 0,
    "lastBandwidthUpdate" TEXT,
    type TEXT NOT NULL,
    online BOOLEAN NOT NULL DEFAULT FALSE,
    "address" TEXT,
    "endpoint" TEXT,
    "publicKey" TEXT,
    "lastHolePunch" BIGINT,
    "listenPort" INTEGER,
    "dockerSocketEnabled" BOOLEAN NOT NULL DEFAULT TRUE,
    "remoteSubnets" TEXT
);

-- Resources table (adds proxyProtocol and proxyProtocolVersion)
CREATE TABLE IF NOT EXISTS resources (
    "resourceId" SERIAL PRIMARY KEY,
    "resourceGuid" TEXT NOT NULL DEFAULT 'PLACEHOLDER',
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "niceId" TEXT NOT NULL,
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
    "setHostHeader" TEXT,
    "enableProxy" BOOLEAN DEFAULT TRUE,
    "skipToIdpId" INTEGER REFERENCES idp("idpId") ON DELETE CASCADE,
    headers TEXT,
    proxyProtocol TEXT,
    proxyProtocolVersion TEXT
);

-- Site Resources table
CREATE TABLE IF NOT EXISTS "siteResources" (
    "siteResourceId" SERIAL PRIMARY KEY,
    "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "niceId" TEXT NOT NULL,
    name TEXT NOT NULL,
    protocol TEXT NOT NULL,
    "proxyPort" INTEGER NOT NULL,
    "destinationPort" INTEGER NOT NULL,
    "destinationIp" TEXT NOT NULL,
    enabled BOOLEAN DEFAULT TRUE NOT NULL
);

-- Targets table
CREATE TABLE IF NOT EXISTS targets (
    "targetId" SERIAL PRIMARY KEY,
    "resourceId" INTEGER NOT NULL REFERENCES resources("resourceId") ON DELETE CASCADE,
    "siteId" INTEGER NOT NULL REFERENCES sites("siteId") ON DELETE CASCADE,
    ip TEXT NOT NULL,
    method TEXT,
    port INTEGER NOT NULL,
    "internalPort" INTEGER,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    path TEXT,
    "pathMatchType" TEXT,
    "rewritePath" TEXT,
    "rewritePathType" TEXT,
    priority INTEGER
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
    "termsAcceptedTimestamp" TEXT,
    "termsVersion" TEXT,
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

-- Setup tokens table
CREATE TABLE IF NOT EXISTS "setupTokens" (
    "tokenId" TEXT PRIMARY KEY NOT NULL,
    token TEXT NOT NULL,
    used BOOLEAN DEFAULT FALSE NOT NULL,
    "dateCreated" TEXT NOT NULL,
    "dateUsed" TEXT
);

-- User organizations table
CREATE TABLE IF NOT EXISTS "userOrgs" (
    "userId" TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    "orgId" TEXT NOT NULL REFERENCES orgs("orgId") ON DELETE CASCADE,
    "roleId" INTEGER NOT NULL,
    "isOwner" BOOLEAN NOT NULL DEFAULT FALSE,
    "autoProvisioned" BOOLEAN DEFAULT FALSE
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

-- Indexes
CREATE INDEX IF NOT EXISTS idx_sites_org_id ON sites("orgId");
CREATE INDEX IF NOT EXISTS idx_resources_org_id ON resources("orgId");
CREATE INDEX IF NOT EXISTS idx_targets_resource_id ON targets("resourceId");
CREATE INDEX IF NOT EXISTS idx_targets_site_id ON targets("siteId");
CREATE INDEX IF NOT EXISTS idx_site_resources_site_id ON "siteResources"("siteId");
CREATE INDEX IF NOT EXISTS idx_site_resources_org_id ON "siteResources"("orgId");
CREATE INDEX IF NOT EXISTS idx_user_email ON "user"(email);
CREATE INDEX IF NOT EXISTS idx_session_user_id ON session("userId");
CREATE INDEX IF NOT EXISTS idx_newt_site_id ON newt("siteId");
CREATE INDEX IF NOT EXISTS idx_user_orgs_user_id ON "userOrgs"("userId");
CREATE INDEX IF NOT EXISTS idx_user_orgs_org_id ON "userOrgs"("orgId");
EOF
}

# Create schema
create_postgres_structure

# Helper: check if a component exists
is_pangolin_plus() {
    local components_list="${COMPONENTS_CSV:-${COMPONENTS:-}}"
    case "$components_list" in
        *"pangolin+"*) return 0 ;;
        *) return 1 ;;
    esac
}
has_component() {
    local component="$1"
    local components_list="${COMPONENTS_CSV:-${COMPONENTS:-}}"
    case "$components_list" in
        *"$component"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Which resource IDs to include (same logic as sqlite script)
get_included_resource_ids() {
    local resource_ids="1"
    if has_component "traefik-log-dashboard"; then
        resource_ids="$resource_ids,2,5"
    fi
    if has_component "nlweb"; then
        resource_ids="$resource_ids,4,7"
    fi
    if has_component "agentgateway" || has_component "openai-chatkit"; then
        resource_ids="$resource_ids,4"
    fi
    if has_component "mcpauth"; then
        resource_ids="$resource_ids,6"
    fi
    echo "$resource_ids"
}

filter_csv_for_deployment() {
    local input_csv="$1"
    local output_csv="$2"
    local table_name="$3"

    if [[ ! -f "$input_csv" ]]; then
        echo "Input CSV file not found: $input_csv"
        return 1
    fi

    local included_ids
    included_ids="$(get_included_resource_ids)"
    echo "Including resources based on components: $included_ids"
    local id_pattern
    id_pattern=$(echo "$included_ids" | sed 's/,/|/g')

    case "$table_name" in
        "resources")
            head -n 1 "$input_csv" > "$output_csv"
            grep -E "^($id_pattern)," "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        "targets")
            head -n 1 "$input_csv" > "$output_csv"
            grep -E "^[0-9]+,($id_pattern)," "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        "roleResources")
            head -n 1 "$input_csv" > "$output_csv"
            grep -E "^[0-9]+,($id_pattern)$" "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        *)
            cp "$input_csv" "$output_csv"
            ;;
    esac
}

# Build a function to import any CSV via staging-as-text then cast into typed table
import_csv_with_casts() {
    local table="$1"
    local csv_file="$2"

    if [[ ! -f "$csv_file" ]]; then
        echo "Skipped $table (file missing: $csv_file)"
        return 0
    fi

    if [[ $(wc -l < "$csv_file") -le 1 ]]; then
        echo "Skipped $table (file empty or header only)"
        return 0
    fi

    echo "==> Importing $table from $csv_file"

    # Read header and build temp table DDL
    HEADER_LINE=$(head -n 1 "$csv_file")
    # Split header into an array of column names while preserving quoted names
    # Convert header into newline-separated, then iterate
    IFS=',' read -r -a HEADER_ARR <<< "$HEADER_LINE"

    # Build CREATE TEMP TABLE statement with each header column typed as text
    TEMP_TABLE="temp_import_${table}"
    CREATE_SQL="CREATE TEMP TABLE \"${TEMP_TABLE}\" ("
    first=true
    for rawcol in "${HEADER_ARR[@]}"; do
        # Trim whitespace and any surrounding quotes
        col=$(echo "$rawcol" | sed -e 's/^ *//;s/ *$//' -e 's/^"//;s/"$//')
        # Escape double quotes in column name
        col_esc=$(printf '%s' "$col" | sed 's/"/""/g')
        if $first; then
            CREATE_SQL="${CREATE_SQL}\"${col_esc}\" text"
            first=false
        else
            CREATE_SQL="${CREATE_SQL}, \"${col_esc}\" text"
        fi
    done
    CREATE_SQL="${CREATE_SQL});"

    # Create temp table
    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 -q -c "$CREATE_SQL"

    # Copy CSV into temp table (text columns tolerate empty strings)
    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "\COPY \"${TEMP_TABLE}\" FROM '$csv_file' WITH CSV HEADER;"

    # Now we need to build INSERT ... SELECT ... where we cast based on target table column types.
    # Get target table's columns and types from information_schema
    # Note: we query by table_name as-is (case sensitive), so this requires the table name to match exactly as created.
    mapfile -t COLUMN_INFO < <(PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -A -c \
        "SELECT column_name || '|' || data_type || '|' || ordinal_position
         FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = '$table'
         ORDER BY ordinal_position;")

    if [[ ${#COLUMN_INFO[@]} -eq 0 ]]; then
        # If we didn't find typed columns (maybe table doesn't exist or different case), do a fallback: direct copy
        echo "  Warning: Could not find information_schema entry for table '$table'. Falling back to direct COPY (may fail on empty numeric/boolean fields)."
        PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "\COPY \"$table\" FROM '$csv_file' WITH CSV HEADER;"
        # Drop temp table
        PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "DROP TABLE IF EXISTS \"${TEMP_TABLE}\";"
        return 0
    fi

    # Build lists to use in INSERT
    TARGET_COLS=()
    SELECT_EXPR=()

    # Build a map from header names -> typed expressions
    # For each target column (positionally), if header present map header->type
    # We'll assume CSV header columns and table columns are in the same order (user choice B)
    # So we map by ordinal position.
    for idx in "${!COLUMN_INFO[@]}"; do
        row="${COLUMN_INFO[$idx]}"
        colname=$(cut -d'|' -f1 <<< "$row")
        dtype=$(cut -d'|' -f2 <<< "$row")
        pos=$(cut -d'|' -f3 <<< "$row")
        # Header column at same ordinal (pos) must exist in HEADER_ARR
        # Note pos is 1-based index; bash array is 0-based
        header_index=$((pos - 1))
        if (( header_index < ${#HEADER_ARR[@]} )); then
            raw_header="${HEADER_ARR[$header_index]}"
            hdr=$(echo "$raw_header" | sed -e 's/^ *//;s/ *$//' -e 's/^"//;s/"$//')
        else
            echo "  Warning: CSV header has fewer columns than target table '$table'. Column $colname will be inserted as NULL."
            hdr=""
        fi

        # Build select expression depending on dtype
        expr=""
        # The temp table column reference must be quoted the same as hdr
        if [[ -z "$hdr" ]]; then
            expr="NULL"
        else
            # escape double quotes in hdr for use in SQL
            hdr_esc=$(printf '%s' "$hdr" | sed 's/"/""/g')
            case "$dtype" in
                integer|smallint|bigint)
                    # cast to integer/bigint; use NULLIF to convert empty string to NULL
                    if [[ "$dtype" == "bigint" ]]; then
                        expr="NULLIF(\"$hdr_esc\", '')::bigint"
                    else
                        expr="NULLIF(\"$hdr_esc\", '')::integer"
                    fi
                    ;;
                numeric|real|double\ precision|decimal)
                    expr="NULLIF(\"$hdr_esc\", '')::double precision"
                    ;;
                boolean)
                    # Normalize t/f/true/false/1/0 -> boolean, otherwise NULL
                    expr="(CASE WHEN lower(NULLIF(\"$hdr_esc\", '')) IN ('t','true','1') THEN true WHEN lower(NULLIF(\"$hdr_esc\", '')) IN ('f','false','0') THEN false ELSE NULL END)"
                    ;;
                text|character varying|character|varchar)
                    expr="NULLIF(\"$hdr_esc\", '')"
                    ;;
                bigint)
                    expr="NULLIF(\"$hdr_esc\", '')::bigint"
                    ;;
                timestamp without time zone|timestamp with time zone)
                    expr="NULLIF(\"$hdr_esc\", '')::text"
                    ;;
                json|jsonb)
                    expr="NULLIF(\"$hdr_esc\", '')::jsonb"
                    ;;
                *)
                    # Default fallback to text (NULL for empty)
                    expr="NULLIF(\"$hdr_esc\", '')"
                    ;;
            esac
        fi

        TARGET_COLS+=("\"$colname\"")
        SELECT_EXPR+=("$expr")
    done

    # If the target is resources and resourceGuid exists, ensure empty resourceGuid becomes a generated uuid
    # Modify SELECT_EXPR where target column is resourceGuid
    for i in "${!TARGET_COLS[@]}"; do
        col=${TARGET_COLS[$i]}
        # strip surrounding quotes
        col_unq=$(echo "$col" | sed 's/^"//;s/"$//')
        if [[ "$col_unq" == "resourceGuid" ]]; then
            # replace SELECT_EXPR[i] with generation logic: CASE WHEN NULLIF(...) IS NULL OR '' THEN lower(uuid_generate_v4()::text) ELSE resourceGuid END
            # But earlier expr is NULLIF("resourceGuid",'')
            SELECT_EXPR[$i]="(CASE WHEN NULLIF(\"resourceGuid\",'') IS NULL THEN lower(uuid_generate_v4()::text) ELSE NULLIF(\"resourceGuid\",'') END)"
        fi
    done

    # Build final INSERT SQL
    TARGET_COLS_CSV=$(IFS=,; echo "${TARGET_COLS[*]}")
    SELECT_EXPR_CSV=$(IFS=,; echo "${SELECT_EXPR[*]}")

    INSERT_SQL="INSERT INTO \"$table\" ($TARGET_COLS_CSV) SELECT $SELECT_EXPR_CSV FROM \"$TEMP_TABLE\";"

    # Execute insert inside a transaction (to fail fast)
    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 -q -c "BEGIN; $INSERT_SQL; COMMIT;" || {
        echo "  Error importing into $table (insert failed). Dropping temp table and aborting."
        PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "DROP TABLE IF EXISTS \"${TEMP_TABLE}\";"
        exit 1
    }

    # Drop temp table
    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "DROP TABLE IF EXISTS \"${TEMP_TABLE}\";"
    echo "  Imported $table successfully."
}

# Table list (same as your script)
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
    "webauthnChallenge" "webauthnCredentials" "setupTokens" "siteResources"
)

echo "Importing CSV data into PostgreSQL database: $PG_DB (this may take a while)..."

for table in "${TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/$table.csv"

    if [[ "$table" == "userOrgs" ]]; then
        # Special handling: replace userId column with actual single user id
        if [[ -f "$CSV_FILE" && $(wc -l < "$CSV_FILE") -gt 1 ]]; then
            echo "Special handling for userOrgs - adjusting userId to actual system user id"
            ACTUAL_USER_ID=$(PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -A -c "SELECT id FROM \"user\" LIMIT 1;" | xargs || true)
            if [[ -z "$ACTUAL_USER_ID" ]]; then
                echo "  No user found in database; skipping userOrgs import. Create a user first."
                continue
            fi
            # Build temp CSV replacing first column value with actual user id (keep header)
            TMP_USERORGS="/tmp/userOrgs_temp.csv"
            head -n 1 "$CSV_FILE" > "$TMP_USERORGS"
            tail -n +2 "$CSV_FILE" | sed "s/^[^,]*/$ACTUAL_USER_ID/" >> "$TMP_USERORGS"
            # Truncate and import via staged method
            PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "TRUNCATE TABLE \"$table\";"
            import_csv_with_casts "$table" "$TMP_USERORGS"
            rm -f "$TMP_USERORGS"
        else
            echo "Skipped $table (missing or empty)"
        fi
    else
        if [[ -f "$CSV_FILE" && $(wc -l < "$CSV_FILE") -gt 1 ]]; then
            # For filterable tables, create filtered CSV first
            if [[ "$table" == "resources" || "$table" == "targets" || "$table" == "roleResources" ]]; then
                FILTERED_CSV="/tmp/${table}_filtered.csv"
                if filter_csv_for_deployment "$CSV_FILE" "$FILTERED_CSV" "$table"; then
                    PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "TRUNCATE TABLE \"$table\" RESTART IDENTITY CASCADE;"
                    import_csv_with_casts "$table" "$FILTERED_CSV"
                    rm -f "$FILTERED_CSV"
                else
                    echo "Failed to filter $table, skipping import"
                fi
            else
                PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "TRUNCATE TABLE \"$table\" RESTART IDENTITY CASCADE;"
                import_csv_with_casts "$table" "$CSV_FILE"
            fi
        else
            echo "Skipped $table (file missing or empty)"
        fi
    fi
done

echo "Updating userOrg mapping (ensure userId is consistent)..."
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "UPDATE \"userOrgs\" SET \"userId\" = (SELECT id FROM \"user\" LIMIT 1) WHERE (SELECT COUNT(*) FROM \"user\") > 0;"

echo "Resetting sequences (resources, targets, sites, roles, siteResources)..."
PGPASSWORD="$PG_PASS" $PSQL -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 -q <<'SQL'
SELECT setval(pg_get_serial_sequence('resources', 'resourceId'), COALESCE((SELECT MAX("resourceId") FROM resources), 1), true);
SELECT setval(pg_get_serial_sequence('targets', 'targetId'), COALESCE((SELECT MAX("targetId") FROM targets), 1), true);
SELECT setval(pg_get_serial_sequence('sites', 'siteId'), COALESCE((SELECT MAX("siteId") FROM sites), 1), true);
SELECT setval(pg_get_serial_sequence('roles', 'roleId'), COALESCE((SELECT MAX("roleId") FROM roles), 1), true);
SELECT setval(pg_get_serial_sequence('siteResources','siteResourceId'), COALESCE((SELECT MAX("siteResourceId") FROM "siteResources"), 1), true);
SQL

echo "Import complete."
