#!/bin/bash
set -euo pipefail

# Test script to verify domain substitution works correctly

echo "🧪 Testing domain substitution logic..."

# Set up test environment
TEST_DIR="./test/domain-substitution-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/postgres_export"
mkdir -p "$TEST_DIR/components/pangolin/postgres_export"

# Copy the original resources.csv to simulate the component structure
cp components/pangolin/postgres_export/resources.csv "$TEST_DIR/components/pangolin/postgres_export/"

# Set test environment variables
export DOMAIN="mcpgateway.online"
export MIDDLEWARE_MANAGER_SUBDOMAIN=""
export TRAEFIK_SUBDOMAIN=""
export KOMODO_SUBDOMAIN=""
export NLWEB_SUBDOMAIN=""
export LOGS_SUBDOMAIN=""

# Simulate the domain update function
cd "$TEST_DIR"

echo "🔄 Updating domain references in CSV files..."

# Create postgres_export directory if it doesn't exist
mkdir -p postgres_export

# Copy postgres_export data from component to host setup directory
if [ -d "components/pangolin/postgres_export" ]; then
    cp -r components/pangolin/postgres_export/* postgres_export/
    echo "✅ Copied postgres_export data from pangolin component"
fi

# Check if resources.csv exists
if [ -f "postgres_export/resources.csv" ]; then
    echo "📄 Original resources.csv:"
    cat postgres_export/resources.csv
    echo ""
    
    # Replace example.com with the DOMAIN variable in resources.csv
    sed -i "s/example\.com/${DOMAIN}/g" postgres_export/resources.csv
    
    echo "📄 Updated resources.csv:"
    cat postgres_export/resources.csv
    echo ""
    
    # Verify the substitution worked
    if grep -q "$DOMAIN" postgres_export/resources.csv; then
        echo "✅ Domain substitution successful!"
    else
        echo "❌ Domain substitution failed!"
        exit 1
    fi
else
    echo "⚠️ resources.csv not found, skipping domain update"
    exit 1
fi

cd - > /dev/null
echo "🎉 Domain substitution test completed successfully!"
