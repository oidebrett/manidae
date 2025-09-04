#!/bin/sh
# Komodo component setup
set -e

echo "🐉 Setting up Komodo component..."

# Update subdomain in postgres_export if present and custom subdomain is provided
if [ -f "/host-setup/postgres_export/resources.csv" ] && [ -n "${KOMODO_SUBDOMAIN:-}" ]; then
    echo "🔄 Updating komodo subdomain to ${KOMODO_SUBDOMAIN}..."
    sed -i "s/komodo\.${DOMAIN}/${KOMODO_SUBDOMAIN}.${DOMAIN}/g" /host-setup/postgres_export/resources.csv
    echo "✅ Updated komodo subdomain to ${KOMODO_SUBDOMAIN}"
fi

echo "✅ Komodo component setup complete"

