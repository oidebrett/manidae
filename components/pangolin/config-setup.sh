# Pangolin core setup (always run)

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Core shared functions
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Directories
mkdir -p "$ROOT_HOST_DIR/config/traefik"
mkdir -p "$ROOT_HOST_DIR/config/traefik/rules"
mkdir -p "$ROOT_HOST_DIR/config/letsencrypt"
mkdir -p "$ROOT_HOST_DIR/public_html"
chmod 600 "$ROOT_HOST_DIR/config/letsencrypt"

# Secret
SECRET_KEY=$(generate_secret)

# config.yml (base)
cat > "$ROOT_HOST_DIR/config/config.yml" << EOF
app:
    dashboard_url: "https://${ADMIN_SUBDOMAIN}.${DOMAIN}"
    log_level: "info"
    save_logs: false

domains:
    domain1:
        base_domain: "${DOMAIN}"
        cert_resolver: "letsencrypt"

server:
    external_port: 3000
    internal_port: 3001
    next_port: 3002
    internal_hostname: "pangolin"
    session_cookie_name: "p_session_token"
    resource_access_token_param: "p_token"
    resource_access_token_headers:
        id: "P-Access-Token-Id"
        token: "P-Access-Token"
    resource_session_request_param: "p_session_request"
    secret: ${SECRET_KEY}
    cors:
        origins: ["https://${DOMAIN}"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH"]
        headers: ["X-CSRF-Token", "Content-Type"]
        credentials: false

traefik:
    cert_resolver: "letsencrypt"
    http_entrypoint: "web"
    https_entrypoint: "websecure"

gerbil:
    start_port: 51820
    base_endpoint: "${ADMIN_SUBDOMAIN}.${DOMAIN}"
    use_subdomain: false
    block_size: 24
    site_block_size: 30
    subnet_group: 100.89.137.0/20

rate_limits:
    global:
        window_minutes: 1
        max_requests: 500

flags:
    require_email_verification: false
    disable_signup_without_invite: true
    disable_user_create_org: false
    allow_raw_resources: true
    allow_base_domain_resources: true

postgres:
    connection_string: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/postgres

EOF

# Function to check if a specific component is included
has_component() {
    local component="$1"
    case "${COMPONENTS_CSV:-}" in
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

    # Include chatkit-embed (4) if agentgateway component is present
    if has_component "agentgateway"; then
        resource_ids="$resource_ids,4"
    fi

    # Include idp (6) if mcpauth component is present
    if has_component "mcpauth"; then
        resource_ids="$resource_ids,6"
    fi

    # Note: komodo-core (3) is intentionally excluded from all deployments

    echo "$resource_ids"
}

# Function to filter CSV data based on components
filter_csv_for_components() {
    local input_csv="$1"
    local output_csv="$2"
    local table_name="$3"

    if [ ! -f "$input_csv" ]; then
        echo "Input CSV file not found: $input_csv"
        return 1
    fi

    # Get the list of resource IDs that should be included based on components
    local included_ids=$(get_included_resource_ids)
    echo "🔍 Including resources based on components: $included_ids"

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

# Function to update domain in CSV files
update_domains_in_csv() {
    echo "🔄 Updating domain references in CSV files..."

    # Create postgres_export directory if it doesn't exist
    mkdir -p "$ROOT_HOST_DIR/postgres_export"

    # Copy postgres_export data from component to host setup directory
    if [ -d "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/pangolin/postgres_export" ]; then
        cp -r "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/pangolin/postgres_export"/* "$ROOT_HOST_DIR/postgres_export/"
        echo "✅ Copied postgres_export data from pangolin component"
    fi

    # Filter CSV files based on components if COMPONENTS_CSV is set
    if [ -n "${COMPONENTS_CSV:-}" ]; then
        echo "🔧 Filtering CSV files based on components: ${COMPONENTS_CSV}"

        # Filter each CSV file
        for table in resources targets roleResources; do
            if [ -f "$ROOT_HOST_DIR/postgres_export/$table.csv" ]; then
                # Create a backup
                cp "$ROOT_HOST_DIR/postgres_export/$table.csv" "$ROOT_HOST_DIR/postgres_export/$table.csv.backup"

                # Filter the CSV
                filter_csv_for_components "$ROOT_HOST_DIR/postgres_export/$table.csv.backup" "$ROOT_HOST_DIR/postgres_export/$table.csv" "$table"

                # Remove backup
                rm -f "$ROOT_HOST_DIR/postgres_export/$table.csv.backup"

                echo "✅ Filtered $table.csv based on components"
            fi
        done
    fi

    # Check if resources.csv exists
    if [ -f "$ROOT_HOST_DIR/postgres_export/resources.csv" ]; then
        # Replace yourdomain.com with the DOMAIN variable in resources.csv
        sed -i "s/yourdomain\.com/${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"

        # Update traefik subdomain if custom subdomain is provided (traefik is part of pangolin platform)
        if [ -n "${TRAEFIK_SUBDOMAIN:-}" ]; then
            sed -i "s/traefik\.${DOMAIN}/${TRAEFIK_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"
            echo "✅ Updated traefik subdomain to ${TRAEFIK_SUBDOMAIN}"
        fi

        echo "✅ Updated domain references in resources.csv"
    else
        echo "⚠️ resources.csv not found, skipping domain update"
    fi
}

echo "🐛 DEBUG: COMPONENTS='${COMPONENTS:-}'"
echo "🐛 DEBUG: COMPONENTS_CSV='${COMPONENTS_CSV:-}'"
echo "🐛 DEBUG: Checking if mcpauth is included..."
if has_component "mcpauth"; then
    echo "🐛 mcpauth IS PRESENT according to has_component()"
else
    echo "🐛 mcpauth is NOT present"
fi

# Function to process HTML template based on components
process_html_template() {
    echo "🌐 Processing HTML template based on components..."

    # Create public_html directory if it doesn't exist
    mkdir -p "$ROOT_HOST_DIR/public_html"

    # Copy the HTML template
    if [ -f "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/templates/html/index.html" ]; then
        cp "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/templates/html/index.html" "$ROOT_HOST_DIR/public_html/index.html"

        # Replace domain placeholders
        sed -i "s/yourdomain\.com/${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"

        # Process conditional sections based on components
        local temp_file="$ROOT_HOST_DIR/public_html/index.html.tmp"

        # Process NLWeb section
        if has_component "nlweb"; then
            echo "✅ Including NLWeb section in HTML"
            # Keep the NLWeb section - remove the conditional markers
            sed '/<!-- COMPONENT_CONDITIONAL_NLWEB_START -->/d; /<!-- COMPONENT_CONDITIONAL_NLWEB_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
        else
            echo "❌ Excluding NLWeb section from HTML"
            # Remove the entire NLWeb section
            sed '/<!-- COMPONENT_CONDITIONAL_NLWEB_START -->/,/<!-- COMPONENT_CONDITIONAL_NLWEB_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
        fi
        mv "$temp_file" "$ROOT_HOST_DIR/public_html/index.html"

        # Process Chatkit section
        if has_component "openai-chatkit"; then
            echo "✅ Including Chatkit section in HTML"
            # Keep the Chatkit section - remove the conditional markers
            sed '/<!-- COMPONENT_CONDITIONAL_CHATKIT_START -->/d; /<!-- COMPONENT_CONDITIONAL_CHATKIT_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
        else
            echo "❌ Excluding Chatkit section from HTML"
            # Remove the entire Chatkit section
            sed '/<!-- COMPONENT_CONDITIONAL_CHATKIT_START -->/,/<!-- COMPONENT_CONDITIONAL_CHATKIT_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
        fi
        mv "$temp_file" "$ROOT_HOST_DIR/public_html/index.html"

        if has_component "mcpauth"; then
            echo "✅ Including McpAuth section in HTML"
            sed -i '/<!-- COMPONENT_CONDITIONAL_IDP_START -->/d; /<!-- COMPONENT_CONDITIONAL_IDP_END -->/d' "$ROOT_HOST_DIR/public_html/index.html"
        else
            echo "❌ Excluding McpAuth section from HTML"
            sed -i '/<!-- COMPONENT_CONDITIONAL_IDP_START -->/,/<!-- COMPONENT_CONDITIONAL_IDP_END -->/d; /<!-- Start of IDP -->/,/<!-- End of IDP -->/d' "$ROOT_HOST_DIR/public_html/index.html"
        fi
        mv "$temp_file" "$ROOT_HOST_DIR/public_html/index.html"

        # Process Idp section
#        if has_component "mcpauth"; then
#            echo "✅ Including McpAuth section in HTML"
#            # Keep the Mcpauth section - remove the conditional markers
#            sed '/<!-- COMPONENT_CONDITIONAL_IDP_START -->/d; /<!-- COMPONENT_CONDITIONAL_IDP_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
#        else
#            echo "❌ Excluding McpAuth section from HTML"
#            nl -ba "$ROOT_HOST_DIR/public_html/index.html" | sed -n '/<!-- Start of IDP -->/,/<!-- End of IDP -->/p'
#
#                   # Remove the entire Mcpauth section
#            sed '/<!-- COMPONENT_CONDITIONAL_IDP_START -->/,/<!-- COMPONENT_CONDITIONAL_IDP_END -->/d' "$ROOT_HOST_DIR/public_html/index.html" > "$temp_file"
#        fi
#        mv "$temp_file" "$ROOT_HOST_DIR/public_html/index.html"
#
        echo "✅ HTML template processed successfully"
    else
        echo "⚠️ HTML template not found, skipping HTML processing"
    fi
}

# Update domains in CSV if present
update_domains_in_csv

# Process HTML template based on components
process_html_template

# Function to detect if pangolin+ is being used
is_pangolin_plus() {
    # Check if COMPONENTS_CSV contains pangolin+
    case "${COMPONENTS_CSV:-}" in
        *"pangolin+"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Traefik static config
if is_pangolin_plus; then
    # Pangolin+ configuration with CrowdSec support
    cat > "$ROOT_HOST_DIR/config/traefik/traefik_config.yml" << EOF
api:
  insecure: true
  dashboard: true

providers:
  http:
    endpoint: "http://pangolin:3001/api/v1/traefik-config"
    pollInterval: "5s"
  file:
    directory: "/rules"
    watch: true

experimental:
  plugins:
    badger:
      moduleName: "github.com/fosrl/badger"
      version: "v1.2.0"
    statiq:
      moduleName: github.com/hhftechnology/statiq
      version: v1.0.1
    crowdsec:
      moduleName: "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
      version: "v1.4.5"

log:
    level: "INFO"
    format: "json"
    maxSize: 100
    maxAge: 3
    compress: true

accessLog:
    filePath: "/var/log/traefik/access.log"
    format: json

certificatesResolvers:
  letsencrypt:
    acme:
      httpChallenge:
        entryPoint: web
      email: ${EMAIL}
      storage: "/letsencrypt/acme.json"
      caServer: "https://acme-v02.api.letsencrypt.org/directory"

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: "30m"
    http:
      tls:
        certResolver: "letsencrypt"
      middlewares:
        - crowdsec@file

serversTransport:
  insecureSkipVerify: true
EOF
else
    # Standard Pangolin configuration without CrowdSec
    cat > "$ROOT_HOST_DIR/config/traefik/traefik_config.yml" << EOF
api:
  insecure: true
  dashboard: true

providers:
  http:
    endpoint: "http://pangolin:3001/api/v1/traefik-config"
    pollInterval: "5s"
  file:
    directory: "/rules"
    watch: true

experimental:
  plugins:
    badger:
      moduleName: "github.com/fosrl/badger"
      version: "v1.2.0"
    statiq:
      moduleName: github.com/hhftechnology/statiq
      version: v1.0.1

log:
    level: "INFO"
    format: "json"
    maxSize: 100
    maxAge: 3
    compress: true

accessLog:
    filePath: "/var/log/traefik/access.log"
    format: json

certificatesResolvers:
  letsencrypt:
    acme:
      httpChallenge:
        entryPoint: web
      email: ${EMAIL}
      storage: "/letsencrypt/acme.json"
      caServer: "https://acme-v02.api.letsencrypt.org/directory"

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: "30m"
    http:
      tls:
        certResolver: "letsencrypt"

serversTransport:
  insecureSkipVerify: true
EOF
fi

# Dynamic config for pangolin and pangolin+
cat > "$ROOT_HOST_DIR/config/traefik/rules/dynamic_config.yml" << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3002" # Next.js server

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000" # API/WebSocket server
EOF

# NLWeb basic hook (no-op by default)
if [ -n "${OPENAI_API_KEY:-}" ]; then
  : # In modular system this will be handled by a component when added
fi

# Deployment info (base)
cat > "$ROOT_HOST_DIR/DEPLOYMENT_INFO.txt" << EOF
🚀 Pangolin + Traefik Stack Deployment

Deployment completed at: $(date)

📊 Configuration:
- Domain: ${DOMAIN}
- Admin Subdomain: ${ADMIN_SUBDOMAIN}
- Email: ${EMAIL}
- Admin User: admin@${DOMAIN}

🌐 Access Information:
- Dashboard URL: https://${ADMIN_SUBDOMAIN}.${DOMAIN}
- Admin Login: ${ADMIN_USERNAME}
- Admin Password: [Set during deployment]

📁 Directory Structure Created:
./config/
├── config.yml
├── letsencrypt/          # Let's Encrypt certificates
└── traefik/
    ├── rules/
    │   └── dynamic_config.yml
    ├── traefik_config.yml
    └── logs/             # Traefik logs

EOF

