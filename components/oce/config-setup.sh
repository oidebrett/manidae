#!/bin/sh
set -e

# OpenClaw Enterprise Config Setup
# Generates the Traefik main config and the console route. OCE runs on the host in k3d
# (production Helm install by manidae-cloud, docs/oce-package-plan.md); its k3d load balancer
# listens on 127.0.0.1:18480. The install writes the same oce-console.yml; writing it here too
# keeps the route if the stack directory is re-cloned. The voice bridge adds its own router.

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

if [ -n "${OCE_SUBDOMAIN:-}" ] && [ -n "${OCE_DOMAIN:-}" ]; then
cat > "${RULES_DIR}/oce-console.yml" <<EOT
# OpenClaw Enterprise console (manidae oce component; same file as the manidae-cloud install writes)
http:
  routers:
    oce-console:
      entryPoints: [websecure]
      rule: "Host(\`${OCE_SUBDOMAIN}.${OCE_DOMAIN}\`)"
      service: oce-console
      tls: { certResolver: letsencrypt }
    oce-console-root:
      entryPoints: [websecure]
      rule: "Host(\`${OCE_SUBDOMAIN}.${OCE_DOMAIN}\`) && Path(\`/\`)"
      middlewares: [oce-console-root]
      service: oce-console
      tls: { certResolver: letsencrypt }
  middlewares:
    oce-console-root:
      redirectRegex:
        regex: ".*"
        replacement: "https://${OCE_SUBDOMAIN}.${OCE_DOMAIN}/console/"
  services:
    oce-console:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:18480"
EOT
fi

log "✅ OCE Traefik config generated for ${OCE_SUBDOMAIN}.${OCE_DOMAIN}"
