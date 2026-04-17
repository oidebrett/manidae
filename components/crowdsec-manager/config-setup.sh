# CrowdSec Manager setup additions

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Create directories needed by crowdsec-manager
mkdir -p "$ROOT_HOST_DIR/backups"
mkdir -p "$ROOT_HOST_DIR/data"

cat >> "$ROOT_HOST_DIR/DEPLOYMENT_INFO.txt" << 'EOF'

🛡️ CrowdSec Manager:
- Dashboard available at: https://crowdsec-manager.yourdomain.com
- Manages CrowdSec decisions, bouncers, and configuration
- Connects to Docker socket for container management
EOF
