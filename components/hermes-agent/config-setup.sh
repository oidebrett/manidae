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
# Two routers because browsers don't forward HTTP basic-auth on WebSocket upgrades:
#   /api/*  → no basic-auth (Hermes' ephemeral session token in the SPA HTML
#             gates these endpoints anyway). Required for /api/ws, /api/events, /api/pty.
#   /       → basic-auth (gates the HTML so the session token isn't leaked).
cat > "${RULES_DIR}/hermes-agent.yml" <<EOF
http:
  middlewares:
    hermes-auth:
      basicAuth:
        users:
          - "${HERMES_AUTH_USER}:${HERMES_AUTH_PASSWORD_HASH}"
    # Rewrite the WebSocket Origin to the loopback host. The dashboard binds
    # 127.0.0.1 and rejects WS upgrades whose Origin host != its bound host
    # ("pty refused: origin_mismatch"), so the browser's public Origin would
    # otherwise close the chat socket (code 1006). Traefik already rewrites the
    # Host (passHostHeader=false); this does the same for Origin.
    hermes-ws-origin:
      headers:
        customRequestHeaders:
          Origin: "http://127.0.0.1:9119"

  routers:
    # /api/* — gated only by Hermes' ephemeral session token (browsers do not
    # send HTTP basic-auth on WebSocket upgrades, so Traefik basic-auth on
    # /api/ws, /api/events, /api/pty would break the chat tab).
    hermes-agent-api:
      rule: "Host(\`${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}\`) && PathPrefix(\`/api/\`)"
      service: hermes-agent
      priority: 100
      middlewares:
        - hermes-ws-origin
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # SPA shell + static — basic-auth (so the HTML carrying the session token
    # is gated). Lower priority means /api/* matches first.
    hermes-agent:
      rule: "Host(\`${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}\`)"
      service: hermes-agent
      priority: 10
      middlewares:
        - hermes-auth
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    hermes-agent:
      loadBalancer:
        # Hermes dashboard validates the Host header against its bind address
        # and rejects requests forwarded with the public hostname.
        # passHostHeader=false makes Traefik send the upstream URL's host instead.
        passHostHeader: false
        servers:
          - url: "http://127.0.0.1:9119"
EOF

log "✅ Hermes Agent Traefik rules generated for ${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}"
