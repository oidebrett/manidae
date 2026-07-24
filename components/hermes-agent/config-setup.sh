#!/bin/sh
set -e

# Hermes Agent Config Setup
# Generates Traefik routing rules for the Hermes web dashboard with basic-auth.

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
      email: "${EMAIL:-admin@${HERMES_DOMAIN}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# --- Hermes Routing Rule ---
# Proxies https://${HERMES_SUBDOMAIN}.${HERMES_DOMAIN} -> localhost:9119.
# The Hermes dashboard now owns authentication (its built-in `basic` provider — the
# host systemd service registers it via HERMES_DASHBOARD_BASIC_AUTH_* and binds 0.0.0.0
# so Hermes' auth gate engages). A non-loopback bind makes Hermes accept any Host/Origin
# and honour X-Forwarded-* headers, so this is a single plain router — no basic-auth
# middleware, no WebSocket Origin rewrite, no passHostHeader override. The chat WebSocket
# authenticates via the session cookie + ws-tickets.
cat > "${RULES_DIR}/hermes-agent.yml" <<EOF
http:
  routers:
    hermes-agent:
      rule: "Host(\`${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}\`)"
      service: hermes-agent
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    hermes-agent:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:9119"
EOF

log "✅ Hermes Agent Traefik rules generated for ${HERMES_SUBDOMAIN}.${HERMES_DOMAIN} (Hermes built-in auth)"
