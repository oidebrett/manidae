#!/usr/bin/env bash
set -euo pipefail

# Orchestrator: builds compose.yaml, container-setup.sh, DEPLOYMENT_INFO.txt
# Usage:
#   COMPONENTS="pangolin,crowdsec,mcpauth,komodo" OUTPUT_DIR=./out ./orchestrator/build-compose.sh
#   COMPONENTS="coolify,crowdsec" OUTPUT_DIR=./out ./orchestrator/build-compose.sh
# Env:
#   COMPONENTS       Comma-separated list of components (must include a base platform: pangolin or coolify)
#   OUTPUT_DIR       Directory to write outputs (default: $PWD)
#   DRY_RUN=1        If set, do not execute the generated container-setup.sh
#   SKIP_ENVSUBST=1  If set, do not run envsubst on outputs (useful for tests)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPONENTS_RAW="${COMPONENTS:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD}"

# Auto-derive COMPONENTS if not provided
if [[ -z "$COMPONENTS_RAW" ]]; then
  echo "[orchestrator] Auto-deriving COMPONENTS..."

  # Detect base platform
  if [[ -n "${DB_USERNAME:-}" || -n "${REDIS_PASSWORD:-}" || -n "${PUSHER_APP_ID:-}" || -n "${PUSHER_APP_KEY:-}" || -n "${PUSHER_APP_SECRET:-}" ]]; then
    echo "[orchestrator] Detected Coolify platform (Coolify environment variables are set)"
    COMPONENTS_RAW="coolify"
  elif [[ -n "${OPENAI_API_KEY:-}" && -n "${WORKFLOW_ID:-}" && -n "${ADMIN_USERNAME:-}" && -n "${ADMIN_PASSWORD:-}" ]]; then
    echo "[orchestrator] Detected AgentGateway platform (OPENAI_API_KEY, WORKFLOW_ID, and admin credentials are set)"
    COMPONENTS_RAW="agentgateway,middleware-manager,crowdsec,crowdsec-manager,mcpauth"

    # Add static-page if STATIC_PAGE_SUBDOMAIN is provided
    if [[ -n "${STATIC_PAGE_SUBDOMAIN:-}" ]]; then
      echo "[orchestrator] Adding static-page (STATIC_PAGE_SUBDOMAIN is set)"
      COMPONENTS_RAW="$COMPONENTS_RAW,static-page"
    fi
  elif [[ -n "${NEMOCLAW_PROVIDER:-}" && -n "${NEMOCLAW_MODEL:-}" && -n "${NEMOCLAW_INFERENCE_API_KEY:-}" ]]; then
    echo "[orchestrator] Detected NemoClaw platform (NEMOCLAW_PROVIDER, NEMOCLAW_MODEL, NEMOCLAW_INFERENCE_API_KEY are set)"
    COMPONENTS_RAW="nemoclaw"
  elif [[ -n "${OPENCLAW_PROVIDER:-}" && -n "${OPENCLAW_MODEL:-}" && -n "${OPENCLAW_INFERENCE_API_KEY:-}" ]]; then
    echo "[orchestrator] Detected OpenClaw platform (OPENLAW_PROVIDER, OPENCLAW_MODEL, OPENCLAW_INFERENCE_API_KEY are set)"
    COMPONENTS_RAW="openclaw"
  elif [[ -n "${HERMES_DOMAIN:-}" && -n "${HERMES_AUTH_PASSWORD_HASH:-}" ]]; then
    echo "[orchestrator] Detected Hermes Agent platform (HERMES_DOMAIN and HERMES_AUTH_PASSWORD_HASH are set)"
    COMPONENTS_RAW="hermes-agent"
  elif [[ -n "${OPENAI_API_KEY:-}" && -n "${WORKFLOW_ID:-}" && -z "${ADMIN_USERNAME:-}" ]]; then
    echo "[orchestrator] Detected OpenAI Chatkit platform (OPENAI_API_KEY and WORKFLOW_ID are set, no Pangolin admin)"
    COMPONENTS_RAW="openai-chatkit"
  elif [[ -n "${DOMAIN:-}" && -n "${EMAIL:-}" ]]; then
    echo "[orchestrator] Detected Pangolin platform (DOMAIN and EMAIL are set)"
    COMPONENTS_RAW="pangolin,middleware-manager"
  else
    echo "[orchestrator] ERROR: Could not detect platform. Please provide either:"
    echo "  - For Pangolin: DOMAIN and EMAIL"
    echo "  - For Coolify: Any Coolify environment variables (or COMPONENTS=coolify)"
    echo "  - For OpenAI Chatkit: DOMAIN, EMAIL, OPENAI_API_KEY, and WORKFLOW_ID"
    echo "  - For NemoClaw: NEMOCLAW_PROVIDER, NEMOCLAW_MODEL, and NEMOCLAW_INFERENCE_API_KEY"
    echo "  - Or specify COMPONENTS explicitly"
    exit 1
  fi

  # Add optional components based on environment variables
  if [[ -n "${CROWDSEC_ENROLLMENT_KEY:-}" ]]; then
    echo "[orchestrator] Adding crowdsec (CROWDSEC_ENROLLMENT_KEY is set)"
    if [[ "$COMPONENTS_RAW" != *"crowdsec"* ]]; then
      COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec"
    fi
  fi
  if [[ -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]] || [[ -n "${PROVIDER:-}" ]]; then
    echo "[orchestrator] Adding mcpauth (CLIENT_ID/CLIENT_SECRET or PROVIDER is set)"
    if [[ "$COMPONENTS_RAW" != *"mcpauth"* ]]; then
      COMPONENTS_RAW="$COMPONENTS_RAW,mcpauth"
    fi
  fi
  # Only add nlweb if we're not in openai-chatkit or agentgateway mode
  if [[ -n "${OPENAI_API_KEY:-}" || -n "${AZURE_OPENAI_API_KEY:-}" || -n "${ANTHROPIC_API_KEY:-}" || -n "${GEMINI_API_KEY:-}" ]]; then
    if [[ "$COMPONENTS_RAW" != "openai-chatkit" && "$COMPONENTS_RAW" != *"agentgateway"* ]]; then
      echo "[orchestrator] Adding nlweb (AI_API_KEY is set)"
      COMPONENTS_RAW="$COMPONENTS_RAW,nlweb"
    fi
  fi
  if [[ -n "${KOMODO_HOST_IP:-}" ]]; then
    echo "[orchestrator] Adding komodo (KOMODO_HOST_IP is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,komodo"
  fi

  # Only add these components if not already handled by AgentGateway auto-detection
  if [[ "$COMPONENTS_RAW" != *"agentgateway"* ]]; then
    if [[ -n "${STATIC_PAGE_SUBDOMAIN:-}" ]]; then
      echo "[orchestrator] Adding static-page (STATIC_PAGE_SUBDOMAIN is set)"
      COMPONENTS_RAW="$COMPONENTS_RAW,static-page"
    fi
  fi

  echo "[orchestrator] Auto-derived COMPONENTS: $COMPONENTS_RAW"
else
  echo "[orchestrator] Using explicitly provided COMPONENTS: $COMPONENTS_RAW"
fi

# Handle explicit agentgateway specification by adding companion components
if [[ "$COMPONENTS_RAW" == "agentgateway" || "$COMPONENTS_RAW" == *",agentgateway"* || "$COMPONENTS_RAW" == *"agentgateway,"* ]]; then
  echo "[orchestrator] AgentGateway detected in explicit components - adding companion components"

  # Add core companion components if not already present
  if [[ "$COMPONENTS_RAW" != *"middleware-manager"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,middleware-manager"
  fi
  if [[ "$COMPONENTS_RAW" != *"crowdsec"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec"
  fi
  if [[ "$COMPONENTS_RAW" != *"mcpauth"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,mcpauth"
  fi

  # Add conditional components based on environment variables
  if [[ "$COMPONENTS_RAW" != *"crowdsec-manager"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec-manager"
  fi
  if [[ -n "${STATIC_PAGE_SUBDOMAIN:-}" && "$COMPONENTS_RAW" != *"static-page"* ]]; then
    echo "[orchestrator] Adding static-page (STATIC_PAGE_SUBDOMAIN is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,static-page"
  fi

  echo "[orchestrator] Updated COMPONENTS for AgentGateway: $COMPONENTS_RAW"
fi

# Handle openai-chatkit + pangolin combinations by converting to agentgateway
if [[ "$COMPONENTS_RAW" == *"openai-chatkit"* && ("$COMPONENTS_RAW" == *"pangolin"* || "$COMPONENTS_RAW" == *"middleware-manager"*) ]]; then
  echo "[orchestrator] openai-chatkit detected with pangolin components - converting to agentgateway mode"

  # Replace openai-chatkit with agentgateway in the components list
  COMPONENTS_RAW=$(echo "$COMPONENTS_RAW" | sed 's/openai-chatkit/agentgateway/')

  # Ensure core companion components are present
  if [[ "$COMPONENTS_RAW" != *"middleware-manager"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,middleware-manager"
  fi
  if [[ "$COMPONENTS_RAW" != *"crowdsec"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec"
  fi
  if [[ "$COMPONENTS_RAW" != *"mcpauth"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,mcpauth"
  fi

  echo "[orchestrator] Updated COMPONENTS for AgentGateway (from openai-chatkit): $COMPONENTS_RAW"
fi

# Handle platform+ aliases by adding required components (applies to both auto-derived and explicit components)
if [[ "$COMPONENTS_RAW" == *"pangolin+"* ]]; then
  echo "[orchestrator] pangolin+ detected - ensuring crowdsec is included"
  if [[ "$COMPONENTS_RAW" != *"crowdsec"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec"
  fi
fi
if [[ "$COMPONENTS_RAW" == *"coolify+"* ]]; then
  echo "[orchestrator] coolify+ detected - ensuring crowdsec is included"
  if [[ "$COMPONENTS_RAW" != *"crowdsec"* ]]; then
    COMPONENTS_RAW="$COMPONENTS_RAW,crowdsec"
  fi
fi

IFS="," read -r -a COMPONENTS_ARR <<< "$COMPONENTS_RAW"

# Helpers
has_component() {
  local c="$1"
  for x in "${COMPONENTS_ARR[@]}"; do
    # Handle pangolin+ as alias for pangolin
    if [[ "$c" == "pangolin" && ("$x" == "pangolin" || "$x" == "pangolin+") ]]; then
      return 0
    # Handle coolify+ as alias for coolify
    elif [[ "$c" == "coolify" && ("$x" == "coolify" || "$x" == "coolify+") ]]; then
      return 0
    elif [[ "$x" == "$c" ]]; then
      return 0
    fi
  done
  return 1
}

# Detect base platform from components
detect_base_platform() {
  if has_component "coolify"; then
    echo "coolify"
  elif has_component "nemoclaw"; then
    echo "nemoclaw"
  elif has_component "openclaw"; then
    echo "openclaw"
  elif has_component "hermes-agent"; then
    echo "hermes-agent"
  elif has_component "opencomputer"; then
    echo "opencomputer"
  elif has_component "agentgateway"; then
    echo "agentgateway"
  elif has_component "openai-chatkit" && (has_component "pangolin" || has_component "middleware-manager"); then
    # If openai-chatkit is specified alongside pangolin components, use agentgateway
    echo "agentgateway"
  elif has_component "pangolin"; then
    echo "pangolin"
  elif has_component "openai-chatkit"; then
    echo "openai-chatkit"
  else
    # Auto-detect based on environment variables
    if [[ -n "${DB_USERNAME:-}" && -n "${REDIS_PASSWORD:-}" && -n "${PUSHER_APP_ID:-}" ]]; then
      echo "coolify"
    elif [[ -n "${NEMOCLAW_PROVIDER:-}" && -n "${NEMOCLAW_MODEL:-}" ]]; then
      echo "nemoclaw"
    elif [[ -n "${OPENCLAW_PROVIDER:-}" && -n "${OPENCLAW_MODEL:-}" ]]; then
      echo "openclaw"
    elif [[ -n "${HERMES_DOMAIN:-}" && -n "${HERMES_AUTH_PASSWORD_HASH:-}" ]]; then
      echo "hermes-agent"
    elif [[ -n "${OC_DOMAIN:-}" && -n "${OC_AUTH_PASSWORD_HASH:-}" ]]; then
      echo "opencomputer"
    elif [[ -n "${OPENAI_API_KEY:-}" && -n "${WORKFLOW_ID:-}" && -n "${ADMIN_USERNAME:-}" && -n "${ADMIN_PASSWORD:-}" ]]; then
      echo "agentgateway"
    elif [[ -n "${OPENAI_API_KEY:-}" && -n "${WORKFLOW_ID:-}" && -z "${ADMIN_USERNAME:-}" ]]; then
      echo "openai-chatkit"
    elif [[ -n "${DOMAIN:-}" && -n "${EMAIL:-}" ]]; then
      echo "pangolin"
    else
      echo "unknown"
    fi
  fi
}

BASE_PLATFORM=$(detect_base_platform)

echo "[orchestrator] Detected base platform: ${BASE_PLATFORM}"
echo "[orchestrator] Using components: ${COMPONENTS_RAW}"
echo "[orchestrator] Output dir: ${OUTPUT_DIR}"

# Validate base platform
if [[ "$BASE_PLATFORM" == "unknown" ]]; then
  echo "[orchestrator] ERROR: Could not detect base platform. Please specify COMPONENTS with 'pangolin', 'agentgateway', 'coolify', or 'openai-chatkit', or provide appropriate environment variables."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# --- Build compose.yaml ---
compose_out="$OUTPUT_DIR/compose.yaml"
{
  # Add Coolify-specific comments before services section
  if [[ "$BASE_PLATFORM" == "coolify" ]]; then
    cat <<'EOF'
# Coolify Platform Docker Compose Configuration
#
# 🚨 IMPORTANT SERVER PREREQUISITES:
# Before running 'docker compose up -d', you MUST complete these steps on your server:
#
# 1. Create Directories:
#    mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
#    mkdir -p /data/coolify/ssh/{keys,mux}
#    mkdir -p /data/coolify/proxy/dynamic
#
# 2. Generate & Add SSH Key:
#    ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify
#    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
#    chmod 600 ~/.ssh/authorized_keys
#
# 3. Set Permissions:
#    chown -R 9999:root /data/coolify
#    chmod -R 700 /data/coolify
#
# 4. Create Docker Network:
#    docker network create --attachable coolify
#
# 📋 Environment Variables:
# Copy .env.coolify.example to .env and configure your values.
# Missing values will be auto-generated during setup.
#
# 📚 Official Coolify Manual Installation Guide:
# https://coolify.io/docs/installation#manual

services:
EOF
  elif [[ "$BASE_PLATFORM" == "openclaw" ]]; then
    cat <<EOF
# OpenClaw Standalone Docker Compose Configuration
#
# 🚨 IMPORTANT SERVER PREREQUISITES:
# This compose stack ONLY brings up the Traefik reverse-proxy. The OpenClaw
# gateway runs as a HOST systemd service (not in Docker). You MUST complete
# these steps on your server BEFORE running 'docker compose up -d'.
# See PREREQUISITES_OPENCLAW.md (generated alongside this file) for the
# step-by-step copy-paste commands. Summary:
#
# 1. curl -fsSL https://openclaw.ai/install.sh | bash
# 2. openclaw gateway install --force
# 3. openclaw config set gateway.auth.token "\${OPENCLAW_AUTH_TOKEN}"
#    + provider/model/API key (see PREREQUISITES_OPENCLAW.md)
# 4. Create /etc/systemd/system/openclaw-gateway.service
#    (template in PREREQUISITES_OPENCLAW.md) + enable/start it
# 5. Verify: systemctl is-active openclaw-gateway && curl http://127.0.0.1:18789/
#
# 📋 Then run 'docker compose up -d' to start Traefik (this file).
# 🔗 Access: https://\${OPENCLAW_SUBDOMAIN}.\${OPENCLAW_DOMAIN}/#token=\${OPENCLAW_AUTH_TOKEN}
# 📚 OpenClaw docs: https://openclaw.ai/docs

services:
EOF
  elif [[ "$BASE_PLATFORM" == "hermes-agent" ]]; then
    cat <<EOF
# Hermes Agent Standalone Docker Compose Configuration
#
# 🚨 IMPORTANT SERVER PREREQUISITES:
# This compose stack ONLY brings up the Traefik reverse-proxy (TLS termination).
# The Hermes dashboard runs as a HOST systemd service (not in Docker) and now
# authenticates users itself via Hermes' built-in \`basic\` dashboard-auth provider —
# there is NO Traefik basic-auth middleware. You MUST complete these steps on your
# server BEFORE running 'docker compose up -d'. See PREREQUISITES_HERMES.md (generated
# alongside this file) for the step-by-step copy-paste commands. Summary:
#
# 1. sudo apt install -y git curl ca-certificates ufw
# 2. curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
# 3. /usr/local/lib/hermes-agent/venv/bin/pip install 'hermes-agent[web,pty]' ptyprocess
# 4. Configure ~/.hermes/.env (API key) + hermes config set model.provider/default
# 5. Add the built-in dashboard auth to ~/.hermes/.env (Hermes reads these directly):
#      HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
#      HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<YOUR_PASSWORD>
#      HERMES_DASHBOARD_BASIC_AUTH_SECRET=<32+ random bytes>   # keeps sessions across restarts
# 6. Create /etc/systemd/system/hermes-dashboard.service (template in
#    PREREQUISITES_HERMES.md) and start it: --host 0.0.0.0 --no-open
#    (0.0.0.0 is REQUIRED — Hermes only engages its auth gate on a non-loopback bind)
# 7. FIREWALL: \`ufw deny 9119/tcp\` — port 9119 MUST NOT be exposed publicly
#    (only Traefik on localhost should reach it)
# 8. Verify: systemctl is-active hermes-dashboard && curl http://127.0.0.1:9119/
#
# 📋 Then run 'docker compose up -d' to start Traefik (this file).
# 🔗 Access: https://\${HERMES_SUBDOMAIN}.\${HERMES_DOMAIN} (Hermes shows a login page — use admin + your password)
# 📚 Hermes docs: https://hermes-agent.nousresearch.com/docs

services:
EOF
  else
    echo "services:"
  fi

  # Base platform services
  if [[ "$BASE_PLATFORM" == "pangolin" ]]; then
    # Pangolin platform (includes pangolin + gerbil + traefik)
    sed -n '1,9999p' "$ROOT_DIR/components/pangolin/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "agentgateway" ]]; then
    # AgentGateway platform (Pangolin-based with chatkit-embed)
    sed -n '1,9999p' "$ROOT_DIR/components/agentgateway/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    # Coolify platform
    sed -n '1,9999p' "$ROOT_DIR/components/coolify/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "openai-chatkit" ]]; then
    # OpenAI Chatkit platform (standalone with traefik)
    sed -n '1,9999p' "$ROOT_DIR/components/openai-chatkit/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "nemoclaw" ]]; then
    # NemoClaw platform (Traefik proxy to OpenShell sandbox)
    sed -n '1,9999p' "$ROOT_DIR/components/nemoclaw/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "openclaw" ]]; then
    # OpenClaw platform (Traefik proxy to host service)
    sed -n '1,9999p' "$ROOT_DIR/components/openclaw/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "hermes-agent" ]]; then
    # Hermes Agent platform (Traefik proxy to host dashboard with basic-auth)
    sed -n '1,9999p' "$ROOT_DIR/components/hermes-agent/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "opencomputer" ]]; then
    # OpenComputer platform (Traefik proxy to host agent dashboard with basic-auth)
    sed -n '1,9999p' "$ROOT_DIR/components/opencomputer/compose.yaml"
  fi

  # Optional components (platform-agnostic)
  if has_component middleware-manager; then sed -n '1,9999p' "$ROOT_DIR/components/middleware-manager/compose.yaml"; fi
  if has_component static-page; then sed -n '1,9999p' "$ROOT_DIR/components/static-page/compose.yaml"; fi
  if has_component crowdsec-manager; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec-manager/compose.yaml"; fi

  # MCPAuth with conditional configuration based on PROVIDER
  if has_component mcpauth; then
    if [[ "${PROVIDER:-}" == "keycloak" ]]; then
      echo "[orchestrator] Using mcpauth with Keycloak IdP" >&2
      sed -n '1,9999p' "$ROOT_DIR/components/mcpauth/compose-keycloak.yaml"
    elif [[ -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]]; then
      echo "[orchestrator] Using mcpauth with Google OAuth (CLIENT_ID and CLIENT_SECRET are set)" >&2
      sed -n '1,9999p' "$ROOT_DIR/components/mcpauth/compose.yaml"
    else
      echo "[orchestrator] Using mcpauth with internal OAuth" >&2
      sed -n '1,9999p' "$ROOT_DIR/components/mcpauth/compose-internal.yaml"
    fi
  fi

  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/compose.yaml"; fi
  if has_component nlweb; then sed -n '1,9999p' "$ROOT_DIR/components/nlweb/compose.yaml"; fi
  if has_component mcp-gateway; then sed -n '1,9999p' "$ROOT_DIR/components/mcp-gateway/compose.yaml"; fi
  if has_component openshell; then sed -n '1,9999p' "$ROOT_DIR/components/openshell/compose.yaml"; fi
  # Note: komodo component has been removed from all deployments

  # Add backup service if MAX_BACKUPS is set and greater than 0
  if [[ -n "${MAX_BACKUPS:-}" && "${MAX_BACKUPS:-0}" -gt 0 ]]; then
    # Derive deployment name from the host directory
    # Method 1: Try to get from HOST_PWD environment variable (if passed)
    if [[ -n "${HOST_PWD:-}" ]]; then
      current_dir=$(basename "$HOST_PWD")
    else
      # Method 2: Try to extract from mount info or use a fallback
      # Check if we can get the host path from /proc/mounts
      host_mount=$(grep "/host-setup" /proc/mounts 2>/dev/null | head -1 | awk '{print $1}')
      if [[ -n "$host_mount" && "$host_mount" != "." ]]; then
        current_dir=$(basename "$host_mount")
      else
        # Method 3: Fallback - use a generic name and warn
        current_dir="manidae-deployment"
        echo "Warning: Could not determine deployment name, using fallback: $current_dir"
      fi
    fi

    if [[ "$current_dir" == *"_setup-stack" ]]; then
      # Extract deployment name from folder like "test-326962_setup-stack"
      DEPLOYMENT_NAME="${current_dir%_setup-stack}"
    else
      # If not in a _setup-stack folder, use the directory name as deployment name
      DEPLOYMENT_NAME="$current_dir"
    fi

    # Always use the standard Komodo path structure for production deployments
    FULL_STACK_PATH="/etc/komodo/stacks/${DEPLOYMENT_NAME}_setup-stack"

    echo "  backup-job:"
    echo "    image: oideibrett/manidae-backup:latest"
    echo "    restart: unless-stopped"
    echo "    env_file:"
    echo "      - ./.env  # Load SSH_PRIVATE_KEY and other variables"
    echo "    environment:"
    # REPO_URL: prefer BACKUP_REPO_URL from .env (set by manidae-cloud, knows the org slug);
    # fall back to a name built from the local dir if not provided (e.g. BYOVPS without an org).
    REPO_URL_VALUE="${BACKUP_REPO_URL:-git@github.com:ManidaeCloud/${DEPLOYMENT_NAME}_syncresources.git}"
    echo "      # Repository configuration"
    echo "      - REPO_URL=${REPO_URL_VALUE}"
    echo "      - BACKUP_SOURCE_PATH=${FULL_STACK_PATH}/config"
    echo "      - BACKUP_MODE=backup"
    echo "      - GIT_USER_NAME=Backup Bot"
    echo "      - GIT_USER_EMAIL=backup@\${DOMAIN:-contextware.ai}"
    echo "      # Backup configuration"
    echo "      - MAX_BACKUPS=\${MAX_BACKUPS}"
    # Per-agent: bind the host config path read-only and let backup-helper.sh
    # stage them into config/{agent}-config/ at the start of each daily cycle.
    # Pangolin/Coolify already write their configs directly into config/, so no
    # extra mount is needed for them. Only drop the stack-dir :ro flag if we
    # actually need to stage anything into config/.
    agent_mounts=""
    needs_docker_cli=false
    if has_component openclaw; then
      agent_mounts="${agent_mounts}      - /root/.openclaw:/agent-src/openclaw:ro\n"
    fi
    if has_component hermes-agent; then
      agent_mounts="${agent_mounts}      - /root/.hermes:/agent-src/hermes:ro\n"
    fi
    if has_component nemoclaw || has_component agentgateway; then
      agent_mounts="${agent_mounts}      - /root/.nemoclaw:/agent-src/nemoclaw:ro\n"
      # OpenShell sandboxes run OpenClaw/Hermes inside Docker containers named
      # openshell-{sandbox-name}-{uuid}. Real agent config is at /sandbox/.openclaw
      # and /sandbox/.hermes inside each container. backup-helper.sh shells into
      # each container via docker.sock and docker cp's the contents out.
      agent_mounts="${agent_mounts}      - /var/run/docker.sock:/var/run/docker.sock:ro\n"
      needs_docker_cli=true
    fi
    if has_component agentgateway; then
      # /opt/openshell-controller is the Next.js clone (~850MB with node_modules);
      # only .env.local + .runtime/ are real user state.
      agent_mounts="${agent_mounts}      - /opt/openshell-controller:/agent-src/openshell-controller:ro\n"
    fi

    echo "    volumes:"
    if [ -n "$agent_mounts" ]; then
      # Writable so backup-helper.sh can stage agent configs into config/
      echo "      - ${FULL_STACK_PATH}:${FULL_STACK_PATH}"
      printf "%b" "$agent_mounts"
    else
      # Pangolin/Coolify-only — backup-job is read-only
      echo "      - ${FULL_STACK_PATH}:${FULL_STACK_PATH}:ro"
    fi

    # The orchestration logic lives in backup-helper.sh (written below). Keeping
    # it out of compose.yaml dodges the envsubst pass that eats shell `$VAR`
    # references and breaks the per-sandbox docker-cp loop.
    echo "    command: [\"/bin/sh\", \"${FULL_STACK_PATH}/backup-helper.sh\"]"
    echo "    healthcheck:"
    echo "      test: [\"CMD\", \"pgrep\", \"-f\", \"backup_script.sh\"]"
    echo "      interval: 30s"
    echo "      timeout: 10s"
    echo "      retries: 3"
    echo "      start_period: 10s"
    echo "    logging:"
    echo "      driver: \"json-file\""
    echo "      options:"
    echo "        max-size: \"10m\""
    echo "        max-file: \"3\""
    echo ""
  fi

  # Volumes (platform and component specific)
  volumes_needed=false
  if [[ "$BASE_PLATFORM" == "coolify" ]]; then volumes_needed=true; fi
  if has_component nlweb; then volumes_needed=true; fi
  if has_component mcp-gateway; then volumes_needed=true; fi
  if has_component openshell; then volumes_needed=true; fi

  if [[ "$volumes_needed" == "true" ]]; then
    echo "volumes:"
    if [[ "$BASE_PLATFORM" == "coolify" ]]; then sed -n '1,9999p' "$ROOT_DIR/components/coolify/volumes.yaml"; fi
    if has_component nlweb; then sed -n '1,9999p' "$ROOT_DIR/components/nlweb/volumes.yaml"; fi
    if has_component mcp-gateway; then sed -n '1,9999p' "$ROOT_DIR/components/mcp-gateway/volumes.yaml"; fi
    if has_component openshell; then sed -n '1,9999p' "$ROOT_DIR/components/openshell/volumes.yaml"; fi
    # Note: komodo volumes have been removed from all deployments
  fi

  # Networks (generic for all platforms)
  if [[ "$BASE_PLATFORM" == "pangolin" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    #external: true
    name: manidae
    enable_ipv6: true
EOF
  elif [[ "$BASE_PLATFORM" == "agentgateway" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    #external: true
    name: agentgateway
    enable_ipv6: true
EOF
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    cat <<'EOF'
networks:
  coolify:
    name: coolify
    driver: bridge
    external: true
EOF
  elif [[ "$BASE_PLATFORM" == "nemoclaw" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    name: nemoclaw
EOF
  elif [[ "$BASE_PLATFORM" == "openai-chatkit" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    name: chatkit
EOF
  elif [[ "$BASE_PLATFORM" == "openclaw" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    name: openclaw
EOF
  elif [[ "$BASE_PLATFORM" == "hermes-agent" ]]; then
    cat <<'EOF'
networks:
  default:
    driver: bridge
    name: hermes-agent
EOF
  fi
} > "$compose_out"

echo "[orchestrator] Wrote $compose_out"

# --- Build backup-helper.sh (only when MAX_BACKUPS > 0) ---
# Lives outside compose.yaml so the envsubst pass (which mangles $VAR
# references and breaks the per-sandbox docker-cp loop) doesn't touch it.
# Mounted into backup-job at FULL_STACK_PATH (same path on host and container).
if [[ -n "${MAX_BACKUPS:-}" && "${MAX_BACKUPS:-0}" -gt 0 ]]; then
  helper_out="$OUTPUT_DIR/backup-helper.sh"
  if [[ -n "${HOST_PWD:-}" ]]; then
    helper_dir=$(basename "$HOST_PWD")
  else
    helper_dir="manidae-deployment_setup-stack"
  fi
  if [[ "$helper_dir" == *"_setup-stack" ]]; then
    HELPER_DEPLOY_NAME="${helper_dir%_setup-stack}"
  else
    HELPER_DEPLOY_NAME="$helper_dir"
  fi
  HELPER_STACK_PATH="/etc/komodo/stacks/${HELPER_DEPLOY_NAME}_setup-stack"
  cat > "$helper_out" <<HELPER_EOF
#!/bin/sh
# Generated by build-compose.sh. Runs inside the backup-job container.
# Stages host/sandbox agent configs into config/ then invokes backup_script.sh.
set -u
STACK_DIR="${HELPER_STACK_PATH}"
CONFIG_DIR="\${STACK_DIR}/config"

# Alpine image has tar but not docker — install on first run so we can reach
# inside OpenShell sandbox containers below. No-op if docker is already there
# (e.g. base image gains it later).
command -v docker >/dev/null 2>&1 || apk add --no-cache docker-cli >/dev/null 2>&1 || true

stage_dir() {
  src="\$1"
  dst="\$2"
  if [ -d "\$src" ]; then
    mkdir -p "\$dst" 2>/dev/null
    # Use tar to copy everything EXCEPT 'node' and 'node_modules' directories
    tar -C "\$src" --exclude="node" --exclude="node_modules" -cf - . | tar -C "\$dst" -xf - 2>/dev/null || true
  fi
}

while true; do
  echo "Running backup at \$(date)"

  # 1) Host agent dirs — only the mounted ones will be present.
  stage_dir /agent-src/openclaw "\${CONFIG_DIR}/openclaw-config"
  stage_dir /agent-src/hermes   "\${CONFIG_DIR}/hermes-config"
  stage_dir /agent-src/nemoclaw "\${CONFIG_DIR}/nemoclaw-config"

  # 2) openshell-controller — narrow to user state, skip node_modules/source.
  if [ -d /agent-src/openshell-controller ]; then
    mkdir -p "\${CONFIG_DIR}/openshell-controller-config" 2>/dev/null
    cp /agent-src/openshell-controller/.env.local "\${CONFIG_DIR}/openshell-controller-config/" 2>/dev/null || true
    cp -a /agent-src/openshell-controller/.runtime "\${CONFIG_DIR}/openshell-controller-config/" 2>/dev/null || true
  fi

  # 3) Per-sandbox configs — OpenClaw/Hermes running inside openshell-{name}-{uuid}.
  if [ -S /var/run/docker.sock ] && command -v docker >/dev/null 2>&1; then
    for c in \$(docker ps --filter 'name=^openshell-' --format '{{.Names}}' 2>/dev/null); do
      n=\${c#openshell-}
      n=\${n%-????????-????-????-????-????????????}
      for a in openclaw hermes; do
        if docker exec "\$c" test -d "/sandbox/.\$a" 2>/dev/null; then
          mkdir -p "\${CONFIG_DIR}/sandbox-\$a-\$n" 2>/dev/null
          docker cp "\$c:/sandbox/.\$a/." "\${CONFIG_DIR}/sandbox-\$a-\$n/" 2>/dev/null || true
        fi
      done
    done
  fi

  # Strip nested git repos from the staged config before backing up. OpenClaw (and
  # agent workspaces) initialise their workspace as a git repo; a nested .git makes
  # the backup repo's "git add ." abort with "does not have a commit checked out",
  # silently skipping the commit/push so no backup is ever pushed. We only need the
  # working files, not the workspace's own git history.
  find "\${CONFIG_DIR}" -mindepth 2 -type d -name .git -prune -exec rm -rf {} + 2>/dev/null || true

  /usr/local/bin/backup_script.sh
  echo "Backup completed. Sleeping for 1 day ..."
  sleep 86400
done
HELPER_EOF
  chmod +x "$helper_out"
  echo "[orchestrator] Wrote $helper_out"
fi

# --- Build container-setup.sh (copy if present; fallback generate if missing/empty) ---
setup_out="$OUTPUT_DIR/container-setup.sh"
setup_src="$ROOT_DIR/container-setup.sh"

# Always regenerate container-setup.sh when platform+ aliases are used to ensure proper handling
if [[ "$COMPONENTS_RAW" == *"+"* ]]; then
  echo "[orchestrator] Platform+ alias detected; generating container-setup.sh with proper alias handling"
  cat > "$setup_out" <<EOF
#!/bin/sh
set -e
ROOT_HOST_DIR="\${ROOT_HOST_DIR:-/host-setup}"
COMPONENTS_CSV="$COMPONENTS_RAW"
export COMPONENTS_CSV

# Export environment variables for component scripts
export DOMAIN="\${DOMAIN:-}"
export EMAIL="\${EMAIL:-}"
export OPENAI_API_KEY="\${OPENAI_API_KEY:-}"
export WORKFLOW_ID="\${WORKFLOW_ID:-}"
export ADMIN_USERNAME="\${ADMIN_USERNAME:-}"
export ADMIN_PASSWORD="\${ADMIN_PASSWORD:-}"
export CHATKIT_SUBDOMAIN="\${CHATKIT_SUBDOMAIN:-}"
export TRAEFIK_SUBDOMAIN="\${TRAEFIK_SUBDOMAIN:-}"
export LOGS_SUBDOMAIN="\${LOGS_SUBDOMAIN:-}"
export STATIC_PAGE_SUBDOMAIN="\${STATIC_PAGE_SUBDOMAIN:-}"
export MAIN_STACK_PREFIX="\${MAIN_STACK_PREFIX:-}"
export CLIENT_ID="\${CLIENT_ID:-}"
export CLIENT_SECRET="\${CLIENT_SECRET:-}"
export OAUTH_DOMAIN="\${OAUTH_DOMAIN:-}"
export NEMOCLAW_PROVIDER="\${NEMOCLAW_PROVIDER:-}"
export NEMOCLAW_MODEL="\${NEMOCLAW_MODEL:-}"
export NEMOCLAW_INFERENCE_API_KEY="\${NEMOCLAW_INFERENCE_API_KEY:-}"
export NEMOCLAW_INFERENCE_BASE_URL="\${NEMOCLAW_INFERENCE_BASE_URL:-}"
export NEMOCLAW_INFERENCE_API="\${NEMOCLAW_INFERENCE_API:-}"
export NEMOCLAW_SUBDOMAIN="\${NEMOCLAW_SUBDOMAIN:-}"
export NEMOCLAW_DOMAIN="\${NEMOCLAW_DOMAIN:-nemoclaw.dpdns.org}"
export NEMOCLAW_AUTH_TOKEN="\${NEMOCLAW_AUTH_TOKEN:-}"
export NEMOCLAW_AGENT="\${NEMOCLAW_AGENT:-openclaw}"
export TELEGRAM_BOT_TOKEN="\${TELEGRAM_BOT_TOKEN:-}"
export TELEGRAM_USER_ID="\${TELEGRAM_USER_ID:-}"
export DISCORD_BOT_TOKEN="\${DISCORD_BOT_TOKEN:-}"
export SLACK_BOT_TOKEN="\${SLACK_BOT_TOKEN:-}"
export BRAVE_API_KEY="\${BRAVE_API_KEY:-}"
export OPENSHELL_CONTROLLER_SUBDOMAIN="\${OPENSHELL_CONTROLLER_SUBDOMAIN:-}"
export HERMES_SUBDOMAIN="\${HERMES_SUBDOMAIN:-hermes}"
export HERMES_DOMAIN="\${HERMES_DOMAIN:-}"
export HERMES_AUTH_USER="\${HERMES_AUTH_USER:-admin}"
export HERMES_AUTH_PASSWORD_HASH="\${HERMES_AUTH_PASSWORD_HASH:-}"
export OC_SUBDOMAIN="\${OC_SUBDOMAIN:-computer}"
export OC_DOMAIN="\${OC_DOMAIN:-}"
export OC_AUTH_USER="\${OC_AUTH_USER:-admin}"
export OC_AUTH_PASSWORD_HASH="\${OC_AUTH_PASSWORD_HASH:-}"

log() { printf "%s\n" "\$*"; }
run_component_hooks() {
  comps_csv="\${COMPONENTS_CSV}"
  # Core-shared functionality is now integrated into platform-specific components
  # POSIX sh split (BusyBox ash compatible)
  old_ifs="\$IFS"; IFS=','; set -- \$comps_csv; IFS="\$old_ifs"
  for c in "\$@"; do
    [ -z "\$c" ] && continue
    # Handle pangolin+ as alias for pangolin
    # Handle coolify+ as alias for coolify
    component_dir="\$c"
    if [ "\$c" = "pangolin+" ]; then
      component_dir="pangolin"
    elif [ "\$c" = "coolify+" ]; then
      component_dir="coolify"
    fi
    if [ -f "\${MANIDAE_ROOT:-\$ROOT_HOST_DIR}/components/\${component_dir}/config-setup.sh" ]; then
      /bin/sh "\${MANIDAE_ROOT:-\$ROOT_HOST_DIR}/components/\${component_dir}/config-setup.sh" || true
    fi
  done
}
run_component_hooks
EOF
elif [ -s "$setup_src" ]; then
  if [ "$setup_src" = "$setup_out" ]; then
    tmp_file="$(mktemp)"
    sed -n '1,9999p' "$setup_src" > "$tmp_file"
    # Update COMPONENTS_CSV with the current COMPONENTS_RAW
    sed -i "s/^COMPONENTS_CSV=.*/COMPONENTS_CSV=\"$COMPONENTS_RAW\"/" "$tmp_file"
    cat "$tmp_file" > "$setup_out"
    rm -f "$tmp_file"
  else
    # Copy and update COMPONENTS_CSV with the current COMPONENTS_RAW
    sed "s/^COMPONENTS_CSV=.*/COMPONENTS_CSV=\"$COMPONENTS_RAW\"/" "$setup_src" > "$setup_out"
  fi
else
  echo "[orchestrator] Source container-setup.sh missing or empty; generating default"
  cat > "$setup_out" <<EOF
#!/bin/sh
set -e
ROOT_HOST_DIR="\${ROOT_HOST_DIR:-/host-setup}"
COMPONENTS_CSV="$COMPONENTS_RAW"
export COMPONENTS_CSV

# Export environment variables for component scripts
export DOMAIN="\${DOMAIN:-}"
export EMAIL="\${EMAIL:-}"
export OPENAI_API_KEY="\${OPENAI_API_KEY:-}"
export WORKFLOW_ID="\${WORKFLOW_ID:-}"
export ADMIN_USERNAME="\${ADMIN_USERNAME:-}"
export ADMIN_PASSWORD="\${ADMIN_PASSWORD:-}"
export CHATKIT_SUBDOMAIN="\${CHATKIT_SUBDOMAIN:-}"
export TRAEFIK_SUBDOMAIN="\${TRAEFIK_SUBDOMAIN:-}"
export LOGS_SUBDOMAIN="\${LOGS_SUBDOMAIN:-}"
export STATIC_PAGE_SUBDOMAIN="\${STATIC_PAGE_SUBDOMAIN:-}"
export MAIN_STACK_PREFIX="\${MAIN_STACK_PREFIX:-}"
export CLIENT_ID="\${CLIENT_ID:-}"
export CLIENT_SECRET="\${CLIENT_SECRET:-}"
export OAUTH_DOMAIN="\${OAUTH_DOMAIN:-}"
export NEMOCLAW_PROVIDER="\${NEMOCLAW_PROVIDER:-}"
export NEMOCLAW_MODEL="\${NEMOCLAW_MODEL:-}"
export NEMOCLAW_INFERENCE_API_KEY="\${NEMOCLAW_INFERENCE_API_KEY:-}"
export NEMOCLAW_INFERENCE_BASE_URL="\${NEMOCLAW_INFERENCE_BASE_URL:-}"
export NEMOCLAW_INFERENCE_API="\${NEMOCLAW_INFERENCE_API:-}"
export NEMOCLAW_SUBDOMAIN="\${NEMOCLAW_SUBDOMAIN:-}"
export NEMOCLAW_DOMAIN="\${NEMOCLAW_DOMAIN:-nemoclaw.dpdns.org}"
export NEMOCLAW_AUTH_TOKEN="\${NEMOCLAW_AUTH_TOKEN:-}"
export NEMOCLAW_AGENT="\${NEMOCLAW_AGENT:-openclaw}"
export TELEGRAM_BOT_TOKEN="\${TELEGRAM_BOT_TOKEN:-}"
export TELEGRAM_USER_ID="\${TELEGRAM_USER_ID:-}"
export DISCORD_BOT_TOKEN="\${DISCORD_BOT_TOKEN:-}"
export SLACK_BOT_TOKEN="\${SLACK_BOT_TOKEN:-}"
export BRAVE_API_KEY="\${BRAVE_API_KEY:-}"
export OPENSHELL_CONTROLLER_SUBDOMAIN="\${OPENSHELL_CONTROLLER_SUBDOMAIN:-}"
export HERMES_SUBDOMAIN="\${HERMES_SUBDOMAIN:-hermes}"
export HERMES_DOMAIN="\${HERMES_DOMAIN:-}"
export HERMES_AUTH_USER="\${HERMES_AUTH_USER:-admin}"
export HERMES_AUTH_PASSWORD_HASH="\${HERMES_AUTH_PASSWORD_HASH:-}"
export OC_SUBDOMAIN="\${OC_SUBDOMAIN:-computer}"
export OC_DOMAIN="\${OC_DOMAIN:-}"
export OC_AUTH_USER="\${OC_AUTH_USER:-admin}"
export OC_AUTH_PASSWORD_HASH="\${OC_AUTH_PASSWORD_HASH:-}"

log() { printf "%s\n" "\$*"; }
run_component_hooks() {
  comps_csv="\${COMPONENTS_CSV}"
  # Core-shared functionality is now integrated into platform-specific components
  # POSIX sh split (BusyBox ash compatible)
  old_ifs="\$IFS"; IFS=','; set -- \$comps_csv; IFS="\$old_ifs"
  for c in "\$@"; do
    [ -z "\$c" ] && continue
    # Handle pangolin+ as alias for pangolin
    # Handle coolify+ as alias for coolify
    component_dir="\$c"
    if [ "\$c" = "pangolin+" ]; then
      component_dir="pangolin"
    elif [ "\$c" = "coolify+" ]; then
      component_dir="coolify"
    fi
    if [ -f "\${MANIDAE_ROOT:-\$ROOT_HOST_DIR}/components/\${component_dir}/config-setup.sh" ]; then
      /bin/sh "\${MANIDAE_ROOT:-\$ROOT_HOST_DIR}/components/\${component_dir}/config-setup.sh" || true
    fi
  done
}
run_component_hooks
EOF
fi
chmod +x "$setup_out"
echo "[orchestrator] Wrote $setup_out"

# --- Build DEPLOYMENT_INFO.txt from snippets ---
info_out="$OUTPUT_DIR/DEPLOYMENT_INFO.txt"
{
  # Base platform deployment info
  if [[ "$BASE_PLATFORM" == "pangolin" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/pangolin/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "agentgateway" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/agentgateway/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/coolify/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "openai-chatkit" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/openai-chatkit/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "nemoclaw" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/nemoclaw/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "openclaw" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/openclaw/deployment-info.txt"
  elif [[ "$BASE_PLATFORM" == "hermes-agent" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/hermes-agent/deployment-info.txt"
  fi

  # Component-specific deployment info
  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/deployment-info.txt"; fi
  # Future: append other components' deployment info as needed
} > "$info_out"
echo "[orchestrator] Wrote $info_out"

# --- BYOVPS prerequisite docs (host-installed agents) ---
# For openclaw / hermes-agent the actual agent runs natively on the host
# (curl-installer + systemd), not in Docker. BYOVPS users need step-by-step
# install instructions to copy alongside compose.yaml. Cloud-init paths
# handle this via the startup script — but those scripts never run on a
# user's own VPS, so we emit the same recipe as a markdown doc here.
if [[ "$BASE_PLATFORM" == "openclaw" && -f "$ROOT_DIR/components/openclaw/PREREQUISITES.md" ]]; then
  cp "$ROOT_DIR/components/openclaw/PREREQUISITES.md" "$OUTPUT_DIR/PREREQUISITES_OPENCLAW.md"
  echo "[orchestrator] Wrote $OUTPUT_DIR/PREREQUISITES_OPENCLAW.md"
elif [[ "$BASE_PLATFORM" == "hermes-agent" && -f "$ROOT_DIR/components/hermes-agent/PREREQUISITES.md" ]]; then
  cp "$ROOT_DIR/components/hermes-agent/PREREQUISITES.md" "$OUTPUT_DIR/PREREQUISITES_HERMES.md"
  echo "[orchestrator] Wrote $OUTPUT_DIR/PREREQUISITES_HERMES.md"
fi

# --- Execute setup script unless dry run ---
if [[ "${DRY_RUN:-}" != "1" ]]; then
  echo "[orchestrator] Executing $setup_out"
  # Execute from the output directory with proper environment
  (cd "$OUTPUT_DIR" && ROOT_HOST_DIR="." MANIDAE_ROOT="$ROOT_DIR" "./$(basename "$setup_out")")
else
  echo "[orchestrator] DRY_RUN=1 set; skipping execution."
fi

# --- Envsubst pass unless skipped ---
if [[ "${SKIP_ENVSUBST:-}" != "1" ]]; then
  # Only run envsubst on files that are not shell scripts
  command -v envsubst >/dev/null 2>&1 || { echo "[orchestrator] envsubst not found; skipping"; exit 0; }
  ENVSUBST_FILES=("$compose_out" "$info_out")
  [ -f "$OUTPUT_DIR/PREREQUISITES_OPENCLAW.md" ] && ENVSUBST_FILES+=("$OUTPUT_DIR/PREREQUISITES_OPENCLAW.md")
  [ -f "$OUTPUT_DIR/PREREQUISITES_HERMES.md" ]   && ENVSUBST_FILES+=("$OUTPUT_DIR/PREREQUISITES_HERMES.md")
  for f in "${ENVSUBST_FILES[@]}"; do
    tmp="$f.tmp"; envsubst < "$f" > "$tmp" && mv "$tmp" "$f"
  done
  echo "[orchestrator] Performed envsubst on outputs."
else
  echo "[orchestrator] SKIP_ENVSUBST=1 set; skipping envsubst."
fi

