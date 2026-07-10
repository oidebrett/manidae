#!/bin/sh
set -e

# OpenComputer Config Setup
# Generates Traefik routing rules for the OpenComputer agent dashboard with basic-auth.

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
      email: "${EMAIL:-admin@${OC_DOMAIN}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# --- OpenComputer Routing Rule ---
# ONE router, basic-auth on ALL paths → http://127.0.0.1:9800.
# Validated (Chromium + Firefox): the browser sends the origin's cached basic-auth on
# the /ws/events (agent event stream) and /desktop (noVNC) WebSocket handshakes, so a
# single router suffices — no /api exemption, no Origin rewrite (the interface-service
# has no WS Origin check and CORS is already '*').
cat > "${RULES_DIR}/opencomputer.yml" <<EOF
http:
  middlewares:
    opencomputer-auth:
      basicAuth:
        users:
          - "${OC_AUTH_USER}:${OC_AUTH_PASSWORD_HASH}"

  routers:
    opencomputer:
      rule: "Host(\`${OC_SUBDOMAIN}.${OC_DOMAIN}\`)"
      service: opencomputer
      entryPoints:
        - websecure
      middlewares:
        - opencomputer-auth
      tls:
        certResolver: letsencrypt

  services:
    opencomputer:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9800"
EOF

log "✅ OpenComputer Traefik rules generated for ${OC_SUBDOMAIN}.${OC_DOMAIN}"
