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

echo "📁 Creating Coolify directory structure..."

# Create all necessary directories as per official Coolify setup
# Note: These directories need to be created on the HOST at /data/coolify, not in the container
# The user must run these commands on their server before docker compose up:
echo "⚠️  Directory creation will be handled by server prerequisites"
echo "    The following directories must be created on the HOST system:"
echo "    mkdir -p /data/coolify/source"
echo "    mkdir -p /data/coolify/ssh/keys"
echo "    mkdir -p /data/coolify/ssh/mux"
echo "    mkdir -p /data/coolify/applications"
echo "    mkdir -p /data/coolify/databases"
echo "    mkdir -p /data/coolify/backups"
echo "    mkdir -p /data/coolify/services"
echo "    mkdir -p /data/coolify/proxy/dynamic"
echo "    mkdir -p /data/coolify/webhooks-during-maintenance"

echo "🔑 Setting up SSH keys..."

# SSH key generation must be done on the HOST system, not in the container
echo "⚠️  SSH key generation will be handled by server prerequisites"
echo "    The SSH key must be generated on the HOST system:"
echo "    ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify"
echo "    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys"
echo "    chmod 600 ~/.ssh/authorized_keys"

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

echo "📋 Setting up permissions..."

# Permissions must be set on the HOST system, not in the container
echo "⚠️  Permissions will be handled by server prerequisites"
echo "    The following permissions must be set on the HOST system:"
echo "    chown -R 9999:root /data/coolify"
echo "    chmod -R 700 /data/coolify"

echo "✅ Coolify platform setup complete"
echo ""
echo "🚨 IMPORTANT: Before running 'docker compose up -d', ensure you have:"
echo "   1. Run the server prerequisites listed in the compose.yaml file comments"
echo "   2. Added the SSH public key to your ~/.ssh/authorized_keys"
echo "   3. Set proper permissions on /data/coolify directories"
echo "   4. Created the coolify Docker network"
echo ""

