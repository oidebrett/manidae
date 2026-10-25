#!/bin/sh
set -e

# OpenClaw Enterprise Config Setup
# Generates the Traefik main config. OCE's console is only on the host loopback for now
# (development launcher, see manidae-cloud docs/oce-package-plan.md), so no console router
# is written here yet; the voice bridge adds its own /telnyx/* + /twilio/* router.

log() { printf "%s\n" "$*"; }

CONFIG_DIR="${MANIDAE_ROOT:-/host-setup}/config"
TRAEFIK_DIR="${CONFIG_DIR}/traefik"
RULES_DIR="${TRAEFIK_DIR}/rules"

mkdir -p "${RULES_DIR}"

cat > "${TRAEFIK_DIR}/traefik_config.yml" <<EOT
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
      email: "${EMAIL:-admin@${OCE_DOMAIN}}"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOT

log "✅ OCE Traefik config generated for ${OCE_SUBDOMAIN}.${OCE_DOMAIN}"
