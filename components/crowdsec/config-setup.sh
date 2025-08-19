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

# CrowdSec does not need to modify dynamic_config.yml
# The routing and services are handled by pangolin and other components
# CrowdSec only provides security scanning and bouncer functionality


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

