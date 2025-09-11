#!/bin/sh
# Coolify platform setup
set -e

echo "🚀 Setting up Coolify platform..."

# Generate secure random values for Coolify
generate_random_hex() {
    openssl rand -hex 16
}

generate_random_base64() {
    openssl rand -base64 32
}

# Generate required values if not provided
APP_ID="${APP_ID:-$(generate_random_hex)}"
APP_KEY="${APP_KEY:-base64:$(generate_random_base64)}"

echo "� Server prerequisites will be handled separately"
echo "    Directory creation and SSH key setup must be done on the server"
echo "    See compose.yaml comments for detailed instructions"

echo "🔧 Auto-generating missing Coolify environment variables..."

# Function to add environment variable to .env file ONLY if it doesn't exist at all
add_env_var_if_missing() {
    local var_name="$1"
    local var_value="$2"
    local env_file="/host-setup/.env"

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
        echo "Added ${var_name} to .env file"
        export "${var_name}=${var_value}"
    else
        echo "Using existing ${var_name} from .env file"
    fi
}

# Generate required values and add to .env only if missing
APP_ID=$(generate_random_hex)
add_env_var_if_missing "APP_ID" "$APP_ID"

APP_KEY="base64:$(generate_random_base64)"
add_env_var_if_missing "APP_KEY" "$APP_KEY"

DB_USERNAME="coolify"
add_env_var_if_missing "DB_USERNAME" "$DB_USERNAME"

DB_PASSWORD=$(generate_random_base64)
add_env_var_if_missing "DB_PASSWORD" "$DB_PASSWORD"

REDIS_PASSWORD=$(generate_random_base64)
add_env_var_if_missing "REDIS_PASSWORD" "$REDIS_PASSWORD"

PUSHER_APP_ID=$(openssl rand -hex 32)
add_env_var_if_missing "PUSHER_APP_ID" "$PUSHER_APP_ID"

PUSHER_APP_KEY=$(openssl rand -hex 32)
add_env_var_if_missing "PUSHER_APP_KEY" "$PUSHER_APP_KEY"

PUSHER_APP_SECRET=$(openssl rand -hex 32)
add_env_var_if_missing "PUSHER_APP_SECRET" "$PUSHER_APP_SECRET"

# Add other common variables with defaults only if missing
add_env_var_if_missing "APP_NAME" "Coolify"
add_env_var_if_missing "APP_ENV" "production"
add_env_var_if_missing "DB_DATABASE" "coolify"
add_env_var_if_missing "APP_PORT" "8000"
add_env_var_if_missing "SOKETI_PORT" "6001"
add_env_var_if_missing "SOKETI_DEBUG" "false"
add_env_var_if_missing "REGISTRY_URL" "ghcr.io"
add_env_var_if_missing "LATEST_IMAGE" "latest"

echo "✅ Generated missing Coolify configuration values (only added missing variables to .env)"

echo "🌐 Setting up Docker network..."

# Create the coolify docker network if it doesn't exist
if ! docker network ls | grep -q "coolify"; then
    echo "Creating coolify docker network..."
    docker network create --attachable coolify || echo "⚠️ Network coolify may already exist"
else
    echo "✅ Coolify docker network already exists"
fi

echo "📋 Permissions will be handled on the server"
echo "    Server setup must include: chown -R 9999:root /data/coolify && chmod -R 700 /data/coolify"

# Generate custom domain configuration for Coolify proxy
echo "🌐 Generating custom domain configuration..."

# Set default admin subdomain if not provided
ADMIN_SUBDOMAIN="${ADMIN_SUBDOMAIN:-coolify}"

# Validate required DOMAIN variable
if [ -z "${DOMAIN}" ]; then
    echo "❌ Error: DOMAIN environment variable is required for Coolify proxy configuration"
    exit 1
fi

# Create config directory if it doesn't exist
mkdir -p /host-setup/config/coolify

# Generate the custom domain configuration file
cat > /host-setup/config/coolify/custom_domain.yml << EOF
http:
  routers:
    coolify-ui:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: coolify-ui-service
      entryPoints:
        - https
      middlewares:
        - crowdsec@file
      tls:
        certResolver: letsencrypt

  services:
    coolify-ui-service:
      loadBalancer:
        servers:
          - url: "http://coolify:8080"
EOF

echo "✅ Generated custom domain configuration at config/coolify/custom_domain.yml"
echo "   Domain: ${ADMIN_SUBDOMAIN}.${DOMAIN}"

echo "✅ Coolify platform setup complete"
echo ""
echo "🚨 IMPORTANT: Before running 'docker compose up -d', complete the server prerequisites:"
echo "   See the detailed instructions in the generated compose.yaml file comments"
echo "   Or follow the official Coolify manual installation guide:"
echo "   https://coolify.io/docs/installation#manual"
echo ""
echo "📋 Additional step required for custom domain:"
echo "   Copy the generated proxy configuration to the server:"
echo "   cp config/coolify/custom_domain.yml /data/coolify/proxy/dynamic/"
echo ""

