#!/bin/sh
# NemoClaw component setup - generates Traefik config for HTTPS routing
set -e

echo "Setting up NemoClaw Traefik routing..."

# Default values
NEMOCLAW_SUBDOMAIN="${NEMOCLAW_SUBDOMAIN:-nemoclaw}"
NEMOCLAW_DOMAIN="${NEMOCLAW_DOMAIN:-nemoclaw.dpdns.org}"
NEMOCLAW_EMAIL="${EMAIL:-admin@nemoclaw.dpdns.org}"
HOST_SETUP_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Create required directories
mkdir -p "${HOST_SETUP_DIR}/config/traefik/rules"
mkdir -p "${HOST_SETUP_DIR}/config/letsencrypt"
chmod 600 "${HOST_SETUP_DIR}/config/letsencrypt"

# Create Traefik static configuration
cat > "${HOST_SETUP_DIR}/config/traefik/traefik_config.yml" << EOF
api:
  insecure: true
  dashboard: true

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
      email: ${NEMOCLAW_EMAIL}
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

# Create Traefik dynamic configuration for NemoClaw dashboard routing
# Routes {subdomain}.nemoclaw.dpdns.org to the OpenShell-forwarded port 18789
cat > "${HOST_SETUP_DIR}/config/traefik/rules/dynamic_config.yml" << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https

  routers:
    nemoclaw-router-redirect:
      rule: "Host(\`${NEMOCLAW_SUBDOMAIN}.${NEMOCLAW_DOMAIN}\`)"
      service: nemoclaw-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    nemoclaw-router:
      rule: "Host(\`${NEMOCLAW_SUBDOMAIN}.${NEMOCLAW_DOMAIN}\`)"
      service: nemoclaw-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    nemoclaw-service:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:18789"
EOF

echo "NemoClaw Traefik setup complete"
echo "Dashboard will be available at: https://${NEMOCLAW_SUBDOMAIN}.${NEMOCLAW_DOMAIN}"
