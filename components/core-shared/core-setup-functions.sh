# Core shared functions extracted from original container-setup.sh

# Generate a secure random secret key
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to update domain in CSV files
update_domains_in_csv() {
    echo "🔄 Updating domain references in CSV files..."
    mkdir -p /host-setup/postgres_export
    if [ -f "/host-setup/postgres_export/resources.csv" ]; then
        sed -i "s/yourdomain\.com/${DOMAIN}/g" /host-setup/postgres_export/resources.csv
        echo "✅ Updated domain references in resources.csv"
    else
        echo "⚠️ resources.csv not found, skipping domain update"
    fi
}

