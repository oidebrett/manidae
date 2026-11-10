#!/bin/sh
# Inference Router: route https://<IR_API_SUBDOMAIN>.<DOMAIN>/v1 to the router that
# manidae-cloud installs on the HOST (systemd inference-router, LiteLLM, port 4100).
#
# - No Pangolin SSO on the API: API clients cannot follow an SSO redirect. Per-person
#   API keys are the auth (no key -> 401). CrowdSec applies via the websecure entrypoint.
# - Only /v1/... is published: LiteLLM's own pages never reach the internet.
# - The admin UI (port 4110) is NOT published here: it is Pangolin resource 12
#   (components/pangolin/postgres_export), behind Pangolin SSO, at <IR_ADMIN_SUBDOMAIN>.
# - Upstream is the Docker bridge IP: Pangolin+'s Traefik (in Gerbil's network
#   namespace) has no host-gateway alias; the router binds that same IP.
# Regenerated on every setup run, so a Komodo reclone cannot leave it stale.
set -e
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"
SUB="${IR_API_SUBDOMAIN:-inference}"
UPSTREAM="${IR_API_UPSTREAM:-http://172.17.0.1:4100}"

if [ -z "${DOMAIN:-}" ]; then
    echo "⚠️  inference-router: DOMAIN is empty - skipping the API route"
    exit 0
fi

mkdir -p "$ROOT_HOST_DIR/config/traefik/rules"
cat > "$ROOT_HOST_DIR/config/traefik/rules/inference-router.yml" << RULE_EOF
# Managed by manidae components/inference-router/config-setup.sh - do not edit.
http:
  routers:
    9-inference-router:
      entryPoints: [websecure]
      priority: 250
      rule: "Host(\`${SUB}.${DOMAIN}\`) && PathPrefix(\`/v1/\`)"
      service: 9-inference-router-svc
      tls:
        certResolver: letsencrypt
  services:
    9-inference-router-svc:
      loadBalancer:
        servers:
          - url: "${UPSTREAM}"
RULE_EOF
echo "✅ inference-router: https://${SUB}.${DOMAIN}/v1 -> ${UPSTREAM} (admin UI: https://${IR_ADMIN_SUBDOMAIN:-router}.${DOMAIN}, Pangolin SSO)"
