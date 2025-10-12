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

echo "📁 Updating the middleware-manager templates for mcp auth..."

TEMPLATES_FILE="/host-setup/config/middleware-manager/templates.yml"

# Ensure file exists
if [ ! -f "$TEMPLATES_FILE" ]; then
  echo "❌ Error: $TEMPLATES_FILE not found!"
  exit 1
fi

# Function to append a middleware block if not already present
add_middleware_if_missing() {
  local id="$1"
  local yaml_block="$2"

  if grep -q "^[[:space:]]*- id: ${id}\b" "$TEMPLATES_FILE"; then
    echo "✅ Middleware '${id}' already exists. Skipping."
  else
    echo "➕ Adding middleware '${id}'..."
    printf "\n%s\n" "$yaml_block" >> "$TEMPLATES_FILE"
  fi
}

# --- Define YAML blocks ---

mcp_auth=$(cat <<'YAML'
  - id: mcp-auth
    name: MCP Auth (Forward Authentication)
    type: forwardAuth
    config:
      address: "http://mcpauth:11000/auth"
      authResponseHeaders:
        - "X-Forwarded-User"
YAML
)

mcp_cors_headers=$(cat <<'YAML'
  - id: mcp-cors-headers
    name: MCP CORS Headers
    type: headers
    config:
      accessControlAllowCredentials: true
      accessControlAllowHeaders:
        - "Authorization"
        - "Content-Type"
        - "mcp-protocol-version"
      accessControlAllowMethods:
        - "GET"
        - "POST"
        - "OPTIONS"
      accessControlAllowOriginList:
        - "*"
      accessControlMaxAge: 86400
      addVaryHeader: true
YAML
)

mcp_redirect_regex=$(cat <<'YAML'
  - id: mcp-redirect-regex
    name: MCP Redirect Regex
    type: redirectRegex
    config:
      permanent: true
      regex: "^https://([a-z0-9-]+)\\.(.+)/\\.well-known/(oauth-authorization-server|openid-configuration)(.*)?"
      replacement: "https://oauth.${2}/.well-known/${3}${4}"
YAML
)

mcp_security_chain=$(cat <<'YAML'
  - id: mcp-security-chain
    name: MCP Security Chain
    type: chain
    config:
      middlewares:
        - "mcp-cors-headers@file"
        - "mcp-redirect-regex@file"
        - "mcp-auth@file"
YAML
)

# --- Append if missing ---
add_middleware_if_missing "mcp-auth" "$mcp_auth"
add_middleware_if_missing "mcp-cors-headers" "$mcp_cors_headers"
add_middleware_if_missing "mcp-redirect-regex" "$mcp_redirect_regex"
add_middleware_if_missing "mcp-security-chain" "$mcp_security_chain"

echo "✅ Done updating $TEMPLATES_FILE"

echo "✅ Middleware Manager setup complete"
