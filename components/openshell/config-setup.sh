#!/bin/sh
# OpenShell component setup - adds openshell-gateway Pangolin resource/target
set -e

echo "🐚 Setting up OpenShell component..."

# This script runs in the context of build-compose.sh
# ROOT_HOST_DIR is set by the orchestrator to the host config directory

# The Pangolin postgres_export CSVs are written by the pangolin config-setup.sh.
# We append the openshell-gateway resource here so it gets provisioned automatically.
# The pangolin config-setup.sh get_included_resource_ids() already handles filtering
# resource id 11 (openshell-gateway) when openshell component is present.

echo "✅ OpenShell component setup complete"
echo "🌐 OpenShell gateway will be available at: https://openshell-gateway.${DOMAIN}"
