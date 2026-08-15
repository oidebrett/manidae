#!/bin/sh
set -e

# Buzz Relay Config Setup
# Generates Traefik routing rules that terminate TLS for the self-hosted Buzz
# relay and proxy both HTTPS and wss:// to the host's loopback listener.

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
      email: "${EMAIL:-admin@${BUZZ_DOMAIN}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# --- Buzz Routing Rule ---
# ONE router, no middlewares → http://127.0.0.1:3000.
# The relay serves the WebSocket, the REST API, the media endpoints and the web
# UI from the same port, and does its own client authentication, so a single
# catch-all router for the host is exactly right. Adding basic-auth here would
# break the Buzz desktop app's NIP-42/98 handshake.
cat > "${RULES_DIR}/buzz.yml" <<EOF
http:
  routers:
    buzz:
      rule: "Host(\`${BUZZ_SUBDOMAIN}.${BUZZ_DOMAIN}\`)"
      service: buzz
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    buzz:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:3000"
EOF

log "✅ Buzz Traefik rules generated for ${BUZZ_SUBDOMAIN}.${BUZZ_DOMAIN} (wss:// ready)"
