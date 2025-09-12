#!/bin/bash
set -euo pipefail

# --- Check for container name argument ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <container-name>"
  exit 1
fi

container="$1"

# --- 1. Generate API key ---
key=$(docker exec -i "$container" \
  cscli bouncers add traefik-bouncer 2>&1 \
  | grep -Eo '[A-Za-z0-9+/=]{20,}' | head -n1)

if [ -z "$key" ]; then
  echo "❌ Failed to generate API key from container: $container"
  exit 1
fi

echo "✅ Generated API key: $key"

# --- 2. Replace placeholder in YAML files ---
for file in config/traefik/rules/resource-overrides.yml \
            config/middleware-manager/templates.yaml; do
  if [ -f "$file" ]; then
    sed -i.bak "s|PUT_YOUR_BOUNCER_KEY_HERE_OR_IT_WILL_NOT_WORK|$key|" "$file"
    echo "🔄 Updated $file"
  else
    echo "⚠️ File not found: $file"
  fi
done

# --- 3. Update SQLite database ---
sqlite3 data/middleware.db <<EOF
UPDATE middlewares
SET config = REPLACE(config, 'PUT_YOUR_BOUNCER_KEY_HERE_OR_IT_WILL_NOT_WORK', '$key'),
    updated_at = CURRENT_TIMESTAMP
WHERE id = 'crowdsec';
EOF

echo "💾 Updated SQLite middleware entry"
