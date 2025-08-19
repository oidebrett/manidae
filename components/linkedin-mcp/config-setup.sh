# LinkedIn MCP config generator
mkdir -p /host-setup/config/linkedin-mcp
cat > /host-setup/config/linkedin-mcp/.env << EOF
PORT=${LINKEDIN_MCP_PORT:-18000}
LINKEDIN_USERNAME=${LINKEDIN_USERNAME}
LINKEDIN_PASSWORD=${LINKEDIN_PASSWORD}
EOF

