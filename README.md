# 🚀 Manidae - Simple Docker Deployment Generator

**One command. Complete deployments.** Generate production-ready Docker stacks for Pangolin, Coolify, and more with automatic security, monitoring, and backup features.

[![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)](https://docker.com)
[![Pangolin](https://img.shields.io/badge/Pangolin-Supported-green)](https://github.com/contextware/pangolin)
[![Coolify](https://img.shields.io/badge/Coolify-Supported-orange)](https://coolify.io)
[![CrowdSec](https://img.shields.io/badge/CrowdSec-Integrated-red)](https://crowdsec.net)

---

## ✨ What is Manidae?

Manidae is a **smart deployment generator** that creates complete Docker Compose stacks with just a few environment variables. No complex configuration files, no manual setup - just specify what you want and get a production-ready deployment.

### 🎯 Perfect for:
- **DevOps Engineers** setting up new environments quickly
- **Self-hosters** wanting secure, monitored applications
- **Teams** needing consistent, reproducible deployments
- **Anyone** who wants Docker deployments without the complexity

---

## 🏗️ Supported Platforms

| Platform | Description | Best For |
|----------|-------------|----------|
| **🦎 Pangolin** | Application platform + WireGuard VPN | Secure app hosting with VPN access |
| **🦎+ Pangolin+** | Pangolin + CrowdSec security | Production apps needing threat protection |
| **🐳 Coolify** | Self-hosted deployment platform | Teams managing multiple applications |

### 🔧 Optional Add-ons
- **🛡️ CrowdSec** - Collaborative security engine
- **📊 Log Dashboard** - Real-time analytics with GeoIP
- **🔐 OAuth** - Google authentication integration
- **🤖 AI Interface** - Natural language management
- **📄 Landing Pages** - Custom static pages
- **💾 Automated Backups** - Git-based configuration backups

---

## 🚀 Quick Start

### 1️⃣ Basic Pangolin (2 minutes)
```bash
# Minimal setup - just domain and email
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
docker compose -f docker-compose-setup.yml up

# Start your stack
docker compose up -d
```
**Access:** `https://pangolin.yourdomain.com`

### 2️⃣ Pangolin+ with Security (3 minutes)
```bash
# Enhanced security with CrowdSec protection
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
ADMIN_USERNAME=admin@yourdomain.com \
ADMIN_PASSWORD=YourSecurePassword123! \
CROWDSEC_ENROLLMENT_KEY=your-crowdsec-key \
docker compose -f docker-compose-setup.yml up

# Start your stack
docker compose up -d
```
**Features:** Automatic threat detection, IP blocking, CAPTCHA challenges

### 3️⃣ Coolify Platform (2 minutes)
```bash
# Self-hosted app deployment platform
DB_PASSWORD=$(openssl rand -hex 32) \
REDIS_PASSWORD=$(openssl rand -hex 32) \
PUSHER_APP_KEY=$(openssl rand -hex 16) \
docker compose -f docker-compose-setup.yml up

# Start your stack
docker compose up -d
```
**Access:** `http://your-server-ip:8000`

---

## 🎛️ Smart Auto-Detection

**No need to specify components!** Manidae automatically detects what you want based on your environment variables:

```bash
# This automatically includes CrowdSec because you provided the enrollment key
DOMAIN=example.com \
EMAIL=admin@example.com \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

**Auto-detected components:**
- 🛡️ CrowdSec (when `CROWDSEC_ENROLLMENT_KEY` is set)
- 📊 Log Dashboard (when `MAXMIND_LICENSE_KEY` is set)
- 🔐 OAuth (when `CLIENT_ID` + `CLIENT_SECRET` are set)
- 🤖 AI Interface (when `OPENAI_API_KEY` is set)
- 💾 Backups (when `MAX_BACKUPS > 0`)

---

## 💾 Automated Backups

Enable automatic Git-based configuration backups:

```bash
# Backup your config to Git every 24 hours, keep 7 days
MAX_BACKUPS=7 \
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
docker compose -f docker-compose-setup.yml up
```

**What gets backed up:**
- All configuration files
- Database schemas and data
- SSL certificates
- Custom settings

**Repository:** `git@github.com:ManidaeCloud/{deployment-name}_syncresources.git`

---

## 🛡️ Security Features

### Pangolin+ Security Stack
- **Real-time threat detection** with CrowdSec
- **Automatic IP blocking** for malicious actors
- **CAPTCHA challenges** for suspicious traffic
- **Collaborative intelligence** from global threat feeds
- **SSL/TLS encryption** with automatic certificate management

### Built-in Security
- **Traefik reverse proxy** with security headers
- **Let's Encrypt SSL** certificates
- **Network isolation** between services
- **Secure defaults** for all components

---

## 📊 What You Get

After running the setup, you'll have:

```
📁 Your Deployment
├── 🐳 compose.yaml              # Complete Docker Compose stack
├── ⚙️ config/                   # All configuration files
│   ├── 🦎 pangolin/            # App configuration
│   ├── 🔀 traefik/             # Reverse proxy rules
│   ├── 🛡️ crowdsec/            # Security configuration
│   └── 🔐 letsencrypt/         # SSL certificates
├── 📋 DEPLOYMENT_INFO.txt       # Access URLs and credentials
└── 🔧 container-setup.sh       # Post-deployment scripts
```

---

## 🎯 Use Cases

### 🏢 **Business Applications**
```bash
# Secure business app with monitoring
COMPONENTS="pangolin+" \
DOMAIN=company.com \
MAXMIND_LICENSE_KEY=your-key \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

### 🏠 **Home Lab**
```bash
# Simple home server setup
DOMAIN=homelab.local \
EMAIL=admin@homelab.local \
docker compose -f docker-compose-setup.yml up
```

### 👥 **Team Development**
```bash
# Coolify for team app deployments
DB_PASSWORD=secure123 \
REDIS_PASSWORD=redis123 \
docker compose -f docker-compose-setup.yml up
```

### **OpenAI chatkit (openai hosted workflows)

```bash
COMPONENTS=openai-chatkit DOMAIN=yourdomain.com EMAIL=admin@yourdomain.com OPENAI_API_KEY=sk-proj-your-key WORKFLOW_ID=wf_your-workflow docker compose -f docker-compose-setup.yml up
```

### **AgentGateway (self hosted workflows)

```bash
COMPONENTS=agentgateway \
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
ADMIN_USERNAME=admin@yourdomain.com \
ADMIN_PASSWORD=your-secure-password \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
docker compose -f docker-compose-setup.yml up
```

---

## 📚 Post-Installation Steps

If you want Pangolin to be prepopulated with the resources/targets for your deployment, you use the contents of the `postgres_export` directory. You can run this automatically but first you will need an initial admin user. 

```bash
docker exec PANGOLIN_CONTAINER_NAME pangctl set-admin-credentials --email "admin@yourdomain.com" --password "YourPassword"

 
chmod +x ./components/pangolin/initialize_sqlite.sh
./components/pangolin/initialize_sqlite.sh
chmod +x ./components/crowdsec/update-bouncer-post-install.sh
./components/crowdsec/update-bouncer-post-install.sh CROWDSEC_CONTAINER_NAME
```

---

## 📚 Need More Details?

- **📋 [Complete Configuration Guide](docs/CONFIGURATION.md)** - All options and advanced features
- **🔄 [Backup Service Guide](docs/BACKUP_SERVICE.md)** - Automated backup configuration
- **🛠️ [Component Documentation](docs/)** - Individual component guides

---

## 🤝 Requirements

- **Docker** and **Docker Compose** installed
- **Domain name** pointing to your server (for Pangolin)
- **Ports 80, 443, 51820** open on your firewall
- **Basic knowledge** of Docker and domain management

---

## 💡 Why Manidae?

✅ **Simple** - One command deployments
✅ **Secure** - Built-in security best practices
✅ **Smart** - Automatic component detection
✅ **Complete** - Everything you need included
✅ **Flexible** - Easy to customize and extend
✅ **Reliable** - Production-tested configurations

**Get started in minutes, not hours.** 🚀
