#!/bin/sh
# Middleware Manager component setup
set -e

echo "📁 Creating middleware-manager directories..."
mkdir -p /host-setup/config/middleware-manager

# Update subdomain in postgres_export if present and custom subdomain is provided
if [ -f "/host-setup/postgres_export/resources.csv" ] && [ -n "${MIDDLEWARE_MANAGER_SUBDOMAIN:-}" ]; then
    echo "🔄 Updating middleware-manager subdomain to ${MIDDLEWARE_MANAGER_SUBDOMAIN}..."
    sed -i "s/middleware-manager\.${DOMAIN}/${MIDDLEWARE_MANAGER_SUBDOMAIN}.${DOMAIN}/g" /host-setup/postgres_export/resources.csv
    echo "✅ Updated middleware-manager subdomain to ${MIDDLEWARE_MANAGER_SUBDOMAIN}"
fi

echo "✅ Middleware Manager setup complete"
