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

# Create all necessary directories in the project folder (./data/coolify)
# These will be mounted as volumes in the compose.yaml
mkdir -p /host-setup/data/coolify/source
mkdir -p /host-setup/data/coolify/ssh/keys
mkdir -p /host-setup/data/coolify/ssh/mux
mkdir -p /host-setup/data/coolify/applications
mkdir -p /host-setup/data/coolify/databases
mkdir -p /host-setup/data/coolify/backups
mkdir -p /host-setup/data/coolify/services
mkdir -p /host-setup/data/coolify/proxy/dynamic
mkdir -p /host-setup/data/coolify/webhooks-during-maintenance

echo "✅ Created Coolify directory structure in ./data/coolify"

echo "🔑 Setting up SSH keys..."

# Generate SSH key for Coolify to manage the server
if [ ! -f "/host-setup/data/coolify/ssh/keys/id.root@host.docker.internal" ]; then
    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -f /host-setup/data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify
        echo "✅ Generated SSH key for Coolify"
        echo "📋 Add the public key to your ~/.ssh/authorized_keys:"
        echo "    cat ./data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys"
        echo "    chmod 600 ~/.ssh/authorized_keys"
    else
        echo "⚠️ ssh-keygen not available in container. Please generate SSH key manually:"
        echo "    ssh-keygen -f ./data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify"
        echo "    cat ./data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys"
        echo "    chmod 600 ~/.ssh/authorized_keys"
    fi
else
    echo "✅ SSH key already exists"
fi

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

# Set correct permissions for Coolify directories
chown -R 9999:root /host-setup/data/coolify 2>/dev/null || echo "⚠️ Could not set ownership (this is normal in some environments)"
chmod -R 700 /host-setup/data/coolify 2>/dev/null || echo "⚠️ Could not set permissions (this is normal in some environments)"

echo "✅ Set permissions for Coolify directories"

echo "✅ Coolify platform setup complete"
echo ""
echo "🚨 IMPORTANT: Before running 'docker compose up -d', ensure you have:"
echo "   1. Run the server prerequisites listed in the compose.yaml file comments"
echo "   2. Added the SSH public key to your ~/.ssh/authorized_keys"
echo "   3. Set proper permissions on /data/coolify directories"
echo "   4. Created the coolify Docker network"
echo ""

