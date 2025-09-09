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

# Function to update domain in CSV files
update_domains_in_csv() {
    echo "🔄 Updating domain references in CSV files..."

    # Create postgres_export directory if it doesn't exist
    mkdir -p "$ROOT_HOST_DIR/postgres_export"

    # Copy postgres_export data from component to host setup directory
    if [ -d "$ROOT_HOST_DIR/components/pangolin/postgres_export" ]; then
        cp -r "$ROOT_HOST_DIR/components/pangolin/postgres_export"/* "$ROOT_HOST_DIR/postgres_export/"
        echo "✅ Copied postgres_export data from pangolin component"
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

# Update domains in CSV if present
update_domains_in_csv

# Traefik static config
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

# Basic dynamic_config.yml without optional middlewares
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

