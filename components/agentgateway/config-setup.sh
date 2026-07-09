#!/bin/sh
# AgentGateway setup (Pangolin-based platform with MCP Auth and OpenShell Controller)
set -e

echo "🤖 Setting up AgentGateway platform..."

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Core shared functions
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Portable sed -i: macOS (BSD sed) requires an explicit backup extension arg
_sed_i() {
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Directories
echo "📁 Creating AgentGateway directories..."
mkdir -p "$ROOT_HOST_DIR/config/traefik"
mkdir -p "$ROOT_HOST_DIR/config/traefik/rules"
mkdir -p "$ROOT_HOST_DIR/config/letsencrypt"
mkdir -p "$ROOT_HOST_DIR/public_html"
chmod 600 "$ROOT_HOST_DIR/config/letsencrypt"

# Copy HTML template from agentgateway component
echo "📄 Setting up AgentGateway HTML template..."
if [ -f "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/templates/html/index.html" ]; then
    cp "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/templates/html/index.html" "$ROOT_HOST_DIR/public_html/index.html"
elif [ -f "/components/agentgateway/templates/html/index.html" ]; then
    cp "/components/agentgateway/templates/html/index.html" "$ROOT_HOST_DIR/public_html/index.html"
else
    echo "⚠️  AgentGateway HTML template not found, creating basic fallback"
    cat > "$ROOT_HOST_DIR/public_html/index.html" << 'EOF'
<!DOCTYPE html><html><head><title>AgentGateway</title></head><body>
<h1>AgentGateway</h1>
<p><a href="https://openshell-controller.yourdomain.com">OpenShell Controller</a></p>
<p><a href="https://idp.yourdomain.com">MCP Auth</a></p>
</body></html>
EOF
fi

# Replace domain placeholders in the HTML
_sed_i "s/yourdomain\.com/${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"

if [ -n "${ADMIN_SUBDOMAIN:-}" ]; then
    _sed_i "s/subdomain\.${DOMAIN}/${ADMIN_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"
fi
if [ -n "${MIDDLEWARE_MANAGER_SUBDOMAIN:-}" ]; then
    _sed_i "s/middleware-manager\.${DOMAIN}/${MIDDLEWARE_MANAGER_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"
fi
if [ -n "${CROWDSEC_MANAGER_SUBDOMAIN:-}" ]; then
    _sed_i "s/crowdsec-manager\.${DOMAIN}/${CROWDSEC_MANAGER_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"
fi
if [ -n "${IDP_SUBDOMAIN:-}" ]; then
    _sed_i "s/idp\.${DOMAIN}/${IDP_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"
fi
if [ -n "${OPENSHELL_CONTROLLER_SUBDOMAIN:-}" ]; then
    _sed_i "s/openshell-controller\.${DOMAIN}/${OPENSHELL_CONTROLLER_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/public_html/index.html"
fi
echo "✅ HTML template configured"

# Secret
SECRET_KEY=$(generate_secret)

# config.yml (Pangolin base config)
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
COMPONENT_PATH=""
if [ -d "${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/postgres_export" ]; then
    COMPONENT_PATH="${MANIDAE_ROOT:-$ROOT_HOST_DIR}/components/agentgateway/postgres_export"
elif [ -d "/components/agentgateway/postgres_export" ]; then
    COMPONENT_PATH="/components/agentgateway/postgres_export"
fi

if [ -n "$COMPONENT_PATH" ]; then
    mkdir -p "$ROOT_HOST_DIR/postgres_export"
    cp -r "$COMPONENT_PATH"/* "$ROOT_HOST_DIR/postgres_export/"
    echo "✅ Copied AgentGateway postgres_export files from $COMPONENT_PATH"
else
    echo "⚠️ AgentGateway postgres_export directory not found, skipping copy"
fi

# Update domain placeholders in CSV files
update_domains_in_csv() {
    if [ -f "$ROOT_HOST_DIR/postgres_export/resources.csv" ]; then
        _sed_i "s/yourdomain\.com/${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"

        if [ -n "${CROWDSEC_MANAGER_SUBDOMAIN:-}" ]; then
            _sed_i "s/crowdsec-manager\.${DOMAIN}/${CROWDSEC_MANAGER_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"
            echo "✅ Updated crowdsec-manager subdomain to ${CROWDSEC_MANAGER_SUBDOMAIN}"
        fi

        if [ -n "${OPENSHELL_CONTROLLER_SUBDOMAIN:-}" ]; then
            _sed_i "s/openshell-controller\.${DOMAIN}/${OPENSHELL_CONTROLLER_SUBDOMAIN}.${DOMAIN}/g" "$ROOT_HOST_DIR/postgres_export/resources.csv"
            echo "✅ Updated openshell-controller subdomain to ${OPENSHELL_CONTROLLER_SUBDOMAIN}"
        fi

        echo "✅ Updated domain references in resources.csv"
    else
        echo "⚠️ resources.csv not found, skipping domain update"
    fi
}

update_domains_in_csv

# Traefik static config with CrowdSec support
echo "🔧 Creating Traefik configuration..."
cat > "$ROOT_HOST_DIR/config/traefik/traefik_config.yml" << EOF
api:
  insecure: true
  dashboard: false

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
    main-app-router-redirect:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    next-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN:-pangolin}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

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
          - url: "http://pangolin:3002"

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000"
EOF

# Traefik WS bypass router for OpenShell Controller dashboard WebSocket upgrades
# Pangolin's badger@http middleware sends a TCP FIN after forwarding the WS upgrade
# request, breaking the tunnel before OpenClaw can respond. We route upgrade requests
# on the dashboard proxy paths directly to the controller (no badger middleware),
# using a higher-priority rule so it wins before the badger-gated router fires.
# Upstream points at the main controller HTTP server on :3000 — the controller's
# server.mjs handles dashboard WS upgrades inline. (An optional WS-only sidecar
# can be enabled by setting OPENCLAW_DASHBOARD_WS_PROXY_PORT in the controller's
# .env.local, but the main server handles upgrades equivalently.)
if [ -n "${OPENSHELL_CONTROLLER_SUBDOMAIN:-}" ]; then
    echo "🔌 Creating OpenShell Controller WebSocket bypass router..."
    cat > "$ROOT_HOST_DIR/config/traefik/rules/openshell-ws-router.yml" << EOF
http:
  routers:
    8-openshell-controller-ws-router:
      entryPoints:
        - websecure
      priority: 300
      rule: "Host(\`${OPENSHELL_CONTROLLER_SUBDOMAIN}.${DOMAIN}\`) && (PathPrefix(\`/api/openshell/dashboard/proxy\`) || PathPrefix(\`/api/openshell/instances/\`)) && HeaderRegexp(\`Upgrade\`, \`(?i)websocket\`)"
      service: "8-openshell-controller-ws-service@file"
      tls:
        certResolver: "letsencrypt"
  services:
    8-openshell-controller-ws-service:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:3000"
EOF
    echo "✅ OpenShell Controller WebSocket bypass router configured"
fi

echo "✅ AgentGateway platform setup complete"
