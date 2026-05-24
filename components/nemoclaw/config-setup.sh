#!/bin/sh
# NemoClaw component setup - generates Traefik config for HTTPS routing
set -e

echo "Setting up NemoClaw Traefik routing..."

# Default values
NEMOCLAW_SUBDOMAIN="${NEMOCLAW_SUBDOMAIN:-nemoclaw}"
NEMOCLAW_DOMAIN="${NEMOCLAW_DOMAIN:-nemoclaw.dpdns.org}"
NEMOCLAW_EMAIL="${EMAIL:-admin@nemoclaw.dpdns.org}"
NEMOCLAW_AGENT="${NEMOCLAW_AGENT:-openclaw}"
# Port forwarded by OpenShell/nemohermes from the sandbox to localhost:
#   - openclaw runtime → 18789 (browser dashboard, gateway-token auth built in)
#   - hermes runtime   → 8642  (OpenAI-compatible HTTP API, NO built-in auth — we add basic-auth here)
if [ "${NEMOCLAW_AGENT}" = "hermes" ]; then
  NEMOCLAW_TARGET_PORT=8642
  NEMOCLAW_AUTH_USER="${NEMOCLAW_AUTH_USER:-admin}"
  NEMOCLAW_AUTH_PASSWORD_HASH="${NEMOCLAW_AUTH_PASSWORD_HASH:-}"
else
  NEMOCLAW_TARGET_PORT=18789
fi
HOST_SETUP_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Create required directories
mkdir -p "${HOST_SETUP_DIR}/config/traefik/rules"
mkdir -p "${HOST_SETUP_DIR}/config/letsencrypt"
chmod 600 "${HOST_SETUP_DIR}/config/letsencrypt"

# Create Traefik static configuration
cat > "${HOST_SETUP_DIR}/config/traefik/traefik_config.yml" << EOF
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

# Create Traefik dynamic configuration for NemoClaw routing
# OpenClaw runtime: gateway-token auth lives inside OpenClaw — no Traefik auth needed.
# Hermes runtime:   API has no built-in auth — gate the public route with basic-auth.
if [ "${NEMOCLAW_AGENT}" = "hermes" ] && [ -n "${NEMOCLAW_AUTH_PASSWORD_HASH}" ]; then
  cat > "${HOST_SETUP_DIR}/config/traefik/rules/dynamic_config.yml" << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    nemoclaw-auth:
      basicAuth:
        users:
          - "${NEMOCLAW_AUTH_USER}:${NEMOCLAW_AUTH_PASSWORD_HASH}"

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
      middlewares:
        - nemoclaw-auth
      tls:
        certResolver: letsencrypt

  services:
    nemoclaw-service:
      loadBalancer:
        servers:
          - url: "http://localhost:${NEMOCLAW_TARGET_PORT}"
EOF
else
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
          - url: "http://localhost:${NEMOCLAW_TARGET_PORT}"
EOF
fi

echo "NemoClaw Traefik setup complete"
echo "Dashboard will be available at: https://${NEMOCLAW_SUBDOMAIN}.${NEMOCLAW_DOMAIN}"
