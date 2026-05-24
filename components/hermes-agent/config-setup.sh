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
# Proxies https://${HERMES_SUBDOMAIN}.${HERMES_DOMAIN} -> localhost:9119
# Protected by HTTP basic-auth because Hermes' dashboard has no built-in auth.
cat > "${RULES_DIR}/hermes-agent.yml" <<EOF
http:
  middlewares:
    hermes-auth:
      basicAuth:
        users:
          - "${HERMES_AUTH_USER}:${HERMES_AUTH_PASSWORD_HASH}"

  routers:
    hermes-agent:
      rule: "Host(\`${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}\`)"
      service: hermes-agent
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
        # (127.0.0.1:9119) and rejects requests forwarded with the public hostname.
        # passHostHeader=false makes Traefik send the upstream URL's host instead.
        passHostHeader: false
        servers:
          - url: "http://127.0.0.1:9119"
EOF

log "✅ Hermes Agent Traefik rules generated for ${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}"
