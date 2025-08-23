#!/usr/bin/env bash
set -euo pipefail

# Orchestrator: builds compose.yaml, container-setup.sh, DEPLOYMENT_INFO.txt
# Usage:
#   COMPONENTS="pangolin,crowdsec,mcpauth,komodo" OUTPUT_DIR=./out ./orchestrator/build-compose.sh
# Env:
#   COMPONENTS       Comma-separated list of components (must include pangolin)
#   OUTPUT_DIR       Directory to write outputs (default: $PWD)
#   DRY_RUN=1        If set, do not execute the generated container-setup.sh
#   SKIP_ENVSUBST=1  If set, do not run envsubst on outputs (useful for tests)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPONENTS_RAW="${COMPONENTS:-pangolin}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD}"
IFS="," read -r -a COMPONENTS_ARR <<< "$COMPONENTS_RAW"

# Helpers
has_component() {
  local c="$1"
  for x in "${COMPONENTS_ARR[@]}"; do
    # Handle pangolin+ as alias for pangolin
    if [[ "$c" == "pangolin" && ("$x" == "pangolin" || "$x" == "pangolin+") ]]; then
      return 0
    elif [[ "$x" == "$c" ]]; then
      return 0
    fi
  done
  return 1
}

echo "[orchestrator] Using components: ${COMPONENTS_RAW}"
echo "[orchestrator] Output dir: ${OUTPUT_DIR}"
mkdir -p "$OUTPUT_DIR"

# --- Build compose.yaml ---
compose_out="$OUTPUT_DIR/compose.yaml"
{
  echo "services:"
  # Pangolin service
  sed -n '1,9999p' "$ROOT_DIR/components/pangolin/compose.yaml"
  # Standalone postgres unless komodo selected
  #if ! has_component komodo; then
  #  sed -n '1,9999p' "$ROOT_DIR/components/pangolin/postgres.yaml"
  #fi
  # Core shared services after pangolin/postgres
  sed -n '1,9999p' "$ROOT_DIR/components/core-shared/core-services.yaml"
  # Optional components
  if has_component middleware-manager; then sed -n '1,9999p' "$ROOT_DIR/components/middleware-manager/compose.yaml"; fi
  if has_component static-page; then sed -n '1,9999p' "$ROOT_DIR/components/static-page/compose.yaml"; fi
  if has_component traefik-log-dashboard; then sed -n '1,9999p' "$ROOT_DIR/components/traefik-log-dashboard/compose.yaml"; fi
  if has_component mcpauth; then sed -n '1,9999p' "$ROOT_DIR/components/mcpauth/compose.yaml"; fi
  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/compose.yaml"; fi
  if has_component nlweb; then sed -n '1,9999p' "$ROOT_DIR/components/nlweb/compose.yaml"; fi
  if has_component komodo; then sed -n '1,9999p' "$ROOT_DIR/components/komodo/compose.yaml"; fi
  # Volumes for komodo (emit before networks to match golden masters)
  if has_component komodo; then sed -n '1,9999p' "$ROOT_DIR/components/komodo/volumes.yaml"; fi
  # Networks (always, must be last)
  cat <<'EOF'
networks:
  default:
    driver: bridge
    #external: true
    name: pangolin
    enable_ipv6: true
EOF
} > "$compose_out"

echo "[orchestrator] Wrote $compose_out"

# --- Build container-setup.sh (copy if present; fallback generate if missing/empty) ---
setup_out="$OUTPUT_DIR/container-setup.sh"
setup_src="$ROOT_DIR/container-setup.sh"
if [ -s "$setup_src" ]; then
  if [ "$setup_src" = "$setup_out" ]; then
    tmp_file="$(mktemp)"
    sed -n '1,9999p' "$setup_src" > "$tmp_file"
    cat "$tmp_file" > "$setup_out"
    rm -f "$tmp_file"
  else
    sed -n '1,9999p' "$setup_src" > "$setup_out"
  fi
else
  echo "[orchestrator] Source container-setup.sh missing or empty; generating default"
  cat <<'EOS' > "$setup_out"
#!/bin/sh
set -e
ROOT_HOST_DIR="/host-setup"
COMPONENTS_CSV="${COMPONENTS:-pangolin}"
log() { printf "%s\n" "$*"; }
run_component_hooks() {
  comps_csv="${COMPONENTS_CSV}"
  # Run core-shared first if present
  if [ -f "${ROOT_HOST_DIR}/components/core-shared/config-setup.sh" ]; then
    /bin/sh "${ROOT_HOST_DIR}/components/core-shared/config-setup.sh" || true
  fi
  # POSIX sh split (BusyBox ash compatible)
  old_ifs="$IFS"; IFS=','; set -- $comps_csv; IFS="$old_ifs"
  for c in "$@"; do
    [ -z "$c" ] && continue
    # Handle pangolin+ as alias for pangolin
    component_dir="$c"
    if [ "$c" = "pangolin+" ]; then
      component_dir="pangolin"
    fi
    if [ -f "${ROOT_HOST_DIR}/components/${component_dir}/config-setup.sh" ]; then
      /bin/sh "${ROOT_HOST_DIR}/components/${component_dir}/config-setup.sh" || true
    fi
  done
}
run_component_hooks
EOS
fi
chmod +x "$setup_out"
echo "[orchestrator] Wrote $setup_out"

# --- Build DEPLOYMENT_INFO.txt from snippets ---
info_out="$OUTPUT_DIR/DEPLOYMENT_INFO.txt"
{
  sed -n '1,9999p' "$ROOT_DIR/components/pangolin/deployment-info.txt"
  if has_component crowdsec; then sed -n '1,9999p' "$ROOT_DIR/components/crowdsec/deployment-info.txt"; fi
  # Future: append other components' deployment info as needed
} > "$info_out"
echo "[orchestrator] Wrote $info_out"

# --- Execute setup script unless dry run ---
if [[ "${DRY_RUN:-}" != "1" ]]; then
  echo "[orchestrator] Executing $setup_out"
  "$setup_out"
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

