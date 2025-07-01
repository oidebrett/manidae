#!/bin/sh

# Container Setup Script for Pangolin + CrowdSec + Traefik
# This script runs inside the Alpine container and creates the host folder structure

set -e

echo "🔧 Starting container setup process..."

# Generate a secure random secret key
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to create directories for CrowdSec
create_crowdsec_directories() {
    echo "📁 Creating CrowdSec directories..."
    mkdir -p /host-setup/config/crowdsec/db
    mkdir -p /host-setup/config/crowdsec/acquis.d
    mkdir -p /host-setup/config/traefik/logs
    mkdir -p /host-setup/config/traefik/conf
    mkdir -p /host-setup/config/crowdsec_logs
}

# Function to create CrowdSec config files
create_crowdsec_config() {
    echo "📝 Creating CrowdSec configuration files..."
    
    # Create acquis.yaml
    cat > /host-setup/config/crowdsec/acquis.yaml << 'EOF'
poll_without_inotify: false
filenames:
  - /var/log/traefik/*.log
labels:
  type: traefik
---
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: myAppSecComponent
source: appsec
labels:
  type: appsec
EOF

    # Create profiles.yaml
    cat > /host-setup/config/crowdsec/profiles.yaml << 'EOF'
name: captcha_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.GetScenario() contains "http"
decisions:
  - type: captcha
    duration: 4h
on_success: break

---
name: default_ip_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
 - type: ban
   duration: 4h
on_success: break

---
name: default_range_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
 - type: ban
   duration: 4h
on_success: break
EOF
    
    wget -O /host-setup/config/traefik/conf/captcha.html https://gist.githubusercontent.com/hhftechnology/48569d9f899bb6b889f9de2407efd0d2/raw/captcha.html 
    
}

# Function to update dynamic config with CrowdSec middleware
update_dynamic_config_with_crowdsec() {
    echo "📝 Updating dynamic config with CrowdSec middleware..."
    
    cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    security-headers:
      headers:
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""
          X-Forwarded-Proto: "https"
          Content-Security-Policy: "frame-ancestors 'self' https://${STATIC_PAGE_DOMAIN}.${DOMAIN}"
        contentTypeNosniff: true
        referrerPolicy: "strict-origin-when-cross-origin"
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsSeconds: 63072000
        stsPreload: true
    statiq:
      plugin:
        statiq:
          enableDirectoryListing: false
          indexFiles:
            - index.html
            - index.htm
          root: /var/www/html
          spaIndex: index.html
          spaMode: false

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
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    statiq-router-redirect:
      rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"
      service: statiq-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    statiq-router:
      entryPoints:
        - websecure
      middlewares:
        - statiq
      service: statiq-service
      priority: 100
      rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"

    # Add these lines for mcpauth
    # mcpauth http redirect router
    mcpauth-router-redirect:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # mcpauth router
    mcpauth:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
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

    statiq-service:
      loadBalancer:
        servers:
          - url: "noop@internal"

    mcpauth-service:
      loadBalancer:
        servers:
          - url: "http://mcpauth:11000"  # mcpauth auth server

    oauth-service:
      loadBalancer:
        servers:
          - url: "https://oauth.${DOMAIN}"

EOF
}

# Create directory structure on host
echo "📁 Creating directory structure..."
mkdir -p /host-setup/config/traefik
mkdir -p /host-setup/config/traefik/rules
mkdir -p /host-setup/config/letsencrypt
mkdir -p /host-setup/public_html

# Set proper permissions for Let's Encrypt directory
chmod 600 /host-setup/config/letsencrypt

echo "✅ Directory structure created"

# Generate secret key
SECRET_KEY=$(generate_secret)
echo "🔐 Generated secure secret key"

# Create config.yml
echo "📝 Creating config.yml..."
cat > /host-setup/config/config.yml << EOF
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
    base_endpoint: "${DOMAIN}"
    use_subdomain: false
    block_size: 24
    site_block_size: 30
    subnet_group: 100.89.137.0/20

rate_limits:
    global:
        window_minutes: 1
        max_requests: 500

users:
    server_admin:
        email: "${ADMIN_USERNAME}"
        password: "${ADMIN_PASSWORD}"

flags:
    require_email_verification: false
    disable_signup_without_invite: true
    disable_user_create_org: false
    allow_raw_resources: true
    allow_base_domain_resources: true

postgres:
    connection_string: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/postgres

EOF

echo "✅ config.yml created"

# Function to update domain in CSV files
update_domains_in_csv() {
    echo "🔄 Updating domain references in CSV files..."
    
    # Create postgres_export directory if it doesn't exist
    mkdir -p /host-setup/postgres_export
    
    # Check if resources.csv exists
    if [ -f "/host-setup/postgres_export/resources.csv" ]; then
        # Replace yourdomain.com with the DOMAIN variable in resources.csv
        sed -i "s/yourdomain\.com/${DOMAIN}/g" /host-setup/postgres_export/resources.csv
        echo "✅ Updated domain references in resources.csv"
    else
        echo "⚠️ resources.csv not found, skipping domain update"
    fi
}

# Call the function to update domains in CSV files
update_domains_in_csv

# Create traefik_config.yml
echo "📝 Creating traefik_config.yml..."
cat > /host-setup/config/traefik/traefik_config.yml << EOF
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

echo "✅ traefik_config.yml created"

# Function to create static page HTML
create_static_page_html() {
    echo "📄 Creating static page HTML..."
    mkdir -p /host-setup/public_html
    
    # Check if template exists in the templates directory
    if [ -f "/host-setup/templates/index.html" ]; then
        echo "Using template from templates directory"
        
        # Copy template to a temporary file
        cp "/host-setup/templates/index.html" "/tmp/index.html.template"
        
        # If KOMODO_HOST_IP is not set, remove the Komodo section from the template
        if [ -z "$KOMODO_HOST_IP" ]; then
            echo "Removing Komodo section from template as KOMODO_HOST_IP is not set"
            
            # Use sed to remove everything between the start and end Komodo comments
            sed -i '/<!-- Start of Komodo -->/,/<!-- End of Komodo -->/d' "/tmp/index.html.template"
            
            # Also remove Komodo from the welcome screen grid
            sed -i 's/Pangolin • Komodo/Pangolin/g' "/tmp/index.html.template"
        fi
        
        # Replace domain placeholders and write to final location
        cat "/tmp/index.html.template" | sed "s/yourdomain\.com/${DOMAIN}/g" | sed "s/subdomain/${ADMIN_SUBDOMAIN}/g" > /host-setup/public_html/index.html
        
        # Clean up temporary file
        rm "/tmp/index.html.template"
    else
        echo "Template not found, using embedded version"
        # Create basic index.html (fallback to embedded version)
        cat > /host-setup/public_html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>ContextWareAI Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-white font-sans h-screen overflow-hidden">
    <!-- Content here -->
</body>
</html>
EOF
    fi
}

# Check if static page should be enabled
if [ -n "$STATIC_PAGE_DOMAIN" ]; then
    echo "🛡️ Static page detected - setting up ..."
    create_static_page_html
fi


# Check if CrowdSec should be enabled
if [ -n "$CROWDSEC_ENROLLMENT_KEY" ]; then
    echo "🛡️ CrowdSec enrollment key detected - setting up CrowdSec..."
    ENABLE_CROWDSEC=true
    
    # Create CrowdSec directories
    create_crowdsec_directories
    
    # Create CrowdSec config files
    create_crowdsec_config
    
    # Update dynamic config with CrowdSec middleware
    update_dynamic_config_with_crowdsec
    
    echo "✅ CrowdSec configuration files created"

# Check if Static page should be enabled
elif [ -n "$STATIC_PAGE_DOMAIN" ]; then
    echo "🛡️ Static page detected - setting up dynamic config..."
    # Create basic dynamic_config.yml without CrowdSec
    cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    statiq:
      plugin:
        statiq:
          enableDirectoryListing: false
          indexFiles:
            - index.html
            - index.htm
          root: /var/www/html
          spaIndex: index.html
          spaMode: false

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

    statiq-router-redirect:
      rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"
      service: statiq-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    statiq-router:
        entryPoints:
            - websecure
        middlewares:
            - statiq
        priority: 100
        rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"
        service: statiq-service
        tls:
            certResolver: "letsencrypt"

  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3002" # Next.js server

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000" # API/WebSocket server

    statiq-service:
        loadBalancer:
            servers:
                - url: "noop@internal"

EOF

else
    echo "ℹ️ No CrowdSec enrollment key or static page - creating basic dynamic config..."
    ENABLE_CROWDSEC=false
    
    # Create basic dynamic_config.yml without CrowdSec
    cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
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
fi

echo "✅ dynamic_config.yml created"

# Create a summary file for the user
cat > /host-setup/DEPLOYMENT_INFO.txt << EOF
🚀 Pangolin + CrowdSec + Traefik Stack Deployment

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
    ├── conf/             # CAPTCHA template support
    └── logs/             # Traefik logs

EOF

if [ -n \"$CROWDSEC_ENROLLMENT_KEY\" ]; then
cat >> /host-setup/DEPLOYMENT_INFO.txt << EOF
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    └── profiles.yaml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec

🛡️ CrowdSec Notes:
- AppSec and log parsing is configured
- Prometheus and API are enabled
- CAPTCHA and remediation profiles are active
- Remember to get the bouncer API key after containers start:
  docker exec crowdsec cscli bouncers add traefik-bouncer
EOF
fi

cat >> /host-setup/DEPLOYMENT_INFO.txt << EOF

🔧 Management Commands:
- View logs: docker compose logs -f
- Restart: docker compose restart
- Stop: docker compose down
- Update: docker compose pull && docker compose up -d

⚠️  Important Notes:
- Ensure ${DOMAIN} DNS points to this server's IP
- Let's Encrypt certificates may take a few minutes to issue
- All traffic is automatically redirected to HTTPS

🔐 Security:
- Secure random secret generated: ${SECRET_KEY}
- HTTPS enforced via Traefik
- Admin access configured

Generated by Pangolin Container Setup
EOF

echo "✅ All configuration files created successfully!"
echo "📋 Deployment info saved to DEPLOYMENT_INFO.txt"

# Final summary
echo ""
echo "🎉 Setup Complete!"
echo "================================"
if [ -n "$CROWDSEC_ENROLLMENT_KEY" ]; then
    echo "✅ CrowdSec configuration included"
    echo "⚠️  Remember to:"
    echo "   - Start your containers: docker compose up -d"
    echo "   - Get bouncer key: docker exec crowdsec cscli bouncers add traefik-bouncer"
    echo "   - Update dynamic_config.yml with the bouncer key"
    echo "   - Restart traefik: docker compose restart traefik"
else
    echo "ℹ️  Basic Traefik configuration (no CrowdSec)"
    echo "💡 To add CrowdSec later, set CROWDSEC_ENROLLMENT_KEY and re-run"
fi
