# Manidae - Pangolin + Middleware-Manager + CrowdSec + Traefik Stack

A pre-packaged, pre-integrated, containerized deployment of Pangolin, Middleware-Manager with CrowdSec security and Traefik reverse proxy. Everything runs in Docker containers and automatically creates the required host folder structure.

## Features

- 🚀 **One-command deployment** - Deploy everything with a single Docker Compose command
- 🐳 **Fully containerized** - Setup process runs in containers, no local scripts needed
- 🔒 **Automatic HTTPS** - Let's Encrypt certificates managed by Traefik
- 🛡️ **Security** - CrowdSec integration for threat protection
- 📁 **Auto-configuration** - Container creates all required files and folder structure on host
- 🔐 **Secure secrets** - Auto-generates secure random keys
- 📥 **GitHub integration** - Downloads setup scripts directly from GitHub

## Quick Start

### Prerequisites

- Linux server with Docker and Docker Compose installed
- Domain name pointing to your server's IP address
- Ports 80, 443, and 51820 available

### One-Command Deployment

```bash
# Download the docker-compose-setup.yml file
curl -sSL https://raw.githubusercontent.com/oidebrett/manidae/main/docker-compose-setup.yml -o docker-compose-setup.yml

# Run the setup first (only needed once)
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin docker compose -f docker-compose-setup.yml up

# Or run this setup (only if you need CROWDSEC)

DOMAIN=example.com \
EMAIL=admin@example.com \
ADMIN_SUBDOMAIN=pangolin \
CROWDSEC_ENROLLMENT_KEY=your-key-here \
docker compose -f docker-compose-setup.yml up

# Or run this setup (only if you need CROWDSEC and want a landing page)
DOMAIN="example.com" EMAIL="admin@example.com" ADMIN_SUBDOMAIN="pangolin" STATIC_PAGE_DOMAIN="www" CROWDSEC_ENROLLMENT_KEY="your-key-here"  docker compose -f docker-compose-setup.yml up

# After setup completes, start the services
docker compose up -d
```

### What happens during deployment:

1. **Setup Container** - Alpine container starts and validates environment variables
2. **Folder Creation** - Container creates config folder structure on host
3. **Configuration** - Container generates all config files with your settings
4. **Docker Compose Generation** - Container creates a docker-compose.yml file for the services
5. **Stack Deployment** - Main services (Pangolin, Gerbil, Traefik) start automatically

## Alternative: Manual Download

If you prefer to review files before running:

```bash
# Clone or download the repository
git clone https://github.com/oidebrett/manidae.git
cd manidae

# Run the setup first (only needed once)
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin docker compose -f docker-compose-setup.yml up

# After setup completes, start the services
docker compose up -d
```

## Environment Variables

The deployment requires three environment variables:

- **DOMAIN** - Your domain name (e.g., `example.com`)
- **EMAIL** - Email address for Let's Encrypt certificates
- **ADMIN_SUBDOMAIN** - Subdomain for the admin portal (default: `pangolin`)
- **ADMIN_SUBDOMAIN** - Subdomain for the admin portal (default: `pangolin`)
- **CROWDSEC_ENROLLMENT_KEY** - CrowdSec enrollment key (optional)
- **POSTGRES_USER** - Postgres username (default: `postgres`)
- **POSTGRES_PASSWORD** - Postgres password (default: `postgres`)

You may see an error: Invalid configuration file: Validation error: Your password must meet the following conditions:
at least one uppercase English letter,
at least one lowercase English letter,
at least one digit,
at least one special character. at "users.server_admin.password"


## Stack Components

- **Setup Container** (alpine:latest) - Creates folder structure and config files (runs once)
- **Pangolin** (fosrl/pangolin:1.5.0) - Main application
- **Gerbil** (fosrl/gerbil:1.0.0) - WireGuard VPN management
- **Traefik** (traefik:v3.4.1) - Reverse proxy with automatic HTTPS

## Setup Orchestrator

The setup orchestrator is a crucial component responsible for initializing the database schema and data. It is designed to be flexible and resilient.

### How it Works

The orchestrator will automatically attempt to connect to the database using the following hosts, in order:

1.  `komodo-postgres-1`
2.  `pangolin-postgres`

It uses the first successful connection to proceed with the initialization. This allows the setup to work in different environments without manual configuration.

### Database Credentials

For the orchestrator to connect to the database, it needs access to the database credentials. These credentials must be provided in a `.env` file located at `./config/.env`. The file should contain the following variables:

```
POSTGRES_USER=your_postgres_user
POSTGRES_PASSWORD=your_postgres_password
```

**Important:** The setup process will fail if this file is not present and correctly configured.

## Directory Structure

After deployment, you'll have:

```
./
├── docker-compose.yml           # Generated by setup container
├── docker-compose-setup.yml     # Used only for initial setup
├── DEPLOYMENT_INFO.txt          # Deployment summary and info
└── config/
    ├── config.yml
    ├── crowdsec/                # Optional CrowdSec config
    ├── letsencrypt/             # Let's Encrypt certificates
    └── traefik/
        ├── traefik_config.yml
        └── rules/
            └── dynamic_config.yml
```

## Management Commands

```bash
# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d

# Update images
docker compose pull
docker compose up -d
```

## Configuration

All configuration is automatically generated during setup. Key files:

- `config/config.yml` - Main Pangolin configuration
- `config/traefik/traefik_config.yml` - Traefik main config
- `config/traefik/rules/dynamic_config.yml` - Traefik routing rules

## Accessing Your Installation

After successful deployment:

- **Dashboard**: `https://yourdomain.com`
- **Admin Login**: `admin@yourdomain.com`
- **Password**: The password you set during installation

## Troubleshooting

### Common Issues

1. **Domain not resolving**
   - Ensure your domain's DNS A record points to your server's IP
   - Wait for DNS propagation (can take up to 24 hours)

2. **Certificate issues**
   - Let's Encrypt certificates can take a few minutes to issue
   - Check logs: `docker compose logs traefik`

3. **Permission errors**
   - Ensure your user is in the docker group: `sudo usermod -aG docker $USER`
   - Log out and back in after adding to docker group

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f pangolin
docker compose logs -f traefik
docker compose logs -f gerbil
```

## Standard Combinations

### 1. Pangolin and Middleware Manager Install (postgres)
```
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin POSTGRES_HOST=komodo-postgres-1 docker compose -f docker-compose-setup.yml up
```
**you can set the POSTGRES_USER and POSTGRES_PASSWORD if you want to use something other than the defaults (postgres/postgres)**

### 2. Pangolin, Middleware Manager Install and Crowdsec
```
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin POSTGRES_HOST=komodo-postgres-1 CROWDSEC_ENROLLMENT_KEY=your-key-here docker compose -f docker-compose-setup.yml up
```

### 3. Pangolin, Middleware Manager Install, Crowdsec, and a Static Page
```
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin POSTGRES_HOST=komodo-postgres-1 CROWDSEC_ENROLLMENT_KEY=your-key-here STATIC_PAGE_DOMAIN=www docker compose -f docker-compose-setup.yml up
```

### 4. Pangolin, Middleware Manager Install, Crowdsec, a Static Page and Komodo
```
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin POSTGRES_HOST=komodo-postgres-1 CROWDSEC_ENROLLMENT_KEY=your-key-here STATIC_PAGE_DOMAIN=www KOMODO_HOST_IP=127.0.0.1 docker compose -f docker-compose-setup.yml up
```

### 5. Pangolin, Middleware Manager Install, Crowdsec, a Static Page, Komodo and MCPAuth
```
DOMAIN=example.com EMAIL=admin@example.com ADMIN_SUBDOMAIN=pangolin POSTGRES_HOST=komodo-postgres-1 CROWDSEC_ENROLLMENT_KEY=your-key-here STATIC_PAGE_DOMAIN=www KOMODO_HOST_IP=127.0.0.1 CLIENT_ID=your-client-id CLIENT_SECRET=your-client-secret docker compose -f docker-compose-setup.yml up
```

Note: the periphery agent for komodo needs to be installed on the Komodo host ip

## Security Notes

- The setup generates secure random secrets automatically
- Admin password is set during installation
- All traffic is automatically redirected to HTTPS
- CrowdSec provides additional security monitoring

## Support

For issues and questions:
- Check the logs first: `docker compose logs -f`
- Ensure your domain DNS is properly configured
- Verify all ports (80, 443, 51820) are accessible

## License

This deployment stack is provided as-is. Please refer to individual component licenses:
- Pangolin: Check fosrl/pangolin repository
- Gerbil: Check fosrl/gerbil repository  
- Traefik: Apache 2.0 License
