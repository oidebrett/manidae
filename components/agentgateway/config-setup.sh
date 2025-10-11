#!/bin/sh
# AgentGateway setup (Pangolin-based platform with chatkit-embed)
set -e

echo "🤖 Setting up AgentGateway platform..."

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Core shared functions
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Directories
echo "📁 Creating AgentGateway directories..."
mkdir -p "$ROOT_HOST_DIR/config/traefik"
mkdir -p "$ROOT_HOST_DIR/config/traefik/rules"
mkdir -p "$ROOT_HOST_DIR/config/letsencrypt"
mkdir -p "$ROOT_HOST_DIR/public_html"
chmod 600 "$ROOT_HOST_DIR/config/letsencrypt"

# Secret
SECRET_KEY=$(generate_secret)

# config.yml (base)
echo "⚙️ Creating Pangolin configuration..."
cat > "$ROOT_HOST_DIR/config/config.yml" << EOF
app:
    dashboard_url: "https://${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}"
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
    base_endpoint: "${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}"
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
    connection_string: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-postgres}@${POSTGRES_HOST:-pangolin-postgres}:5432/postgres

EOF

# Copy postgres_export files
echo "📊 Setting up database export files..."
if [ -d "$ROOT_HOST_DIR/postgres_export" ]; then
    echo "✅ postgres_export directory already exists"
else
    # Find the correct path to the agentgateway component
    COMPONENT_PATH=""
    if [ -d "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/postgres_export" ]; then
        COMPONENT_PATH="${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/postgres_export"
    elif [ -d "/components/agentgateway/postgres_export" ]; then
        COMPONENT_PATH="/components/agentgateway/postgres_export"
    fi

    if [ -n "$COMPONENT_PATH" ]; then
        cp -r "$COMPONENT_PATH" "$ROOT_HOST_DIR/"
        echo "✅ Copied postgres_export files from $COMPONENT_PATH"
    else
        echo "⚠️ postgres_export directory not found, skipping copy"
    fi
fi

# Update domains in CSV files
update_domains_in_csv() {
    # Check if resources.csv exists
    if [ -f "$ROOT_HOST_DIR/postgres_export/resources.csv" ]; then
        # Replace yourdomain.com with the DOMAIN variable in resources.csv
        sed -i "s/yourdomain\.com/${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"

        # Update traefik subdomain if custom subdomain is provided
        if [ -n "${TRAEFIK_SUBDOMAIN:-}" ]; then
            sed -i "s/traefik\.${DOMAIN}/${TRAEFIK_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"
            echo "✅ Updated traefik subdomain to ${TRAEFIK_SUBDOMAIN}"
        fi

        # Update chatkit subdomain if custom subdomain is provided
        if [ -n "${CHATKIT_SUBDOMAIN:-}" ]; then
            sed -i "s/chat\.${DOMAIN}/${CHATKIT_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"
            echo "✅ Updated chatkit subdomain to ${CHATKIT_SUBDOMAIN}"
        fi

        echo "✅ Updated domain references in resources.csv"
    else
        echo "⚠️ resources.csv not found, skipping domain update"
    fi
}

# Update domains in CSV if present
update_domains_in_csv

# Function to detect if agentgateway+ is being used (always true for agentgateway)
is_agentgateway_plus() {
    return 0  # AgentGateway always includes enhanced features
}

# Traefik static config with CrowdSec support (AgentGateway always includes security)
echo "🔧 Creating Traefik configuration with security features..."
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

# Dynamic config for AgentGateway
echo "🌐 Creating dynamic routing configuration..."
cat > "$ROOT_HOST_DIR/config/traefik/rules/dynamic_config.yml" << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`)"
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

echo "✅ AgentGateway platform setup complete"
