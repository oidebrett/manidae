# CrowdSec setup additions

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Detect platform based on environment variables
# First check if .env file exists and source it to get auto-generated variables
if [ -f "$ROOT_HOST_DIR/.env" ]; then
    # Source the .env file to get auto-generated Coolify variables
    set -a  # automatically export all variables
    . "$ROOT_HOST_DIR/.env"
    set +a  # stop automatically exporting
fi

if [ -n "${DB_USERNAME:-}" ] && [ -n "${REDIS_PASSWORD:-}" ] && [ -n "${PUSHER_APP_ID:-}" ]; then
    PLATFORM="coolify"
    echo "🛡️ Setting up CrowdSec for Coolify platform"
elif [ -n "${DOMAIN:-}" ] && [ -n "${EMAIL:-}" ]; then
    PLATFORM="pangolin"
    echo "🛡️ Setting up CrowdSec for Pangolin platform"
else
    # Default to pangolin for backward compatibility
    PLATFORM="pangolin"
    echo "🛡️ Setting up CrowdSec for Pangolin platform (default)"
fi

# Directories
mkdir -p "$ROOT_HOST_DIR/config/crowdsec/db"
mkdir -p "$ROOT_HOST_DIR/config/crowdsec/acquis.d"
mkdir -p "$ROOT_HOST_DIR/config/crowdsec_logs"

# Platform-specific directories
if [ "$PLATFORM" = "pangolin" ]; then
    mkdir -p "$ROOT_HOST_DIR/config/traefik/logs"
    mkdir -p "$ROOT_HOST_DIR/config/traefik/conf"
elif [ "$PLATFORM" = "coolify" ]; then
    mkdir -p "$ROOT_HOST_DIR/config/coolify/proxy"
fi

# Config files - platform-specific
if [ "$PLATFORM" = "pangolin" ]; then
    cat > "$ROOT_HOST_DIR/config/crowdsec/acquis.yaml" << 'EOF'
poll_without_inotify: false
filenames:
  - /var/log/traefik/*.log
labels:
  type: traefik
---
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: myAppSecComponent
source: appsec
labels:
  type: appsec
EOF
elif [ "$PLATFORM" = "coolify" ]; then
    cat > "$ROOT_HOST_DIR/config/crowdsec/acquis.yaml" << 'EOF'
poll_without_inotify: false
filenames:
  - /var/log/coolify/proxy/access.log
labels:
  type: traefik
  log_type: http_access-log
---
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: myAppSecComponent
source: appsec
labels:
  type: appsec
EOF
fi

cat > "$ROOT_HOST_DIR/config/crowdsec/profiles.yaml" << 'EOF'
name: captcha_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.GetScenario() contains "http"
decisions:
  - type: captcha
    duration: 4h
on_success: break

---
name: default_ip_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
 - type: ban
   duration: 4h
on_success: break

---
name: default_range_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
 - type: ban
   duration: 4h
on_success: break
EOF

# Platform-specific additional setup
if [ "$PLATFORM" = "pangolin" ]; then
    wget -O "$ROOT_HOST_DIR/config/traefik/conf/captcha.html" https://gist.githubusercontent.com/hhftechnology/48569d9f899bb6b889f9de2407efd0d2/raw/captcha.html
elif [ "$PLATFORM" = "coolify" ]; then
    # For Coolify, download captcha.html to the coolify proxy config
    wget -O "$ROOT_HOST_DIR/config/coolify/proxy/captcha.html" https://gist.githubusercontent.com/hhftechnology/48569d9f899bb6b889f9de2407efd0d2/raw/captcha.html

    # Create CrowdSec plugin configuration for Coolify Traefik
    cat > "$ROOT_HOST_DIR/config/coolify/proxy/crowdsec-plugin.yml" << 'EOF'
http:
  middlewares:
    crowdsec:
      plugin:
        crowdsec-bouncer:
          crowdsecMode: live
          crowdsecLapiHost: 'host.docker.internal:8080'
          crowdsecLapiKey: 'PASTE_YOUR_KEY_HERE'
          enabled: true
EOF

    # Create docker-compose.override.yml for Coolify proxy logging (to be placed in /data/coolify/proxy/)
    cat > "$ROOT_HOST_DIR/config/coolify/proxy/docker-compose.override.yml" << 'EOF'
# Coolify Proxy Logging Override
# This file enables access logging for Coolify's Traefik proxy
#
# IMPORTANT: Copy this file to /data/coolify/proxy/docker-compose.override.yml
# This will enable access logging required for CrowdSec integration

services:
  coolify-proxy:
    command:
      - '--ping=true'
      - '--ping.entrypoint=http'
      - '--api.dashboard=true'
      - '--entrypoints.http.address=:80'
      - '--entrypoints.https.address=:443'
      - '--entrypoints.http.http.encodequerysemicolons=true'
      - '--entryPoints.http.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http.encodequerysemicolons=true'
      - '--entryPoints.https.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http3'
      - '--providers.file.directory=/traefik/dynamic/'
      - '--providers.file.watch=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http'
      - '--certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json'
      - '--api.insecure=false'
      - '--providers.docker=true'
      - '--providers.docker.exposedbydefault=false'
      # 🔽 Added log settings for CrowdSec integration
      - '--accesslog=true'
      - '--accesslog.format=json'
      - '--accesslog.filepath=/traefik/access.log'
EOF

    # Create docker-compose.overlay.yml for CrowdSec service integration
    cat > "$ROOT_HOST_DIR/docker-compose.overlay.yml" << 'EOF'
# CrowdSec Integration Overlay for Coolify
# This file adds CrowdSec integration to the base Coolify deployment
#
# IMPORTANT: After deployment, you need to:
# 1. Get the bouncer API key: docker exec crowdsec cscli bouncers add traefik-bouncer
# 2. Update the crowdsecLapiKey in /data/coolify/proxy/dynamic/crowdsec-plugin.yml
# 3. Copy the overlay files to /data/coolify/proxy/dynamic/:
#    cp config/coolify/proxy/crowdsec-plugin.yml /data/coolify/proxy/dynamic/
#    cp config/coolify/proxy/captcha.html /data/coolify/proxy/

services:
  # Override coolify-proxy with CrowdSec integration
  coolify-proxy:
    command:
      - '--ping=true'
      - '--ping.entrypoint=http'
      - '--api.dashboard=true'
      - '--entrypoints.http.address=:80'
      - '--entrypoints.https.address=:443'
      - '--entrypoints.http.http.encodequerysemicolons=true'
      - '--entryPoints.http.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http.encodequerysemicolons=true'
      - '--entryPoints.https.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http3'
      - '--providers.file.directory=/traefik/dynamic/'
      - '--providers.file.watch=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http'
      - '--certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json'
      - '--api.insecure=false'
      - '--providers.docker=true'
      - '--providers.docker.exposedbydefault=false'
      # CrowdSec Traefik integration
      - '--entrypoints.http.http.middlewares=crowdsec@file'
      - '--entrypoints.https.http.middlewares=crowdsec@file'
      # CrowdSec plugin configuration
      - '--experimental.plugins.crowdsec-bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin'
      - '--experimental.plugins.crowdsec-bouncer.version=v1.2.1'
      # Access log settings for CrowdSec
      - '--accesslog=true'
      - '--accesslog.format=json'
      - '--accesslog.bufferingsize=0'
      - '--accesslog.fields.headers.defaultmode=drop'
      - '--accesslog.fields.headers.names.User-Agent=keep'
      - '--accesslog.filepath=/traefik/access.log'
      # Enhanced logging
      - '--log.level=INFO'
      # Cloudflare support (if using Cloudflare DNS)
      - '--entryPoints.http.forwardedHeaders.insecure=true'
      - '--entryPoints.https.forwardedHeaders.insecure=true'
    extra_hosts:
      - host.docker.internal:host-gateway
    networks:
      - coolify

  # Add CrowdSec service to the stack
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: coolify-crowdsec
    environment:
      GID: "1000"
      COLLECTIONS: crowdsecurity/traefik crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules crowdsecurity/linux
      ENROLL_INSTANCE_NAME: "coolify-crowdsec"
      PARSERS: crowdsecurity/whitelists
      ENROLL_TAGS: docker
      ENROLL_KEY: ${CROWDSEC_ENROLLMENT_KEY}
    healthcheck:
      interval: 10s
      retries: 15
      timeout: 10s
      test: ["CMD", "cscli", "capi", "status"]
    volumes:
      # crowdsec container data
      - ./config/crowdsec:/etc/crowdsec
      - ./config/crowdsec/db:/var/lib/crowdsec/data
      # log bind mounts into crowdsec (Coolify-specific)
      - /data/coolify/proxy:/var/log/coolify/proxy
    ports:
      - 6060:6060 # metrics endpoint for prometheus
      - 8080:8080 # LAPI endpoint for bouncers
    restart: unless-stopped
    command: -t
    networks:
      - coolify
    extra_hosts:
      - host.docker.internal:host-gateway
EOF
fi

# Set platform-specific environment variables for CrowdSec compose configuration
if [ "$PLATFORM" = "coolify" ]; then
    # Set environment variables for Coolify CrowdSec configuration
    export CROWDSEC_INSTANCE_NAME="coolify-crowdsec"
    export CROWDSEC_LOG_VOLUME="/data/coolify/proxy:/var/log/traefik"
    export CROWDSEC_NETWORK="coolify"

    # Add environment variables to .env file if they don't exist
    add_env_var_if_missing() {
        local var_name="$1"
        local var_value="$2"
        local env_file="$ROOT_HOST_DIR/.env"

        # Create .env file if it doesn't exist
        if [ ! -f "$env_file" ]; then
            touch "$env_file"
        fi

        # Only add if the variable doesn't exist at all in the file
        if ! grep -q "^${var_name}=" "$env_file"; then
            # Ensure the file ends with a newline before appending
            if [ -s "$env_file" ] && [ "$(tail -c1 "$env_file" | wc -l)" -eq 0 ]; then
                echo "" >> "$env_file"
            fi
            echo "${var_name}=${var_value}" >> "$env_file"
        fi
    }

    add_env_var_if_missing "CROWDSEC_INSTANCE_NAME" "coolify-crowdsec"
    add_env_var_if_missing "CROWDSEC_LOG_VOLUME" "/data/coolify/proxy:/var/log/coolify/proxy"
    add_env_var_if_missing "CROWDSEC_NETWORK" "coolify"
elif [ "$PLATFORM" = "pangolin" ]; then
    # Set environment variables for Pangolin CrowdSec configuration (defaults)
    export CROWDSEC_INSTANCE_NAME="pangolin-crowdsec"
    export CROWDSEC_LOG_VOLUME="./config/traefik/logs:/var/log/traefik"
    export CROWDSEC_NETWORK="default"
fi

# CrowdSec does not need to modify dynamic_config.yml
# The routing and services are handled by pangolin and other components
# CrowdSec only provides security scanning and bouncer functionality


# Deployment info additions - platform-specific
if [ "$PLATFORM" = "pangolin" ]; then
    cat >> "$ROOT_HOST_DIR/DEPLOYMENT_INFO.txt" << 'EOF'
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    └── profiles.yaml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec

🛡️ CrowdSec Notes:
- AppSec and log parsing is configured
- Prometheus and API are enabled
- CAPTCHA and remediation profiles are active
- Remember to get the bouncer API key after containers start:
  docker exec crowdsec cscli bouncers add traefik-bouncer
EOF
elif [ "$PLATFORM" = "coolify" ]; then
    cat >> "$ROOT_HOST_DIR/DEPLOYMENT_INFO.txt" << 'EOF'
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    └── profiles.yaml
└── coolify/
    └── proxy/
        ├── crowdsec-plugin.yml
        ├── captcha.html
        └── docker-compose.override.yml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec
docker-compose.overlay.yml # CrowdSec integration overlay

🛡️ CrowdSec for Coolify+ Notes:
- Docker-based CrowdSec integration (no apt installation required)
- Configured to monitor /data/coolify/proxy/access.log
- Uses docker-compose.overlay.yml pattern for non-intrusive integration
- AppSec and log parsing is configured
- Prometheus and API are enabled on ports 6060 and 8080
- CAPTCHA and remediation profiles are active

🚨 IMPORTANT POST-DEPLOYMENT STEPS:
1. Enable Coolify proxy logging (REQUIRED for CrowdSec):
   cp config/coolify/proxy/docker-compose.override.yml /data/coolify/proxy/
   docker restart coolify-proxy

2. Get the bouncer API key:
   docker exec coolify-crowdsec cscli bouncers add traefik-bouncer

3. Update the CrowdSec plugin configuration:
   # Copy the API key from step 2 and update:
   sed -i 's/PASTE_YOUR_KEY_HERE/YOUR_ACTUAL_API_KEY/' config/coolify/proxy/crowdsec-plugin.yml

4. Copy CrowdSec plugin files to Coolify proxy directory:
   cp config/coolify/proxy/crowdsec-plugin.yml /data/coolify/proxy/dynamic/
   cp config/coolify/proxy/captcha.html /data/coolify/proxy/

5. Restart Coolify proxy to apply CrowdSec plugin:
   docker restart coolify-proxy

6. Verify CrowdSec is working:
   docker exec coolify-crowdsec cscli metrics
   # Look for coolify-proxy logs being parsed
   # Check that /data/coolify/proxy/access.log is being created

📚 CrowdSec Documentation:
- CrowdSec Docs: https://docs.crowdsec.net/
- Traefik Plugin: https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
- Coolify Integration Guide: See COOLIFY_CROWDSEC.md

EOF
fi

