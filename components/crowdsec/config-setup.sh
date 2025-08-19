# CrowdSec setup additions

# Directories
mkdir -p /host-setup/config/crowdsec/db
mkdir -p /host-setup/config/crowdsec/acquis.d
mkdir -p /host-setup/config/traefik/logs
mkdir -p /host-setup/config/traefik/conf
mkdir -p /host-setup/config/crowdsec_logs

# Config files
cat > /host-setup/config/crowdsec/acquis.yaml << 'EOF'
poll_without_inotify: false
filenames:
  - /var/log/traefik/*.log
labels:
  type: traefik
---
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: myAppSecComponent
source: appsec
labels:
  type: appsec
EOF

cat > /host-setup/config/crowdsec/profiles.yaml << 'EOF'
name: captcha_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.GetScenario() contains "http"
decisions:
  - type: captcha
    duration: 4h
on_success: break

---
name: default_ip_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
 - type: ban
   duration: 4h
on_success: break

---
name: default_range_remediation
filters:
 - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
 - type: ban
   duration: 4h
on_success: break
EOF

wget -O /host-setup/config/traefik/conf/captcha.html https://gist.githubusercontent.com/hhftechnology/48569d9f899bb6b889f9de2407efd0d2/raw/captcha.html

# Dynamic config middleware augment
cat > /host-setup/config/traefik/rules/dynamic_config.yml << EOF
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
    security-headers:
      headers:
        customResponseHeaders:
          Server: ""
          X-Powered-By: ""
          X-Forwarded-Proto: "https"
          Content-Security-Policy: "frame-ancestors 'self' https://${STATIC_PAGE_DOMAIN}.${DOMAIN}"
        contentTypeNosniff: true
        referrerPolicy: "strict-origin-when-cross-origin"
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsSeconds: 63072000
        stsPreload: true
    statiq:
      plugin:
        statiq:
          enableDirectoryListing: false
          indexFiles:
            - index.html
            - index.htm
          root: /var/www/html
          spaIndex: index.html
          spaMode: false

  routers:
    # HTTP to HTTPS redirect router
    main-app-router-redirect:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: next-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # Next.js router (handles everything except API and WebSocket paths)
    next-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && !PathPrefix(\`/api/v1\`)"
      service: next-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # API router (handles /api/v1 paths)
    api-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`) && PathPrefix(\`/api/v1\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    # WebSocket router
    ws-router:
      rule: "Host(\`${ADMIN_SUBDOMAIN}.${DOMAIN}\`)"
      service: api-service
      entryPoints:
        - websecure
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

    statiq-router-redirect:
      rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"
      service: statiq-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    statiq-router:
      entryPoints:
        - websecure
      middlewares:
        - statiq
      service: statiq-service
      priority: 100
      rule: "Host(\`${STATIC_PAGE_DOMAIN}.${DOMAIN}\`)"

    # Add these lines for mcpauth
    # mcpauth http redirect router
    mcpauth-router-redirect:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
      entryPoints:
        - web
      middlewares:
        - redirect-to-https

    # mcpauth router
    mcpauth:
      rule: "Host(\`oauth.${DOMAIN}\`)"
      service: mcpauth-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    next-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3002" # Next.js server

    api-service:
      loadBalancer:
        servers:
          - url: "http://pangolin:3000" # API/WebSocket server

    statiq-service:
      loadBalancer:
        servers:
          - url: "noop@internal"

    mcpauth-service:
      loadBalancer:
        servers:
          - url: "http://mcpauth:11000"  # mcpauth auth server

    oauth-service:
      loadBalancer:
        servers:
          - url: "https://oauth.${DOMAIN}"
EOF

# Deployment info additions
cat >> /host-setup/DEPLOYMENT_INFO.txt << 'EOF'
└── crowdsec/
    ├── acquis.yaml
    ├── config.yaml
    └── profiles.yaml
📁 Additional:
./crowdsec_logs/          # Log volume for CrowdSec

🛡️ CrowdSec Notes:
- AppSec and log parsing is configured
- Prometheus and API are enabled
- CAPTCHA and remediation profiles are active
- Remember to get the bouncer API key after containers start:
  docker exec crowdsec cscli bouncers add traefik-bouncer
EOF

