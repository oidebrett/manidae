#!/bin/sh
# Traefik Log Dashboard component setup
set -e

echo "📊 Setting up Traefik Log Dashboard component..."

# Function to create required directories
create_directories() {
    echo "📁 Creating MaxMind directory..."
    mkdir -p /host-setup/config/maxmind
    echo "✅ MaxMind directory created"
}

# Function to modify traefik_config.yml to add logging and OTLP tracing
modify_traefik_config() {
    echo "🔧 Adding logging and OTLP tracing configuration to Traefik..."

    local config_file="/host-setup/config/traefik/traefik_config.yml"

    if [ ! -f "$config_file" ]; then
        echo "⚠️ Warning: traefik_config.yml not found at $config_file"
        return 1
    fi

    # Add logging configuration after "level: INFO"
    if ! grep -q 'filePath:.*traefik.log' "$config_file"; then
        echo "🔧 Adding file logging configuration..."

        # Create a temporary file for the new configuration
        local temp_file="/tmp/traefik_config_temp.yml"

        # Read the existing file and add logging configuration
        awk '
        /level: "INFO"/ {
            print $0
            print "    filePath: \"/var/log/traefik/traefik.log\""
            next
        }
        { print }
        ' "$config_file" > "$temp_file"

        # Replace the original file
        mv "$temp_file" "$config_file"

        echo "✅ File logging configuration added to traefik_config.yml"
    else
        echo "ℹ️ File logging configuration already exists in traefik_config.yml"
    fi

    # Check if tracing is already configured
    if grep -q "tracing:" "$config_file"; then
        echo "ℹ️ Tracing configuration already exists in traefik_config.yml"
        return 0
    fi

    # Add OTLP tracing configuration at the end of the file
    cat >> "$config_file" << 'EOF'

# OpenTelemetry Tracing Configuration
tracing:
  otlp:
    http:
      endpoint: "http://log-dashboard-backend:4318/v1/traces"
    # Alternative: GRPC for better performance
    # grpc:
    #   endpoint: "log-dashboard-backend:4317"
    #   insecure: true

  # Sampling rate (adjust for your needs)
  sampleRate: 0.1  # 100% for development, 0.1 (10%) for production

  # Global attributes added to all traces
  globalAttributes:
    environment: "production"
    service.version: "v3.0"
    deployment.environment: "pangolin"
EOF

    echo "✅ OTLP tracing configuration added to traefik_config.yml"
}

# Function to update DEPLOYMENT_INFO.txt with log dashboard information
update_deployment_info() {
    echo "📝 Updating deployment information..."
    
    cat >> /host-setup/DEPLOYMENT_INFO.txt << 'EOF'

📊 Traefik Log Dashboard:
- Backend: http://localhost:3001 (internal)
- Frontend: http://localhost:3000 (internal)
- OTLP GRPC: localhost:4317
- OTLP HTTP: localhost:4318
- MaxMind GeoIP: Enabled with automatic updates

🔧 Configuration:
- MaxMind database: ./config/maxmind/GeoLite2-City.mmdb
- Traefik main logs: ./config/traefik/logs/traefik.log
- Traefik access logs: ./config/traefik/logs/access.log
- OTLP tracing: Enabled with 10% sampling

⚠️ Performance Notes:
- For production, consider reducing sampling rate to 0.1 (10%)
- Use GRPC endpoint for better performance in high-traffic environments
- MaxMind database updates weekly automatically

📚 Documentation:
- Log Dashboard: https://github.com/hhftechnology/traefik-log-dashboard
- Middleware Manager: https://github.com/hhftechnology/middleware-manager
EOF
    
    echo "✅ Deployment information updated"
}

# Main execution
if [ -n "${MAXMIND_LICENSE_KEY:-}" ]; then
    echo "🛡️ MaxMind license key detected - setting up Traefik Log Dashboard..."
    create_directories
    modify_traefik_config
    update_deployment_info
    echo "✅ Traefik Log Dashboard component setup complete"
else
    echo "⚠️ MAXMIND_LICENSE_KEY not set, skipping Traefik Log Dashboard setup"
fi

# Update subdomain in postgres_export if present and custom subdomain is provided
if [ -f "/host-setup/postgres_export/resources.csv" ] && [ -n "${LOGS_SUBDOMAIN:-}" ]; then
    echo "🔄 Updating logs subdomain to ${LOGS_SUBDOMAIN}..."
    sed -i "s/logs\.${DOMAIN}/${LOGS_SUBDOMAIN}.${DOMAIN}/g" /host-setup/postgres_export/resources.csv
    echo "✅ Updated logs subdomain to ${LOGS_SUBDOMAIN}"
fi
