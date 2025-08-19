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
    if [ -f "${ROOT_HOST_DIR}/components/${c}/config-setup.sh" ]; then
      /bin/sh "${ROOT_HOST_DIR}/components/${c}/config-setup.sh" || true
    fi
  done
}
run_component_hooks
