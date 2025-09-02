# Coolify platform setup

echo "🚀 Setting up Coolify platform..."

# Create necessary directories
mkdir -p /host-setup/data/coolify/source
mkdir -p /host-setup/data/coolify/ssh
mkdir -p /host-setup/data/coolify/applications
mkdir -p /host-setup/data/coolify/databases
mkdir -p /host-setup/data/coolify/services
mkdir -p /host-setup/data/coolify/backups
mkdir -p /host-setup/data/coolify/webhooks-during-maintenance

echo "📁 Created Coolify data directories"

# Create Coolify .env file
cat > /host-setup/data/coolify/source/.env << EOF
# Coolify Configuration
APP_NAME="${APP_NAME:-Coolify}"
APP_ENV="${APP_ENV:-production}"
APP_DEBUG=false
APP_URL=http://localhost:${APP_PORT:-8000}

# Database Configuration
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=${DB_DATABASE:-coolify}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}

# Redis Configuration
REDIS_HOST=redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_PORT=6379

# Pusher Configuration (for WebSocket)
PUSHER_APP_ID=${PUSHER_APP_ID}
PUSHER_APP_KEY=${PUSHER_APP_KEY}
PUSHER_APP_SECRET=${PUSHER_APP_SECRET}
PUSHER_HOST=soketi
PUSHER_PORT=6001
PUSHER_SCHEME=http

# Docker Configuration
DOCKER_HOST=unix:///var/run/docker.sock

# SSL Configuration
SSL_MODE=off

# Session Configuration
SESSION_DRIVER=redis
SESSION_LIFETIME=120

# Cache Configuration
CACHE_DRIVER=redis

# Queue Configuration
QUEUE_CONNECTION=redis

# Mail Configuration (optional)
MAIL_MAILER=log

# Logging
LOG_CHANNEL=stack
LOG_LEVEL=info

# Additional Coolify specific settings
COOLIFY_AUTO_UPDATE=false
COOLIFY_INSTANCE_SETTINGS_IS_REGISTRATION_ENABLED=false
EOF

echo "✅ Created Coolify .env configuration"

# Create docker network if it doesn't exist
if ! docker network ls | grep -q "coolify"; then
    echo "🌐 Creating coolify docker network..."
    docker network create coolify || echo "⚠️ Network coolify may already exist"
else
    echo "✅ Coolify docker network already exists"
fi

echo "✅ Coolify platform setup complete"

