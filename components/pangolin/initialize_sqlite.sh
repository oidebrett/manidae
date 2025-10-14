#!/bin/bash

# Import CSV data into SQLite
# This script recreates the functionality of initialize_postgres.sh for SQLite
# It imports data from CSV files in the postgres_export directory into the SQLite database
#
# Usage:
#   1. First create an admin user:
#      docker exec pangolin pangctl set-admin-credentials --email "admin@yourdomain.com" --password "YourPassword"
#   2. Then run this script:
#      ./initialize_sqlite.sh [export_directory]
#
# Parameters:
#   export_directory: Optional path to directory containing CSV files (default: ./postgres_export)
#
# The script will:
# 1. Check for SQLite installation and install if needed
# 2. Verify the SQLite database exists and that a user exists
# 3. Import CSV data from available files, handling:
#    - Boolean conversion (PostgreSQL t/f to SQLite 1/0)
#    - Column mismatches between CSV and SQLite schema
#    - Special handling for userOrgs table to associate resources with the existing user
# 4. Display import summary
#
set -e

# Load environment variables from .env file
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

DB_PATH="./config/db/db.sqlite"

# --- Ensure sqlite3 is installed ---
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "[INFO] sqlite3 not found, attempting installation..."

  if [ -f /etc/alpine-release ]; then
    # Alpine Linux (often in containers)
    apk add --no-cache sqlite
  elif [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    apt-get update && apt-get install -y sqlite3
  elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL/Fedora
    yum install -y sqlite
  elif command -v brew >/dev/null 2>&1; then
    # macOS with Homebrew
    brew install sqlite
  else
    echo "[ERROR] Could not detect package manager to install sqlite3."
    echo "Please install sqlite3 manually."
    exit 1
  fi
fi

# --- Check DB file exists ---
if [ ! -f "$DB_PATH" ]; then
  echo "[ERROR] Database file not found at $DB_PATH"
  exit 1
fi

EXPORT_DIR="${1:-./postgres_export}"

echo "SQLite database path: $DB_PATH"

# Function to detect if pangolin+ is being used
is_pangolin_plus() {
    # Check COMPONENTS_CSV first, then fall back to COMPONENTS
    local components_list="${COMPONENTS_CSV:-${COMPONENTS:-}}"
    case "$components_list" in
        *"pangolin+"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to detect if AI components (nlweb/komodo/agentgateway) are being used
is_pangolin_plus_ai() {
    # Check COMPONENTS_CSV first, then fall back to COMPONENTS
    local components_list="${COMPONENTS_CSV:-${COMPONENTS:-}}"
    case "$components_list" in
        *"nlweb"*|*"komodo"*|*"agentgateway"*) return 0 ;;
    esac

    # If neither COMPONENTS_CSV nor COMPONENTS is set, try to detect from CSV files
    if [ -z "$components_list" ]; then
        # Check if resources.csv contains AI-specific resources
        if [ -f "${EXPORT_DIR:-./postgres_export}/resources.csv" ]; then
            # Look for chatkit-embed (AgentGateway), nlweb, or komodo resources
            if grep -q "chatkit-embed\|nlweb\|komodo-core" "${EXPORT_DIR:-./postgres_export}/resources.csv"; then
                return 0
            fi
        fi
    fi

    return 1
}

# Function to check if a specific component is included
has_component() {
    local component="$1"
    # Check COMPONENTS_CSV first, then fall back to COMPONENTS
    local components_list="${COMPONENTS_CSV:-${COMPONENTS:-}}"
    case "$components_list" in
        *"$component"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to get resource IDs that should be included based on components
get_included_resource_ids() {
    local resource_ids=""

    # Always include middleware-manager (1) for pangolin deployments
    resource_ids="1"

    # Include traefik-dashboard (2) and logs-viewer (5) if traefik-log-dashboard component is present
    if has_component "traefik-log-dashboard"; then
        resource_ids="$resource_ids,2,5"
    fi

    # Include nlweb-app (4) and nlweb-crawler (7) if nlweb component is present
    if has_component "nlweb"; then
        resource_ids="$resource_ids,4,7"
    fi

    # Include idp (6) if mcpauth component is present
    if has_component "mcpauth"; then
        resource_ids="$resource_ids,6"
    fi

    # Note: komodo-core (3) is intentionally excluded from all deployments

    echo "$resource_ids"
}

# Detect and display deployment type
echo "Detecting deployment type..."
echo "COMPONENTS_CSV: ${COMPONENTS_CSV:-not set}"
echo "COMPONENTS: ${COMPONENTS:-not set}"
echo "Using components: ${COMPONENTS_CSV:-${COMPONENTS:-none}}"

if is_pangolin_plus_ai; then
    echo "🤖 Deployment type: Pangolin+AI (includes all resources)"
elif is_pangolin_plus; then
    echo "🛡️ Deployment type: Pangolin+ (core resources only)"
else
    echo "📦 Deployment type: Standard Pangolin (all resources)"
fi

# Function to create SQLite database structure (if needed)
create_sqlite_structure() {
    echo "Checking SQLite schema..."

    # Check if tables exist - if they do, we assume schema is already created
    TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '__drizzle_%';")

    if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "Database schema already exists with $TABLE_COUNT tables."
        return 0
    fi

    echo "Creating SQLite schema..."
    # Note: In a real scenario, you would need to create the schema here
    # For now, we assume the schema already exists from the application
}



# Function to filter CSV data based on deployment type and components
filter_csv_for_deployment() {
    local input_csv="$1"
    local output_csv="$2"
    local table_name="$3"

    if [[ ! -f "$input_csv" ]]; then
        echo "Input CSV file not found: $input_csv"
        return 1
    fi

    # Get the list of resource IDs that should be included based on components
    local included_ids=$(get_included_resource_ids)
    echo "Including resources based on components: $included_ids"

    # Convert comma-separated list to regex pattern
    local id_pattern=$(echo "$included_ids" | sed 's/,/|/g')

    case "$table_name" in
        "resources")
            # Include only resources that match the component selection
            head -n 1 "$input_csv" > "$output_csv"  # Copy header
            grep -E "^($id_pattern)," "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        "targets")
            # Include only targets that link to included resources
            head -n 1 "$input_csv" > "$output_csv"  # Copy header
            grep -E "^[0-9]+,($id_pattern)," "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        "roleResources")
            # Include only roleResources that link to included resources
            head -n 1 "$input_csv" > "$output_csv"  # Copy header
            grep -E "^[0-9]+,($id_pattern)$" "$input_csv" >> "$output_csv" 2>/dev/null || true
            ;;
        *)
            # For other tables, copy as-is
            cp "$input_csv" "$output_csv"
            ;;
    esac
}

# Function to import CSV into SQLite table
import_csv_to_sqlite() {
    local table_name="$1"
    local csv_file="$2"

    if [[ ! -f "$csv_file" ]]; then
        echo "Skipped $table_name (file missing: $csv_file)"
        return
    fi

    if [[ $(wc -l < "$csv_file") -le 1 ]]; then
        echo "Skipped $table_name (file empty or header only)"
        return
    fi

    echo "Importing $table_name from $csv_file"

    # Clear existing data
    sqlite3 "$DB_PATH" "DELETE FROM \"$table_name\";"

    # Get CSV headers and table columns
    CSV_HEADERS=$(head -n 1 "$csv_file")

    # Special handling for tables with column mismatches or data type issues
    if [[ "$table_name" == "sites" ]]; then
        # sites table has an extra remoteSubnets column in SQLite
        import_sites_csv "$csv_file"
    elif [[ "$table_name" == "resources" ]]; then
        # resources table has an extra enableProxy column in SQLite
        import_resources_csv "$csv_file"
    elif [[ "$table_name" == "siteResources" ]]; then
        # resources table has an extra enableProxy column in SQLite
        import_site_resources_csv "$csv_file"
    elif [[ "$table_name" == "targets" ]]; then
        # targets table needs special handling for data types
        import_targets_csv "$csv_file"
    elif [[ "$table_name" == "roles" ]]; then
        # roles table needs special handling for boolean values
        import_roles_csv "$csv_file"
    else
        # Standard import for other tables - need to handle boolean conversion
        import_standard_csv "$csv_file" "$table_name"
    fi
}

# Function for standard CSV import with boolean conversion
import_standard_csv() {
    local csv_file="$1"
    local table_name="$2"

    # Create a temporary file with boolean values converted, skipping header
    TEMP_CSV="/tmp/${table_name}_temp.csv"

    # Convert PostgreSQL boolean values (t/f) to SQLite boolean values (1/0) and skip header
    tail -n +2 "$csv_file" | sed 's/,t,/,1,/g; s/,f,/,0,/g; s/,t$/,1/g; s/,f$/,0/g; s/^t,/1,/g; s/^f,/0,/g' > "$TEMP_CSV"

    # Import the converted CSV without headers
    sqlite3 "$DB_PATH" <<EOF
.mode csv
.import "$TEMP_CSV" "$table_name"
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Special function for sites table
import_sites_csv() {
    local csv_file="$1"

    # Create a temporary CSV file without header
    TEMP_CSV="/tmp/sites_temp.csv"
    tail -n +2 "$csv_file" > "$TEMP_CSV"

    # Create a temporary table to import CSV data
    sqlite3 "$DB_PATH" <<EOF
CREATE TEMP TABLE temp_sites (
    siteId TEXT,
    orgId TEXT,
    niceId TEXT,
    exitNode TEXT,
    name TEXT,
    pubKey TEXT,
    subnet TEXT,
    bytesIn TEXT,
    bytesOut TEXT,
    lastBandwidthUpdate TEXT,
    type TEXT,
    online TEXT,
    address TEXT,
    endpoint TEXT,
    publicKey TEXT,
    lastHolePunch TEXT,
    listenPort TEXT,
    dockerSocketEnabled TEXT
);

.mode csv
.import "$TEMP_CSV" temp_sites

INSERT INTO sites (
    siteId, orgId, niceId, exitNode, name, pubKey, subnet, bytesIn, bytesOut,
    lastBandwidthUpdate, type, online, address, endpoint, publicKey,
    lastHolePunch, listenPort, dockerSocketEnabled, remoteSubnets
)
SELECT
    CASE WHEN siteId = '' THEN NULL ELSE CAST(siteId AS INTEGER) END,
    orgId,
    CASE WHEN niceId = '' OR niceId IS NULL THEN 'site-' || siteId ELSE niceId END,
    CASE WHEN exitNode = '' THEN NULL ELSE CAST(exitNode AS INTEGER) END,
    name,
    CASE WHEN pubKey = '' THEN NULL ELSE pubKey END,
    CASE WHEN subnet = '' THEN NULL ELSE subnet END,
    CASE WHEN bytesIn = '' THEN 0 ELSE CAST(bytesIn AS INTEGER) END,
    CASE WHEN bytesOut = '' THEN 0 ELSE CAST(bytesOut AS INTEGER) END,
    CASE WHEN lastBandwidthUpdate = '' THEN NULL ELSE lastBandwidthUpdate END,
    type,
    CASE WHEN online = 't' THEN 1 WHEN online = 'f' THEN 0 ELSE CAST(online AS INTEGER) END,
    CASE WHEN address = '' THEN NULL ELSE address END,
    CASE WHEN endpoint = '' THEN NULL ELSE endpoint END,
    CASE WHEN publicKey = '' THEN NULL ELSE publicKey END,
    CASE WHEN lastHolePunch = '' THEN NULL ELSE CAST(lastHolePunch AS INTEGER) END,
    CASE WHEN listenPort = '' THEN NULL ELSE CAST(listenPort AS INTEGER) END,
    CASE WHEN dockerSocketEnabled = 't' THEN 1 WHEN dockerSocketEnabled = 'f' THEN 0 ELSE CAST(dockerSocketEnabled AS INTEGER) END,
    NULL as remoteSubnets
FROM temp_sites;

DROP TABLE temp_sites;
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Function to generate a unique niceId
generate_nice_id() {
    local used_ids="$1"
    local nice_id=""
    local loops=0

    # Simple adjective-animal generator (basic version)
    local adjectives=("happy" "clever" "brave" "swift" "bright" "calm" "bold" "wise" "kind" "cool")
    local animals=("cat" "dog" "fox" "owl" "bee" "elk" "ant" "bat" "cod" "eel")

    while true; do
        if [ $loops -gt 100 ]; then
            # Fallback to timestamp-based ID
            nice_id="resource-$(date +%s)-$RANDOM"
            break
        fi

        local adj_idx=$((RANDOM % ${#adjectives[@]}))
        local animal_idx=$((RANDOM % ${#animals[@]}))
        nice_id="${adjectives[$adj_idx]}-${animals[$animal_idx]}"

        # Check if this ID is already used
        if ! echo "$used_ids" | grep -q "^$nice_id$"; then
            break
        fi
        loops=$((loops + 1))
    done

    echo "$nice_id"
}

# Special function for resources table
import_resources_csv() {
    local csv_file="$1"

    # Create a temporary CSV file without header
    TEMP_CSV="/tmp/resources_temp.csv"
    tail -n +2 "$csv_file" > "$TEMP_CSV"

    # Create a temporary table to import CSV data
    sqlite3 "$DB_PATH" <<EOF
CREATE TEMP TABLE temp_resources (
    resourceId TEXT,
    orgId TEXT,
    niceId TEXT,
    name TEXT,
    subdomain TEXT,
    fullDomain TEXT,
    domainId TEXT,
    ssl TEXT,
    blockAccess TEXT,
    sso TEXT,
    http TEXT,
    protocol TEXT,
    proxyPort TEXT,
    emailWhitelistEnabled TEXT,
    applyRules TEXT,
    enabled TEXT,
    stickySession TEXT,
    tlsServerName TEXT,
    setHostHeader TEXT,
    enableProxy TEXT,
    skipToIdpId TEXT,
    headers TEXT
);

.mode csv
.import "$TEMP_CSV" temp_resources

INSERT INTO resources (
    resourceId, orgId, niceId, name, subdomain, fullDomain, domainId,
    ssl, blockAccess, sso, http, protocol, proxyPort, emailWhitelistEnabled,
    applyRules, enabled, stickySession, tlsServerName, setHostHeader, enableProxy, skipToIdpId, headers
)
SELECT
    CASE WHEN resourceId = '' THEN NULL ELSE CAST(resourceId AS INTEGER) END,
    orgId,
    CASE WHEN niceId = '' OR niceId IS NULL THEN 'resource-' || resourceId ELSE niceId END,
    name,
    CASE WHEN subdomain = '' THEN NULL ELSE subdomain END,
    CASE WHEN fullDomain = '' THEN NULL ELSE fullDomain END,
    CASE WHEN domainId = '' THEN NULL ELSE domainId END,
    CASE WHEN ssl = 't' THEN 1 WHEN ssl = 'f' THEN 0 ELSE CAST(ssl AS INTEGER) END,
    CASE WHEN blockAccess = 't' THEN 1 WHEN blockAccess = 'f' THEN 0 ELSE CAST(blockAccess AS INTEGER) END,
    CASE WHEN sso = 't' THEN 1 WHEN sso = 'f' THEN 0 ELSE CAST(sso AS INTEGER) END,
    CASE WHEN http = 't' THEN 1 WHEN http = 'f' THEN 0 ELSE CAST(http AS INTEGER) END,
    protocol,
    CASE WHEN proxyPort = '' THEN NULL ELSE CAST(proxyPort AS INTEGER) END,
    CASE WHEN emailWhitelistEnabled = 't' THEN 1 WHEN emailWhitelistEnabled = 'f' THEN 0 ELSE CAST(emailWhitelistEnabled AS INTEGER) END,
    CASE WHEN applyRules = 't' THEN 1 WHEN applyRules = 'f' THEN 0 ELSE CAST(applyRules AS INTEGER) END,
    CASE WHEN enabled = 't' THEN 1 WHEN enabled = 'f' THEN 0 ELSE CAST(enabled AS INTEGER) END,
    CASE WHEN stickySession = 't' THEN 1 WHEN stickySession = 'f' THEN 0 ELSE CAST(stickySession AS INTEGER) END,
    CASE WHEN tlsServerName = '' THEN NULL ELSE tlsServerName END,
    CASE WHEN setHostHeader = '' THEN NULL ELSE setHostHeader END,
    CASE WHEN enableProxy = 't' THEN 1 WHEN enableProxy = 'f' THEN 0 WHEN enableProxy = '' THEN 1 ELSE CAST(enableProxy AS INTEGER) END,
    CASE WHEN skipToIdpId = '' THEN NULL ELSE CAST(skipToIdpId AS INTEGER) END,
    CASE WHEN headers = '' THEN NULL ELSE headers END
FROM temp_resources;

DROP TABLE temp_resources;
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Special function for site resources table
import_site_resources_csv() {
    local csv_file="$1"

    # Create a temporary CSV file without header
    TEMP_CSV="/tmp/site_resources_temp.csv"
    tail -n +2 "$csv_file" > "$TEMP_CSV"

    # Create a temporary table to import CSV data
    sqlite3 "$DB_PATH" <<EOF
CREATE TEMP TABLE temp_site_resources (
    siteResourceId TEXT,
    siteId TEXT,
    orgId TEXT,
    niceId TEXT,
    name TEXT,
    protocol TEXT,
    proxyPort TEXT,
    destinationPort TEXT,
    destinationIp TEXT,
    enabled TEXT
);

.mode csv
.import "$TEMP_CSV" temp_site_resources

INSERT INTO siteResources (
    siteResourceId, siteId, orgId, niceId, name, protocol, proxyPort, destinationPort, destinationIp, enabled
)
SELECT
    CASE WHEN siteResourceId = '' THEN NULL ELSE CAST(siteResourceId AS INTEGER) END,
    CASE WHEN siteId = '' THEN NULL ELSE CAST(siteId AS INTEGER) END,
    orgId,
    CASE WHEN niceId = '' OR niceId IS NULL THEN 'site-resource-' || siteResourceId ELSE niceId END,
    name,
    protocol,
    CASE WHEN proxyPort = '' THEN NULL ELSE CAST(proxyPort AS INTEGER) END,
    CASE WHEN destinationPort = '' THEN NULL ELSE CAST(destinationPort AS INTEGER) END,
    destinationIp,
    CASE WHEN enabled = 't' THEN 1 WHEN enabled = 'f' THEN 0 ELSE CAST(enabled AS INTEGER) END
FROM temp_site_resources;

DROP TABLE temp_site_resources;
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Special function for targets table
import_targets_csv() {
    local csv_file="$1"

    # Create a temporary CSV file without header
    TEMP_CSV="/tmp/targets_temp.csv"
    tail -n +2 "$csv_file" > "$TEMP_CSV"

    # Get the first site ID to use as default for targets that don't have siteId
    FIRST_SITE_ID=$(sqlite3 "$DB_PATH" "SELECT siteId FROM sites LIMIT 1;")
    if [ -z "$FIRST_SITE_ID" ]; then
        FIRST_SITE_ID=1
    fi

    # Create a temporary table to import CSV data
    sqlite3 "$DB_PATH" <<EOF
CREATE TEMP TABLE temp_targets (
    targetId TEXT,
    resourceId TEXT,
    siteId TEXT,
    ip TEXT,
    method TEXT,
    port TEXT,
    internalPort TEXT,
    enabled TEXT,
    path TEXT,
    pathMatchType TEXT
);

.mode csv
.import "$TEMP_CSV" temp_targets

INSERT INTO targets (
    targetId, resourceId, siteId, ip, method, port, internalPort, enabled, path, pathMatchType
)
SELECT
    CASE WHEN targetId = '' THEN NULL ELSE CAST(targetId AS INTEGER) END,
    CASE WHEN resourceId = '' THEN NULL ELSE CAST(resourceId AS INTEGER) END,
    CASE WHEN siteId = '' OR siteId IS NULL THEN $FIRST_SITE_ID ELSE CAST(siteId AS INTEGER) END,
    ip,
    CASE WHEN method = '' THEN NULL ELSE method END,
    CASE WHEN port = '' THEN NULL ELSE CAST(port AS INTEGER) END,
    CASE WHEN internalPort = '' THEN NULL ELSE CAST(internalPort AS INTEGER) END,
    CASE WHEN enabled = 't' THEN 1 WHEN enabled = 'f' THEN 0 ELSE CAST(enabled AS INTEGER) END,
    CASE WHEN path = '' THEN NULL ELSE path END,
    CASE WHEN pathMatchType = '' THEN NULL ELSE pathMatchType END
FROM temp_targets;

DROP TABLE temp_targets;
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Special function for roles table
import_roles_csv() {
    local csv_file="$1"

    # Create a temporary CSV file without header
    TEMP_CSV="/tmp/roles_temp.csv"
    tail -n +2 "$csv_file" > "$TEMP_CSV"

    # Create a temporary table to import CSV data
    sqlite3 "$DB_PATH" <<EOF
CREATE TEMP TABLE temp_roles (
    roleId TEXT,
    orgId TEXT,
    isAdmin TEXT,
    name TEXT,
    description TEXT
);

.mode csv
.import "$TEMP_CSV" temp_roles

INSERT INTO roles (
    roleId, orgId, isAdmin, name, description
)
SELECT
    CASE WHEN roleId = '' THEN NULL ELSE CAST(roleId AS INTEGER) END,
    orgId,
    CASE WHEN isAdmin = 't' THEN 1 WHEN isAdmin = 'f' THEN 0 WHEN isAdmin = '' THEN NULL ELSE CAST(isAdmin AS INTEGER) END,
    name,
    CASE WHEN description = '' THEN NULL ELSE description END
FROM temp_roles;

DROP TABLE temp_roles;
EOF

    # Clean up temp file
    rm -f "$TEMP_CSV"
}

# Create SQLite structure (check if needed)
create_sqlite_structure

# List of tables to import (matching the PostgreSQL script)
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

echo "Importing CSV data into SQLite database: $DB_PATH"

# Import CSV data for each table
for table in "${TABLES[@]}"; do
    CSV_FILE="$EXPORT_DIR/$table.csv"

    if [[ "$table" == "userOrgs" ]]; then
        # Special handling for userOrgs - get the actual user ID and update CSV on the fly
        if [[ -f "$CSV_FILE" && $(wc -l < "$CSV_FILE") -gt 1 ]]; then
            echo "Special handling for userOrgs table - updating userId with actual system user ID"

            # Get actual user ID from database
            ACTUAL_USER_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM \"user\" LIMIT 1;")

            if [[ -n "$ACTUAL_USER_ID" ]]; then
                # Create a temporary CSV with the correct userId and boolean conversion
                TEMP_CSV="/tmp/userOrgs_temp.csv"
                tail -n +2 "$CSV_FILE" | sed "s/^[^,]*/$ACTUAL_USER_ID/; s/,t$/,1/; s/,f$/,0/" > "$TEMP_CSV"

                # Clear existing data and import
                sqlite3 "$DB_PATH" "DELETE FROM \"userOrgs\";"
                sqlite3 "$DB_PATH" <<EOF
.mode csv
.import "$TEMP_CSV" "userOrgs"
EOF
                rm -f "$TEMP_CSV"  # Clean up temp file
                echo "Updated userOrgs with user ID: $ACTUAL_USER_ID"
            else
                echo "Warning: No user found in database, skipping userOrgs import"
            fi
        else
            echo "Skipped $table (file missing or empty)"
        fi
    else
        # Check if this table needs filtering for deployment type
        if [[ "$table" == "resources" || "$table" == "targets" || "$table" == "roleResources" ]]; then
            # Use filtered CSV for deployment-specific tables
            FILTERED_CSV="/tmp/${table}_filtered.csv"
            if filter_csv_for_deployment "$CSV_FILE" "$FILTERED_CSV" "$table"; then
                import_csv_to_sqlite "$table" "$FILTERED_CSV"
                rm -f "$FILTERED_CSV"  # Clean up filtered file
            else
                echo "Failed to filter $table, skipping import"
            fi
        else
            # Normal import for other tables
            import_csv_to_sqlite "$table" "$CSV_FILE"
        fi
    fi
done

echo "Updating userOrg mapping if needed..."

# Update userOrgs to ensure consistency (similar to PostgreSQL script)
USER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM \"user\";")
if [[ "$USER_COUNT" -gt 0 ]]; then
    ACTUAL_USER_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM \"user\" LIMIT 1;")
    if [[ -n "$ACTUAL_USER_ID" ]]; then
        sqlite3 "$DB_PATH" "UPDATE \"userOrgs\" SET \"userId\" = '$ACTUAL_USER_ID';"
        echo "Updated userOrgs with user ID: $ACTUAL_USER_ID"
    fi
else
    echo "No users found in database. Please create a user first using:"
    echo "docker exec pangolin pangctl set-admin-credentials --email \"admin@mcpgateway.online\" --password \"Mcpgateway123q!\""
    echo "Then run this script again."
fi

echo "Import complete."

# Display summary of imported data
echo ""
echo "=== Import Summary ==="
ORGS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM orgs;")
SITES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sites;")
RESOURCES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM resources;")
TARGETS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM targets;")
ROLES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM roles;")
USER_ORGS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM userOrgs;")

echo "Organizations: $ORGS_COUNT"
echo "Sites: $SITES_COUNT"
echo "Resources: $RESOURCES_COUNT"
echo "Targets: $TARGETS_COUNT"
echo "Roles: $ROLES_COUNT"
echo "User-Org relationships: $USER_ORGS_COUNT"
echo ""
echo "SQLite database initialization complete!"
echo "Database location: $DB_PATH"
