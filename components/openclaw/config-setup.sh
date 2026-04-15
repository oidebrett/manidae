#!/bin/sh
set -e

# OpenClaw Config Setup
# Generates Traefik routing rules for OpenClaw

log() { printf "%s\n" "$*"; }

CONFIG_DIR="${MANIDAE_ROOT:-/host-setup}/config"
TRAEFIK_DIR="${CONFIG_DIR}/traefik"
RULES_DIR="${TRAEFIK_DIR}/rules"

mkdir -p "${RULES_DIR}"

# --- Traefik Main Config ---
cat > "${TRAEFIK_DIR}/traefik_config.yml" <<EOF
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  file:
    directory: /rules
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${EMAIL:-admin@${OPENCLAW_DOMAIN}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# --- OpenClaw Routing Rule ---
# Proxies https://${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN} -> localhost:18789
cat > "${RULES_DIR}/openclaw.yml" <<EOF
http:
  routers:
    openclaw:
      rule: "Host(\`${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN}\`)"
      service: openclaw
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    openclaw:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:18789"
EOF

log "✅ OpenClaw Traefik rules generated for ${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN}"
