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
  elif [[ -n "${DOMAIN:-}" && -n "${EMAIL:-}" ]]; then
    echo "[orchestrator] Detected Pangolin platform (DOMAIN and EMAIL are set)"
    COMPONENTS_RAW="pangolin,middleware-manager"
  else
    echo "[orchestrator] ERROR: Could not detect platform. Please provide either:"
    echo "  - For Pangolin: DOMAIN and EMAIL"
    echo "  - For Coolify: Any Coolify environment variables (or COMPONENTS=coolify)"
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
  if [[ -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]]; then
    echo "[orchestrator] Adding mcpauth (CLIENT_ID and CLIENT_SECRET are set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,mcpauth"
  fi
  if [[ -n "${OPENAI_API_KEY:-}" || -n "${AZURE_OPENAI_API_KEY:-}" || -n "${ANTHROPIC_API_KEY:-}" || -n "${GEMINI_API_KEY:-}" ]]; then
    echo "[orchestrator] Adding nlweb (AI_API_KEY is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,nlweb"
  fi
  if [[ -n "${KOMODO_HOST_IP:-}" ]]; then
    echo "[orchestrator] Adding komodo (KOMODO_HOST_IP is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,komodo"
  fi
  if [[ -n "${STATIC_PAGE_SUBDOMAIN:-}" ]]; then
    echo "[orchestrator] Adding static-page (STATIC_PAGE_SUBDOMAIN is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,static-page"
  fi
  if [[ -n "${MAXMIND_LICENSE_KEY:-}" ]]; then
    echo "[orchestrator] Adding traefik-log-dashboard (MAXMIND_LICENSE_KEY is set)"
    COMPONENTS_RAW="$COMPONENTS_RAW,traefik-log-dashboard"
  fi

  echo "[orchestrator] Auto-derived COMPONENTS: $COMPONENTS_RAW"
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
  elif has_component "pangolin"; then
    echo "pangolin"
  else
    # Auto-detect based on environment variables
    if [[ -n "${DB_USERNAME:-}" && -n "${REDIS_PASSWORD:-}" && -n "${PUSHER_APP_ID:-}" ]]; then
      echo "coolify"
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
  echo "[orchestrator] ERROR: Could not detect base platform. Please specify COMPONENTS with 'pangolin' or 'coolify', or provide appropriate environment variables."
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
  else
    echo "services:"
  fi

  # Base platform services
  if [[ "$BASE_PLATFORM" == "pangolin" ]]; then
    # Pangolin platform (includes pangolin + gerbil + traefik)
    sed -n '1,9999p' "$ROOT_DIR/components/pangolin/compose.yaml"
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    # Coolify platform
    sed -n '1,9999p' "$ROOT_DIR/components/coolify/compose.yaml"
  fi

  # Optional components (platform-agnostic)
  if has_component middleware-manager; then sed -n '1,9999p' "$ROOT_DIR/components/middleware-manager/compose.yaml"; fi
  if has_component static-page; then sed -n '1,9999p' "$ROOT_DIR/components/static-page/compose.yaml"; fi
  if has_component traefik-log-dashboard; then sed -n '1,9999p' "$ROOT_DIR/components/traefik-log-dashboard/compose.yaml"; fi
  if has_component mcpauth; then sed -n '1,9999p' "$ROOT_DIR/components/mcpauth/compose.yaml"; fi
  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/compose.yaml"; fi
  if has_component nlweb; then sed -n '1,9999p' "$ROOT_DIR/components/nlweb/compose.yaml"; fi
  if has_component komodo; then sed -n '1,9999p' "$ROOT_DIR/components/komodo/compose.yaml"; fi

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
    echo "      # Repository configuration"
    echo "      - REPO_URL=git@github.com:ManidaeCloud/${DEPLOYMENT_NAME}_syncresources.git"
    echo "      - BACKUP_SOURCE_PATH=${FULL_STACK_PATH}/config"
    echo "      - BACKUP_MODE=backup"
    echo "      - GIT_USER_NAME=Backup Bot"
    echo "      - GIT_USER_EMAIL=backup@\${DOMAIN:-contextware.ai}"
    echo "      # Backup configuration"
    echo "      - MAX_BACKUPS=\${MAX_BACKUPS}"
    echo "    volumes:"
    echo "      # Mount the actual directory from your VPS"
    echo "      - ${FULL_STACK_PATH}:${FULL_STACK_PATH}:ro"
    echo "    # Run continuously like bandwidth monitor"
    echo "    command: >"
    echo "      sh -c \"while true; do"
    echo "        echo 'Running backup at \$(date)' &&"
    echo "        /usr/local/bin/backup_script.sh &&"
    echo "        echo 'Backup completed. Sleeping for 1 day ...' &&"
    echo "        sleep 86400;"
    echo "      done\""
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
  if [[ "$BASE_PLATFORM" == "coolify" ]]; then sed -n '1,9999p' "$ROOT_DIR/components/coolify/volumes.yaml"; fi
  if has_component komodo; then sed -n '1,9999p' "$ROOT_DIR/components/komodo/volumes.yaml"; fi

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
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    cat <<'EOF'
networks:
  coolify:
    name: coolify
    driver: bridge
    external: true
EOF
  fi
} > "$compose_out"

echo "[orchestrator] Wrote $compose_out"

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
  elif [[ "$BASE_PLATFORM" == "coolify" ]]; then
    sed -n '1,9999p' "$ROOT_DIR/components/coolify/deployment-info.txt"
  fi

  # Component-specific deployment info
  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/deployment-info.txt"; fi
  # Future: append other components' deployment info as needed
} > "$info_out"
echo "[orchestrator] Wrote $info_out"

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
  for f in "$compose_out" "$info_out"; do
    tmp="$f.tmp"; envsubst < "$f" > "$tmp" && mv "$tmp" "$f"
  done
  echo "[orchestrator] Performed envsubst on outputs."
else
  echo "[orchestrator] SKIP_ENVSUBST=1 set; skipping envsubst."
fi

