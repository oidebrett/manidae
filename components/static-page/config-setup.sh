#!/bin/sh
# Static page component setup
set -e

echo "📄 Setting up static page component..."

# Function to create static page HTML
create_static_page_html() {
    echo "📄 Creating static page HTML..."
    mkdir -p /host-setup/public_html
    
    # Check if we're in an AgentGateway deployment (index.html already exists and has chatkit)
    if [ -f "/host-setup/public_html/index.html" ] && grep -q "chatkit" "/host-setup/public_html/index.html"; then
        echo "AgentGateway index.html detected - skipping static page HTML generation to preserve AgentGateway template"
        return 0
    fi

    # Check if template exists in the templates html directory
    if [ -f "/host-setup/templates/html/index.html" ]; then
        echo "Using template from templates directory"

        # Copy template to a temporary file
        cp "/host-setup/templates/html/index.html" "/tmp/index.html.template"

        # Determine if this is an AgentGateway deployment
        IS_AGENTGATEWAY=false
        if echo "${COMPONENTS_CSV:-}" | grep -q "agentgateway"; then
            IS_AGENTGATEWAY=true
        fi

        # Handle AI components based on deployment type
        if [ "$IS_AGENTGATEWAY" = true ]; then
            echo "AgentGateway deployment detected - removing nlweb sections and keeping chatkit sections"
            # Remove nlweb sections for AgentGateway
            sed -i '/<!-- Start of Nlweb -->/,/<!-- End of Nlweb -->/d' "/tmp/index.html.template"
            sed -i 's/Pangolin • Nlweb/Pangolin/g' "/tmp/index.html.template"
        else
            # For non-AgentGateway deployments
            if [ -z "${OPENAI_API_KEY:-}" ]; then
                echo "Removing Nlweb section from template as OPENAI_API_KEY is not set"
                sed -i '/<!-- Start of Nlweb -->/,/<!-- End of Nlweb -->/d' "/tmp/index.html.template"
                sed -i 's/Pangolin • Nlweb/Pangolin/g' "/tmp/index.html.template"
            fi

            # Remove IdP section if not in component list
            if ! echo "${COMPONENTS_CSV:-}" | grep -q "idp"; then
                echo "Removing IdP section from template as 'idp' is not in COMPONENTS_CSV"
                sed -i '/<!-- Start of IDP -->/,/<!-- End of IDP -->/d' "/tmp/index.html.template"
                sed -i '/<!-- COMPONENT_CONDITIONAL_IDP_START -->/,/<!-- COMPONENT_CONDITIONAL_IDP_END -->/d' "/tmp/index.html.template"
                sed -i 's/Pangolin • Idp/Pangolin/g' "/tmp/index.html.template"
            fi
            
            # Remove chatkit sections for non-AgentGateway deployments
            echo "Removing Chatkit sections from template (not AgentGateway deployment)"
            sed -i '/<!-- Start of Chatkit -->/,/<!-- End of Chatkit -->/d' "/tmp/index.html.template"
            sed -i '/<!-- Start of Chatkit Admin -->/,/<!-- End of Chatkit Admin -->/d' "/tmp/index.html.template"
        fi

        # If KOMODO_HOST_IP is not set, remove the Komodo section from the template
        if [ -z "${KOMODO_HOST_IP:-}" ]; then
            echo "Removing Komodo section from template as KOMODO_HOST_IP is not set"
            
            # Use sed to remove everything between the start and end Komodo comments
            sed -i '/<!-- Start of Komodo -->/,/<!-- End of Komodo -->/d' "/tmp/index.html.template"
            
            # Also remove Komodo from the welcome screen grid
            sed -i 's/Pangolin • Komodo/Pangolin/g' "/tmp/index.html.template"
        fi
        
        # Replace domain placeholders and custom subdomains
        cp "/tmp/index.html.template" "/tmp/index.html.processing"

        # Replace main domain
        sed -i "s/yourdomain\.com/${DOMAIN}/g" "/tmp/index.html.processing"

        # Replace admin subdomain (pangolin admin interface)
        sed -i "s/subdomain/${ADMIN_SUBDOMAIN}/g" "/tmp/index.html.processing"

        # Replace component-specific subdomains if provided
        if [ -n "${MIDDLEWARE_MANAGER_SUBDOMAIN:-}" ]; then
            sed -i "s/middleware-manager\.${DOMAIN}/${MIDDLEWARE_MANAGER_SUBDOMAIN}.${DOMAIN}/g" "/tmp/index.html.processing"
        fi

        if [ -n "${TRAEFIK_SUBDOMAIN:-}" ]; then
            sed -i "s/traefik\.${DOMAIN}/${TRAEFIK_SUBDOMAIN}.${DOMAIN}/g" "/tmp/index.html.processing"
        fi

        if [ -n "${KOMODO_SUBDOMAIN:-}" ]; then
            sed -i "s/komodo\.${DOMAIN}/${KOMODO_SUBDOMAIN}.${DOMAIN}/g" "/tmp/index.html.processing"
        fi

        if [ -n "${NLWEB_SUBDOMAIN:-}" ]; then
            sed -i "s/nlweb\.${DOMAIN}/${NLWEB_SUBDOMAIN}.${DOMAIN}/g" "/tmp/index.html.processing"
        fi

        if [ -n "${LOGS_SUBDOMAIN:-}" ]; then
            sed -i "s/logs\.${DOMAIN}/${LOGS_SUBDOMAIN}.${DOMAIN}/g" "/tmp/index.html.processing"
        fi

        # Write to final location
        cp "/tmp/index.html.processing" /host-setup/public_html/index.html

        # Clean up temporary files
        rm "/tmp/index.html.template" "/tmp/index.html.processing"
    else
        echo "Template not found, using embedded version"
        # Create basic index.html (fallback to embedded version)
        cat > /host-setup/public_html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>AI Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-white font-sans h-screen overflow-hidden">
    <div class="flex items-center justify-center h-full">
        <div class="text-center">
            <h1 class="text-4xl font-bold mb-4">Welcome to AI</h1>
            <p class="text-xl text-gray-300">Your deployment is ready</p>
        </div>
    </div>
</body>
</html>
EOF
    fi
}

# Function to modify dynamic_config.yml to add static page middlewares and routing
modify_dynamic_config() {
    echo "🔧 Modifying Traefik dynamic configuration for static page..."
    
    local config_file="/host-setup/config/traefik/rules/dynamic_config.yml"
    
    if [ ! -f "$config_file" ]; then
        echo "⚠️ Warning: dynamic_config.yml not found at $config_file"
        return 1
    fi
    
    # Create a temporary file for the new configuration
    local temp_file="/tmp/dynamic_config_temp.yml"
    
    # Read the existing file and add static page configuration
    awk '
    /scheme: https/ {
        print $0
        print "    security-headers:"
        print "      headers:"
        print "        customResponseHeaders:"
        print "          Server: \"\""
        print "          X-Powered-By: \"\""
        print "          X-Forwarded-Proto: \"https\""
        print "          Content-Security-Policy: \"frame-ancestors '\''self'\'' https://" ENVIRON["STATIC_PAGE_SUBDOMAIN"] "." ENVIRON["DOMAIN"] "\""
        print "        contentTypeNosniff: true"
        print "        referrerPolicy: \"strict-origin-when-cross-origin\""
        print "        forceSTSHeader: true"
        print "        stsIncludeSubdomains: true"
        print "        stsSeconds: 63072000"
        print "        stsPreload: true"
        print "    statiq:"
        print "      plugin:"
        print "        statiq:"
        print "          enableDirectoryListing: false"
        print "          indexFiles:"
        print "            - index.html"
        print "            - index.htm"
        print "          root: /var/www/html"
        print "          spaIndex: index.html"
        print "          spaMode: false"
        next
    }
    /^  routers:/ {
        print $0
        # Add static page routers after the routers section starts
        getline; print  # Print the next line (likely a router definition)
        while (getline && !/^  services:/) {
            print
        }
        # Now add static page routers before services
        print ""
        print "    statiq-router-redirect:"
        print "      rule: \"Host(\`" ENVIRON["STATIC_PAGE_SUBDOMAIN"] "." ENVIRON["DOMAIN"] "\`)\""
        print "      service: statiq-service"
        print "      entryPoints:"
        print "        - web"
        print "      middlewares:"
        print "        - redirect-to-https"
        print ""
        print "    statiq-router:"
        print "      entryPoints:"
        print "        - websecure"
        print "      middlewares:"
        print "        - statiq"
        print "      service: statiq-service"
        print "      priority: 100"
        print "      rule: \"Host(\`" ENVIRON["STATIC_PAGE_SUBDOMAIN"] "." ENVIRON["DOMAIN"] "\`)\""
        print ""
        print $0  # Print the services line
        next
    }
    /^    api-service:/ {
        # We found the api-service, add statiq service after the existing ones
        print $0
        getline; print  # loadBalancer line
        getline; print  # servers line
        getline; print  # url line
        print ""
        print "    statiq-service:"
        print "      loadBalancer:"
        print "        servers:"
        print "          - url: \"noop@internal\""
        next
    }
    { print }
    ' "$config_file" > "$temp_file"
    
    # Replace the original file
    mv "$temp_file" "$config_file"
    
    echo "✅ Dynamic configuration updated for static page"
}

# Main execution
if [ -n "${STATIC_PAGE_SUBDOMAIN:-}" ]; then
    echo "🛡️ Static page detected - setting up..."
    create_static_page_html
    modify_dynamic_config
    echo "✅ Static page component setup complete"
else
    echo "⚠️ STATIC_PAGE_SUBDOMAIN not set, skipping static page setup"
fi
