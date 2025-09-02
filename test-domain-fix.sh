#!/bin/bash
set -euo pipefail

echo "🧪 Testing domain substitution fix..."

# Create test directory structure
TEST_DIR="./test-domain-fix"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/components/pangolin/postgres_export"

# Copy the original resources.csv
cp components/pangolin/postgres_export/resources.csv "$TEST_DIR/components/pangolin/postgres_export/"

# Set test domain
DOMAIN="mcpgateway.online"

echo "📄 Original resources.csv:"
cat "$TEST_DIR/components/pangolin/postgres_export/resources.csv"
echo ""

# Simulate the config-setup.sh logic
cd "$TEST_DIR"

# Create postgres_export directory
mkdir -p postgres_export

# Copy postgres_export data from component
cp -r components/pangolin/postgres_export/* postgres_export/

# Apply domain substitution (the fixed version)
sed -i "s/example\.com/${DOMAIN}/g" postgres_export/resources.csv

echo "📄 Updated resources.csv:"
cat postgres_export/resources.csv
echo ""

# Verify the substitution worked
if grep -q "$DOMAIN" postgres_export/resources.csv; then
    echo "✅ Domain substitution successful! Found $DOMAIN in resources.csv"
else
    echo "❌ Domain substitution failed! $DOMAIN not found in resources.csv"
    exit 1
fi

cd ..
echo "🎉 Test completed successfully!"

# Show how to run the initialize scripts
echo ""
echo "📋 To run the initialize scripts after deployment:"
echo "1. From the root directory where you ran docker-compose-setup.yml:"
echo "   ./components/pangolin/initialize_sqlite.sh"
echo "   # or"
echo "   ./components/pangolin/initialize_postgres.sh"
echo ""
echo "2. The scripts will find the postgres_export directory at ./postgres_export"
echo "3. Make sure the domain substitution worked by checking:"
echo "   cat postgres_export/resources.csv"
