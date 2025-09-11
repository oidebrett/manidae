# 🛡️ Securing Your Coolify Deployment with CrowdSec Integration

This guide walks you through integrating **CrowdSec** with your Coolify deployment to provide comprehensive security protection. CrowdSec is a community-powered, open-source intrusion prevention system (IPS) that analyzes server logs in real time, detects suspicious behavior, and automatically blocks malicious IPs using a global threat intelligence network.

---

## ✨ Two Deployment Methods Available

You can integrate CrowdSec with Coolify using either:

1. **🚀 Automated Setup** - Using the docker-compose-setup generator (recommended)
2. **⚙️ Manual Setup** - Step-by-step manual configuration

Both methods use **Docker containers** for CrowdSec (no apt installation required) and integrate seamlessly with Coolify's Traefik proxy.

---

## 🔍 What CrowdSec Provides

- **Real-time threat detection** from Traefik access logs
- **Automatic IP blocking** for malicious traffic
- **Community threat intelligence** sharing
- **CAPTCHA challenges** for suspicious users
- **AppSec WAF protection** against common web attacks
- **Prometheus metrics** for monitoring
- **Global dashboard** at app.crowdsec.net (optional)

---

## 🚀 Method 1: Automated Setup with Docker Compose

The easiest way to deploy Coolify with CrowdSec is using the automated setup generator. This will install Coolify and Crowdsec together.

### Step 1: Clone the Manidae Repository - this is a Docker config generator

```bash
git clone https://github.com/oidebrett/manidae.git
cd manidae
```

### Step 1: Get Your CrowdSec Enrollment Key

1. Sign up at [app.crowdsec.net](https://app.crowdsec.net/signup)
2. Create a new instance and copy the enrollment key
3. Use this key in the `CROWDSEC_ENROLLMENT_KEY` variable

### Step 2: Run the Automated Setup

From your project root, run:

```bash
DOMAIN=contextware.ai ADMIN_SUBDOMAIN=coolify COMPONENTS="coolify+" CROWDSEC_ENROLLMENT_KEY=REPLACE_WITH_YOUR_KEY docker compose -f docker-compose-setup.yml up
```

> ✅ **Required Variables:**
> - `DOMAIN` - Your domain name (e.g., `contextware.ai`)
> - `ADMIN_SUBDOMAIN` - Subdomain for Coolify admin (e.g., `coolify`)
> - `COMPONENTS` - Set to `coolify+` to include CrowdSec
> - `CROWDSEC_ENROLLMENT_KEY` - Your enrollment key from app.crowdsec.net


### Step 3: Complete Post-Deployment Setup

After the automated setup completes, you'll need to perform these manual steps:

```bash
# 1. Enable Coolify proxy logging (REQUIRED)
cp config/coolify/proxy/docker-compose.override.yml /data/coolify/proxy/

```

### Step 4: Start the Coolify Stack

```bash
docker compose up -d

# 2. Get the bouncer API key
docker exec coolify-crowdsec cscli bouncers add traefik-bouncer

# 3. Update the CrowdSec plugin with your API key
sed -i 's/PASTE_YOUR_KEY_HERE/YOUR_ACTUAL_API_KEY/' config/coolify/proxy/dynamic/crowdsec-plugin.yml

# 4. Copy CrowdSec plugin files to Coolify
cp config/coolify/proxy/dynamic/crowdsec-plugin.yml /data/coolify/proxy/dynamic/
cp config/coolify/proxy/captcha.html /data/coolify/proxy/

# 5. Restart Coolify proxy to apply changes
docker restart coolify-proxy
```

PLEASE NOTE: the crowdsec container in the automated install will be called `manidae_crowdsec_1` or whatever is the project name.
Please use the correct container name when running the debugging commands below.

---

## ⚙️ Method 2: Manual Setup

If you prefer manual configuration or want to add CrowdSec to an existing Coolify deployment

### Pre-requisites:
This guide assumes Coolify is already deployed and running as per the following guide:
https://coolify.io/docs/get-started/installation#manual-installation


### Step 1: Prepare Server Prerequisites

Ensure your server has the required Coolify directory structure:

```bash
# Create required directories
sudo mkdir -p /data/coolify/proxy/dynamic
sudo mkdir -p /data/coolify/ssh
sudo mkdir -p /data/coolify/applications
sudo mkdir -p /data/coolify/databases
sudo mkdir -p /data/coolify/services
sudo mkdir -p /data/coolify/backups

# Set proper permissions
sudo chown -R 1000:1000 /data/coolify
```

### Step 2: Create CrowdSec Configuration Files

Create the CrowdSec configuration directory and files:

```bash
# Create config directories
mkdir -p config/crowdsec/db
mkdir -p config/crowdsec/acquis.d
mkdir -p config/crowdsec_logs
mkdir -p config/coolify/proxy
```

Create `config/crowdsec/acquis.yaml`:

```yaml
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
```

Create `config/crowdsec/profiles.yaml`:

```yaml
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
```

### Step 3: Create Coolify Proxy Configuration Files

Create `config/coolify/proxy/docker-compose.override.yml`:

```yaml
# Coolify Proxy Logging Override
# This file enables access logging for Coolify's Traefik proxy

services:
  coolify-proxy:
    command:
      - '--ping=true'
      - '--ping.entrypoint=http'
      - '--api.dashboard=true'
      - '--entrypoints.http.address=:80'
      - '--entrypoints.https.address=:443'
      - '--entrypoints.http.http.encodequerysemicolons=true'
      - '--entryPoints.http.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http.encodequerysemicolons=true'
      - '--entryPoints.https.http2.maxConcurrentStreams=250'
      - '--entrypoints.https.http3'
      - '--providers.file.directory=/traefik/dynamic/'
      - '--providers.file.watch=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge=true'
      - '--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http'
      - '--certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json'
      - '--api.insecure=false'
      - '--providers.docker=true'
      - '--providers.docker.exposedbydefault=false'
      # 🔽 Added log settings
      - '--log.format=json'
      - '--log.level=INFO'
      - '--accesslog=true'
      - '--accesslog.format=json'
      - '--accesslog.filepath=/traefik/access.log'
```

Create `config/coolify/proxy/dynamic/crowdsec-plugin.yml`:

```yaml
http:
  middlewares:
    crowdsec:
      plugin:
        crowdsec-bouncer:
          crowdsecMode: live
          crowdsecLapiHost: 'crowdsec:8080'
          crowdsecLapiKey: 'PASTE_YOUR_KEY_HERE'
          enabled: true
```

### Step 4: Create Docker Compose Overlay

Create `docker-compose.overlay.yml` to add CrowdSec to your existing Coolify deployment:

```yaml
# CrowdSec Integration Overlay for Coolify
# This file adds CrowdSec integration to the base Coolify deployment

services:
  # Add CrowdSec service to the stack
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: coolify-crowdsec
    environment:
      GID: "1000"
      COLLECTIONS: crowdsecurity/traefik crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules crowdsecurity/linux
      ENROLL_INSTANCE_NAME: "${CROWDSEC_INSTANCE_NAME:-pangolin-crowdsec}"
      PARSERS: crowdsecurity/whitelists
      ENROLL_TAGS: docker
      ENROLL_KEY: REPLACE_WITH_YOUR_KEY
    healthcheck:
      interval: 10s
      retries: 15
      timeout: 10s
      test: ["CMD", "cscli", "capi", "status"]
    labels:
      - "traefik.enable=false" # Disable traefik for crowdsec
    volumes:
      # crowdsec container data
      - ./config/crowdsec:/etc/crowdsec # crowdsec config
      - ./config/crowdsec/db:/var/lib/crowdsec/data # crowdsec db
      # log bind mounts into crowdsec (platform-specific)
      - /data/coolify/proxy:/var/log/traefik # traefik logs
      - ./config/coolify/proxy/captcha.html:/etc/traefik/conf/captcha.html
    ports:
      - 6060:6060 # metrics endpoint for prometheus
    restart: unless-stopped
    command: -t # Add test config flag to verify configuration
    networks:
      - ${CROWDSEC_NETWORK:-default}
```

### Step 5: Create CAPTCHA Page

Create `config/coolify/proxy/captcha.html` for the CAPTCHA challenge page:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <title>CrowdSec Captcha</title>
  <meta content="text/html; charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    /* Tailwind CSS styles for the CAPTCHA page */
    body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 0; padding: 1rem; height: 100vh; display: flex; align-items: center; justify-content: center; }
    .container { border: 2px solid #000; border-radius: 0.75rem; padding: 1rem; text-align: center; width: 100%; max-width: 500px; }
    .title { font-size: 1.5rem; font-weight: 700; margin: 1rem 0; }
    .icon { height: 6rem; width: 6rem; margin: 0 auto 1rem; }
  </style>
  <script src="{{ .FrontendJS }}" async defer></script>
</head>
<body>
  <div class="container">
    <svg class="icon" fill="black" viewBox="0 0 576 512">
      <path d="M569.517 440.013C587.975 472.007 564.806 512 527.94 512H48.054c-36.937 0-59.999-40.055-41.577-71.987L246.423 23.985c18.467-32.009 64.72-31.951 83.154 0l239.94 416.028zM288 354c-25.405 0-46 20.595-46 46s20.595 46 46 46 46-20.595 46-46-20.595-46-46-46zm-43.673-165.346l7.418 136c.347 6.364 5.609 11.346 11.982 11.346h48.546c6.373 0 11.635-4.982 11.982-11.346l7.418-136c.375-6.874-5.098-12.654-11.982-12.654h-63.383c-6.884 0-12.356 5.78-11.981 12.654z"/>
    </svg>
    <h1 class="title">CrowdSec Captcha</h1>
    <form action="" method="POST" id="captcha-form">
      <div id="captcha" class="{{ .FrontendKey }}" data-sitekey="{{ .SiteKey }}" data-callback="captchaCallback"></div>
    </form>
    <p>This security check has been powered by <a href="https://crowdsec.net/" target="_blank">CrowdSec</a></p>
  </div>
  <script>
    function captchaCallback() {
      setTimeout(() => document.querySelector('#captcha-form').submit(), 500);
    }
  </script>
</body>
</html>
```

### Step 6: Deploy CrowdSec with Coolify

Deploy your Coolify stack with CrowdSec integration:

```bash
# Deploy using the overlay file
docker compose -f docker-compose.yml -f docker-compose.overlay.yml up -d
```

### Step 7: Complete Manual Post-Deployment Setup

After deployment, complete the integration:

```bash
# 1. Enable Coolify proxy logging (REQUIRED)
cp config/coolify/proxy/docker-compose.override.yml /data/coolify/proxy/
docker restart coolify-proxy

# 2. Get the bouncer API key
docker exec coolify-crowdsec cscli bouncers add traefik-bouncer

# 3. Update the CrowdSec plugin with your API key
sed -i 's/PASTE_YOUR_KEY_HERE/YOUR_ACTUAL_API_KEY/' config/coolify/proxy/dynamic/crowdsec-plugin.yml

# 4. Copy CrowdSec plugin files to Coolify
cp config/coolify/proxy/dynamic/crowdsec-plugin.yml /data/coolify/proxy/dynamic/
cp config/coolify/proxy/captcha.html /data/coolify/proxy/

# 5. Restart Coolify proxy to apply changes
docker restart coolify-proxy
```

---

## 🔧 Understanding the Integration

### How CrowdSec Works with Coolify

1. **Log Collection**: Coolify's Traefik proxy writes access logs to `/data/coolify/proxy/access.log`
2. **Log Analysis**: CrowdSec container monitors these logs for suspicious patterns
3. **Decision Making**: When threats are detected, CrowdSec creates blocking decisions
4. **Enforcement**: The CrowdSec Traefik plugin queries the CrowdSec API and blocks malicious IPs
5. **User Experience**: Suspicious users may see a CAPTCHA challenge before accessing your sites

### Key Components

- **CrowdSec Container**: Runs threat detection and maintains the decision database
- **Traefik Plugin**: Integrates with Coolify's proxy to enforce blocking decisions
- **Access Logs**: Enable Traefik to log all HTTP requests for analysis
- **CAPTCHA Page**: Provides a user-friendly challenge for suspicious traffic

---

## 🧪 Testing Your CrowdSec Integration

### Step 1: Verify CrowdSec is Running

```bash
# Check CrowdSec container status
docker ps | grep crowdsec

# Check CrowdSec metrics
docker exec coolify-crowdsec cscli metrics

# Verify log parsing
docker exec coolify-crowdsec cscli metrics | grep -A 10 "Local API Metrics"
```

### Step 2: Test Blocking Functionality

```bash
# Manually block an IP for testing
docker exec coolify-crowdsec cscli decisions add -i 1.2.3.4 -d 10m

# View active decisions
docker exec coolify-crowdsec cscli decisions list

# Remove the test block
docker exec coolify-crowdsec cscli decisions delete -i 1.2.3.4
```

### Step 3: Monitor Real Traffic

```bash
# Watch access logs being generated
tail -f /data/coolify/proxy/access.log

# Monitor CrowdSec alerts
docker exec coolify-crowdsec cscli alerts list

# Check bouncer metrics
docker exec coolify-crowdsec cscli bouncers list
```

---

## 📊 Monitoring and Management

### CrowdSec Console Dashboard

If you enrolled your instance with CrowdSec.net, you can monitor your deployment at:
- **Dashboard**: [app.crowdsec.net](https://app.crowdsec.net)
- **View blocked IPs**, attack patterns, and global threat intelligence
- **Configure alerts** and notifications
- **Share threat intelligence** with the community

### Local Monitoring

```bash
# View real-time metrics
docker exec coolify-crowdsec cscli metrics

# Check parser status
docker exec coolify-crowdsec cscli parsers list

# View collections
docker exec coolify-crowdsec cscli collections list

# Monitor hub updates
docker exec coolify-crowdsec cscli hub update
```

---

## 🔒 Security Best Practices

### Recommended Configuration

1. **Enable enrollment** with CrowdSec.net for threat intelligence
2. **Monitor logs regularly** to ensure proper parsing
3. **Update collections** periodically for new threat signatures
4. **Configure alerts** for critical security events
5. **Test blocking** functionality regularly

### Network Security

- CrowdSec API runs on port `8080` (internal to Docker network)
- Prometheus metrics available on port `6060` (optional monitoring)
- All communication between Traefik and CrowdSec uses `host.docker.internal`

---

## 🚨 Troubleshooting

### Common Issues

**CrowdSec not parsing logs:**
```bash
# Check if access.log is being created
ls -la /data/coolify/proxy/access.log

# Verify log format
tail /data/coolify/proxy/access.log

# Check CrowdSec acquisition status
docker exec coolify-crowdsec cscli metrics | grep -A 5 "Acquisition Metrics"
```

**Traefik plugin not working:**
```bash
# Verify plugin configuration
cat /data/coolify/proxy/dynamic/crowdsec-plugin.yml

# Check Traefik logs
docker logs coolify-proxy

# Verify bouncer API key
docker exec coolify-crowdsec cscli bouncers list
```

**CAPTCHA page not displaying:**
```bash
# Check if captcha.html exists
ls -la /data/coolify/proxy/captcha.html

# Verify Traefik can access the file
docker exec coolify-proxy ls -la /traefik/captcha.html
```

---

## 🎯 What You've Achieved

After completing this setup, you now have:

✅ **Comprehensive threat protection** for all Coolify-hosted applications
✅ **Real-time log analysis** and automatic IP blocking
✅ **CAPTCHA challenges** for suspicious users
✅ **Community threat intelligence** integration
✅ **AppSec WAF protection** against common web attacks
✅ **Scalable security** that works with unlimited domains
✅ **Professional monitoring** via CrowdSec dashboard

Your Coolify deployment is now protected by enterprise-grade security that automatically adapts to new threats and shares intelligence with the global CrowdSec community.

---

## 📚 Additional Resources

- **CrowdSec Documentation**: [docs.crowdsec.net](https://docs.crowdsec.net)
- **Traefik Plugin**: [github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin](https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin)
- **Coolify Documentation**: [coolify.io/docs](https://coolify.io/docs)
- **Community Support**: [discourse.crowdsec.net](https://discourse.crowdsec.net)
