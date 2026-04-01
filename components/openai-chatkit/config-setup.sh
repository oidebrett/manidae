#!/bin/sh
# OpenAI Chatkit standalone component setup
set -e

echo "🤖 Setting up OpenAI Chatkit standalone component..."

# Set default subdomain if not provided
CHATKIT_SUBDOMAIN="${CHATKIT_SUBDOMAIN:-chatkit}"

# Create required directories
echo "📁 Creating Traefik directories..."
mkdir -p "/host-setup/config/traefik/rules"
mkdir -p "/host-setup/config/letsencrypt"
chmod 600 "/host-setup/config/letsencrypt"

# Create Traefik static configuration
echo "🔧 Creating Traefik static configuration..."
cat > "/host-setup/config/traefik/traefik_config.yml" << EOF
api:
  insecure: true
  dashboard: false

providers:
  file:
    directory: "/rules"
    watch: true

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: "INFO"
  format: "json"

accessLog:
  format: json

serversTransport:
  insecureSkipVerify: true
EOF

# Create Traefik dynamic configuration for chatkit routing
echo "🔧 Creating Traefik dynamic configuration for chatkit..."
cat > "/host-setup/config/traefik/rules/dynamic_config.yml" << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    chatkit-router-redirect:
      rule: "Host(\`${CHATKIT_SUBDOMAIN}.${DOMAIN}\`)"
      service: chatkit-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    chatkit-router:
      rule: "Host(\`${CHATKIT_SUBDOMAIN}.${DOMAIN}\`)"
      service: chatkit-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    chatkit-service:
      loadBalancer:
        servers:
          - url: "http://chatkit-embed:8000"
EOF

echo "✅ OpenAI Chatkit standalone component setup complete"
echo "🌐 Chatkit will be available at: https://${CHATKIT_SUBDOMAIN}.${DOMAIN}"
