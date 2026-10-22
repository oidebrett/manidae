#!/bin/sh
# PrivateInference: route https://<PI_INFERENCE_SUBDOMAIN>.<DOMAIN> to the PII router
# that manidae-cloud installs on the HOST (systemd pii-router, LiteLLM).
#
# - No Pangolin SSO / badger middleware: API clients cannot follow an SSO
#   redirect. The router's LITELLM_MASTER_KEY is the auth (no key -> 401).
# - CrowdSec still applies: it is attached to the websecure entrypoint.
# - Only /v1/... is published: LiteLLM's own pages (/, /ui admin UI, /docs) never
#   reach the internet, whatever its settings (1.104 serves /ui despite DISABLE_ADMIN_UI).
# - Upstream is the Docker bridge IP, not host.docker.internal: Pangolin+'s
#   Traefik (in Gerbil's network namespace) has no host-gateway alias. The
#   router binds that same IP (PII_ROUTER_HOST in manidae-cloud's install).
# Regenerated on every setup run, so a Komodo reclone cannot leave it stale.
set -e
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"
SUB="${PI_INFERENCE_SUBDOMAIN:-inference}"
UPSTREAM="${PII_ROUTER_UPSTREAM:-http://172.17.0.1:4100}"

if [ -z "${DOMAIN:-}" ]; then
    echo "⚠️  private-inference: DOMAIN is empty - skipping inference route"
    exit 0
fi

mkdir -p "$ROOT_HOST_DIR/config/traefik/rules"
cat > "$ROOT_HOST_DIR/config/traefik/rules/private-inference.yml" << RULE_EOF
# Managed by manidae components/private-inference/config-setup.sh - do not edit.
http:
  routers:
    9-private-inference:
      entryPoints: [websecure]
      priority: 250
      rule: "Host(\`${SUB}.${DOMAIN}\`) && PathPrefix(\`/v1/\`)"
      service: 9-private-inference-svc
      tls:
        certResolver: letsencrypt
  services:
    9-private-inference-svc:
      loadBalancer:
        servers:
          - url: "${UPSTREAM}"
RULE_EOF
echo "✅ private-inference: https://${SUB}.${DOMAIN}/v1 -> ${UPSTREAM}"
