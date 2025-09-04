#!/bin/sh
# NLWeb component setup: copy template config if present
set -e

echo "🤖 Setting up NLWeb component..."

if [ -f "/host-setup/templates/nlweb_config/config_nlweb.yaml" ]; then
  mkdir -p /host-setup/config/nlweb
  cp -r "/host-setup/templates/nlweb_config/" "/host-setup/config/nlweb/"
  echo "✅ NLWeb config templates copied"
fi

# Update subdomain in postgres_export if present and custom subdomain is provided
if [ -f "/host-setup/postgres_export/resources.csv" ] && [ -n "${NLWEB_SUBDOMAIN:-}" ]; then
    echo "🔄 Updating nlweb subdomain to ${NLWEB_SUBDOMAIN}..."
    sed -i "s/nlweb\.${DOMAIN}/${NLWEB_SUBDOMAIN}.${DOMAIN}/g" /host-setup/postgres_export/resources.csv
    echo "✅ Updated nlweb subdomain to ${NLWEB_SUBDOMAIN}"
fi

echo "✅ NLWeb component setup complete"

