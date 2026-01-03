#!/bin/sh
# MCP Gateway component setup
set -e

echo "🤖 Setting up MCP Gateway component..."

# Use ROOT_HOST_DIR if set, otherwise default to /host-setup
ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"

# Create necessary directories
mkdir -p "$ROOT_HOST_DIR/config/mcp-gateway"

# Create seed.json for MCP Registry
echo "📝 Creating MCP Registry seed configuration..."
cat > "$ROOT_HOST_DIR/config/mcp-gateway/seed.json" << 'EOF'
{
  "servers": []
}
EOF

# Create langwatch.env file with defaults
echo "📝 Creating LangWatch environment configuration..."
cat > "$ROOT_HOST_DIR/config/mcp-gateway/langwatch.env" << EOF
# LangWatch Configuration
# Add your API keys here
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GEMINI_API_KEY=${GEMINI_API_KEY:-}
EOF

# Enable Pangolin Integration API by modifying config.yml
echo "🔧 Enabling Pangolin Integration API..."
if [ -f "$ROOT_HOST_DIR/config/config.yml" ]; then
    # Check if enable_integration_api is already in the flags section
    if grep -q "enable_integration_api" "$ROOT_HOST_DIR/config/config.yml"; then
        echo "✅ Integration API already configured in config.yml"
    else
        # Add enable_integration_api to the flags section
        # Use sed to add the line after the flags: section
        if grep -q "^flags:" "$ROOT_HOST_DIR/config/config.yml"; then
            # Create a temp file with the modification
            sed '/^flags:/a\    enable_integration_api: true' "$ROOT_HOST_DIR/config/config.yml" > "$ROOT_HOST_DIR/config/config.yml.tmp"
            mv "$ROOT_HOST_DIR/config/config.yml.tmp" "$ROOT_HOST_DIR/config/config.yml"
            echo "✅ Added enable_integration_api: true to flags section"
        else
            echo "⚠️ Could not find flags section in config.yml"
        fi
    fi
else
    echo "⚠️ config.yml not found - it will be created by the base platform component"
fi

# Get subdomain settings with defaults
MCP_GATEWAY_SUBDOMAIN="${MCP_GATEWAY_SUBDOMAIN:-mcpgateway}"
OPENMEMORY_SUBDOMAIN="${OPENMEMORY_SUBDOMAIN:-memory}"
LANGWATCH_SUBDOMAIN="${LANGWATCH_SUBDOMAIN:-langwatch}"
PANGOLIN_API_SUBDOMAIN="${PANGOLIN_API_SUBDOMAIN:-api}"

# Add traefik routing for the MCP Gateway services
# Create a separate config file for MCP Gateway routes (Traefik will load all files from /rules)
echo "🌐 Adding Traefik routing for MCP Gateway services..."
if [ -d "$ROOT_HOST_DIR/config/traefik/rules" ]; then
    cat > "$ROOT_HOST_DIR/config/traefik/rules/mcp-gateway.yml" << EOF
# ================================
# MCP Gateway Traefik Configuration
# ================================
http:
  routers:
    # Pangolin Integration API (HTTP redirect)
    int-api-router-redirect:
      rule: "Host(\`${PANGOLIN_API_SUBDOMAIN}.${DOMAIN}\`)"
      service: int-api-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https@file

    # Pangolin Integration API (HTTPS)
    int-api-router:
      rule: "Host(\`${PANGOLIN_API_SUBDOMAIN}.${DOMAIN}\`)"
      service: int-api-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # MCP Gateway App (HTTP redirect)
    mcp-gateway-router-redirect:
      rule: "Host(\`${MCP_GATEWAY_SUBDOMAIN}.${DOMAIN}\`)"
      service: mcp-gateway-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https@file

    # MCP Gateway App (HTTPS)
    mcp-gateway-router:
      rule: "Host(\`${MCP_GATEWAY_SUBDOMAIN}.${DOMAIN}\`)"
      service: mcp-gateway-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # OpenMemory (HTTP redirect)
    openmemory-router-redirect:
      rule: "Host(\`${OPENMEMORY_SUBDOMAIN}.${DOMAIN}\`)"
      service: openmemory-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https@file

    # OpenMemory (HTTPS)
    openmemory-router:
      rule: "Host(\`${OPENMEMORY_SUBDOMAIN}.${DOMAIN}\`)"
      service: openmemory-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    # LangWatch (HTTP redirect)
    langwatch-router-redirect:
      rule: "Host(\`${LANGWATCH_SUBDOMAIN}.${DOMAIN}\`)"
      service: langwatch-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https@file

    # LangWatch (HTTPS)
    langwatch-router:
      rule: "Host(\`${LANGWATCH_SUBDOMAIN}.${DOMAIN}\`)"
      service: langwatch-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    # Pangolin Integration API Service
    int-api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3003"

    # MCP Gateway Service
    mcp-gateway-service:
      loadBalancer:
        servers:
          - url: "http://mcp-gateway:3000"

    # OpenMemory Service
    openmemory-service:
      loadBalancer:
        servers:
          - url: "http://openmemory:8765"

    # LangWatch Service
    langwatch-service:
      loadBalancer:
        servers:
          - url: "http://langwatch-app:5560"
EOF
    echo "✅ Created MCP Gateway Traefik configuration at config/traefik/rules/mcp-gateway.yml"
else
    echo "⚠️ Traefik rules directory not found - it will be created by the base platform component"
fi

echo "✅ MCP Gateway component setup complete"

