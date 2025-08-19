#!/bin/sh
# MCPAuth component setup
set -e

echo "🔐 Setting up MCPAuth component..."

# Function to add MCPAuth routing to dynamic_config.yml
add_mcpauth_routing() {
    echo "🔧 Adding MCPAuth routing to Traefik dynamic configuration..."

    local config_file="/host-setup/config/traefik/rules/dynamic_config.yml"

    if [ ! -f "$config_file" ]; then
        echo "⚠️ Warning: dynamic_config.yml not found at $config_file"
        return 1
    fi

    # Create a temporary file for the new configuration
    local temp_file="/tmp/dynamic_config_mcpauth_temp.yml"

    # Read the existing file and add MCPAuth routing
    awk '
    /^  routers:/ {
        print $0
        # Add MCPAuth routers after the routers section starts
        getline; print  # Print the next line (likely a router definition)
        while (getline && !/^  services:/) {
            print
        }
        # Now add MCPAuth routers before services
        print ""
        print "    # MCPAuth http redirect router"
        print "    mcpauth-router-redirect:"
        print "      rule: \"Host(\`oauth." ENVIRON["DOMAIN"] "\`)\""
        print "      service: mcpauth-service"
        print "      entryPoints:"
        print "        - web"
        print "      middlewares:"
        print "        - redirect-to-https"
        print ""
        print "    # MCPAuth router"
        print "    mcpauth:"
        print "      rule: \"Host(\`oauth." ENVIRON["DOMAIN"] "\`)\""
        print "      service: mcpauth-service"
        print "      entryPoints:"
        print "        - websecure"
        print "      tls:"
        print "        certResolver: letsencrypt"
        print ""
        print $0  # Print the services line
        next
    }
    /^    api-service:/ {
        # We found the api-service, add mcpauth service after the existing ones
        print $0
        getline; print  # loadBalancer line
        getline; print  # servers line
        getline; print  # url line
        print ""
        print "    mcpauth-service:"
        print "      loadBalancer:"
        print "        servers:"
        print "          - url: \"http://mcpauth:11000\"  # mcpauth auth server"
        print ""
        print "    oauth-service:"
        print "      loadBalancer:"
        print "        servers:"
        print "          - url: \"https://oauth." ENVIRON["DOMAIN"] "\""
        next
    }
    { print }
    ' "$config_file" > "$temp_file"

    # Replace the original file
    mv "$temp_file" "$config_file"

    echo "✅ MCPAuth routing added to dynamic config"
}

# Add MCPAuth routing to existing dynamic config
add_mcpauth_routing

echo "✅ MCPAuth component setup complete"

