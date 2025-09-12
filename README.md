# Manidae - Flexible Docker Deployment Generator

A flexible, modular docker deployment generator that supports multiple base platforms and optional components. Generate complete docker-compose deployments for Pangolin, Coolify, or other platforms with customizable add-on components like middleware management, security, monitoring, and more.

## Supported Base Platforms

**Pangolin Platform:**
- **Pangolin** - Main application platform with WireGuard VPN (Gerbil)
- **Pangolin+** - Enhanced Pangolin with integrated CrowdSec security
- **Traefik** - Reverse proxy and load balancer
- **Middleware-Manager** - Dynamic Traefik middleware management

**Coolify Platform:**
- **Coolify** - Self-hosted application deployment platform
- **PostgreSQL** - Database for Coolify
- **Redis** - Cache and session storage
- **Soketi** - WebSocket server for real-time features

## Optional Add-on Components

**Security & Monitoring:**
- **CrowdSec** - Collaborative security engine
- **Traefik Log Dashboard** - Enhanced logging and analytics with GeoIP

**Authentication & Management:**
- **MCPAuth** - OAuth authentication
- **Komodo** - Infrastructure management
- **NLWeb** - Natural language web interface
- **Static Page** - Custom landing pages

## How It Works

1. **Choose your base platform** - Pangolin or Coolify
2. **Select optional components** - Add security, monitoring, authentication, etc.
3. **Run the setup container** with your environment variables
4. **The orchestrator generates**:
   - `compose.yaml` - Complete docker-compose configuration
   - `container-setup.sh` - Platform-specific setup scripts
   - `DEPLOYMENT_INFO.txt` - Deployment summary and access information
   - `config/` - Configuration files and folders
5. **Start your stack** with `docker compose up -d`

## Quick Start Examples

### Pangolin Platform

```bash
# Basic Pangolin deployment (minimal requirements)
DOMAIN=example.com \
EMAIL=admin@example.com \
docker compose -f docker-compose-setup.yml up

# Pangolin+ with enhanced security (includes CrowdSec)
COMPONENTS="pangolin+" \
DOMAIN=example.com \
EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com \
ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-enrollment-key \
docker compose -f docker-compose-setup.yml up

# Start services
docker compose up -d
```

### Coolify Platform

```bash
# Basic Coolify deployment
DB_USERNAME=coolify \
DB_PASSWORD=secure-db-password \
REDIS_PASSWORD=secure-redis-password \
PUSHER_APP_ID=coolify-app-id \
PUSHER_APP_KEY=coolify-app-key \
PUSHER_APP_SECRET=coolify-app-secret \
docker compose -f docker-compose-setup.yml up

# Start services
docker compose up -d
```

## Platform Auto-Detection

If you don't specify `COMPONENTS`, the system automatically detects your platform and components:

**Pangolin Platform Detection:**
- Detected when `DOMAIN` and `EMAIL` are provided
- Base: `pangolin,middleware-manager`
- **Pangolin+**: Use `COMPONENTS="pangolin+"` for enhanced security with integrated CrowdSec
- Auto-adds components based on environment variables

**Coolify Platform Detection:**
- Detected when Coolify-specific variables are provided (`DB_USERNAME`, `REDIS_PASSWORD`, etc.)
- Base: `coolify`
- Auto-adds components based on environment variables

**Component Auto-Addition (both platforms):**
- `crowdsec` if `CROWDSEC_ENROLLMENT_KEY` is set (or automatically with `pangolin+`)
- `mcpauth` if both `CLIENT_ID` and `CLIENT_SECRET` are set
- `komodo` if `KOMODO_HOST_IP` is set (Pangolin only)
- `nlweb` if any AI API key is set (`OPENAI_API_KEY`, `AZURE_OPENAI_API_KEY`, etc.)
- `static-page` if `STATIC_PAGE_SUBDOMAIN` is set (Pangolin only)
- `traefik-log-dashboard` if `MAXMIND_LICENSE_KEY` is set

**Note:** `pangolin+` automatically includes CrowdSec with enhanced Traefik integration.

**Manual Override:**
```bash
# Explicit component selection
COMPONENTS="pangolin,middleware-manager,crowdsec" docker compose -f docker-compose-setup.yml up

# Pangolin+ (enhanced with integrated CrowdSec)
COMPONENTS="pangolin+" docker compose -f docker-compose-setup.yml up

# Or for Coolify
COMPONENTS="coolify,crowdsec" docker compose -f docker-compose-setup.yml up
```

## Common Deployment Scenarios

### Pangolin Deployments

**Basic Pangolin (minimal setup):**
```bash
# Only requires DOMAIN and EMAIL
DOMAIN=example.com EMAIL=admin@example.com \
docker compose -f docker-compose-setup.yml up
```

**Pangolin+ (enhanced with integrated CrowdSec security):**
```bash
# Requires admin credentials and CrowdSec enrollment key
COMPONENTS="pangolin+" \
DOMAIN=example.com EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-enrollment-key \
docker compose -f docker-compose-setup.yml up
```

**Full Pangolin+ Stack (all optional components):**
```bash
COMPONENTS="pangolin+" \
DOMAIN=example.com EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key CLIENT_ID=your-client-id CLIENT_SECRET=your-client-secret \
OPENAI_API_KEY=your-key KOMODO_HOST_IP=127.0.0.1 MAXMIND_LICENSE_KEY=your-maxmind-key \
docker compose -f docker-compose-setup.yml up
```

### Coolify Deployments

**Basic Coolify:**
```bash
DB_USERNAME=coolify DB_PASSWORD=secure-password REDIS_PASSWORD=redis-password \
PUSHER_APP_ID=app-id PUSHER_APP_KEY=app-key PUSHER_APP_SECRET=app-secret \
docker compose -f docker-compose-setup.yml up
```

**Coolify+ with Security (+ CrowdSec):**
```bash
DB_USERNAME=coolify DB_PASSWORD=secure-password REDIS_PASSWORD=redis-password \
PUSHER_APP_ID=app-id PUSHER_APP_KEY=app-key PUSHER_APP_SECRET=app-secret \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

## Pangolin vs Pangolin+

### Pangolin (Standard)
**Minimal Requirements:** `DOMAIN` and `EMAIL` only

**What's Included:**
- Pangolin application platform
- Gerbil WireGuard VPN management
- Traefik reverse proxy
- Middleware Manager
- Basic Traefik configuration

**Use Case:** Simple deployments where you want the core functionality without additional security layers.

### Pangolin+ (Enhanced Security)
**Requirements:** `DOMAIN`, `EMAIL`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, and `CROWDSEC_ENROLLMENT_KEY`

**What's Included:**
- Everything from standard Pangolin
- **CrowdSec security engine** with collaborative threat intelligence
- **Enhanced Traefik configuration** with CrowdSec middleware integration
- **Automatic security plugin setup** (CrowdSec bouncer v1.4.5)
- **Integrated threat protection** on all HTTP/HTTPS entry points

**Key Security Features:**
- Real-time IP reputation and threat detection
- Collaborative security with CrowdSec community
- CAPTCHA challenges for suspicious traffic
- Automatic IP banning for malicious actors
- AppSec virtual patching capabilities

**Use Case:** Production deployments requiring enhanced security and threat protection.

**Important Notes:** Pangolin+ requires that the CROWDSEC bouncer api key is added. You can do this using the following script *post* install
```bash
chmod +x ./components/crowdsec/update-bouncer-post-install.sh
./components/crowdsec/update-bouncer-post-install.sh manidae_crowdsec_1
```

## Components

### Middleware Manager

The Middleware Manager is a standalone component that provides dynamic middleware management for Traefik and integrates with Pangolin. It's included by default but can be excluded if not needed.

**What it does:**
- Manages Traefik middleware configurations dynamically
- Integrates with Pangolin's API for configuration management
- Provides a web interface for middleware management
- Supports plugin management for Traefik

**Configuration:**
- Automatically creates `config/middleware-manager/` directory
- Connects to Pangolin API at `http://pangolin:3001/api/v1`
- Uses SQLite database at `./data/middleware.db`
- Runs on port 3456 (internal to Docker network)

**Usage scenarios:**

Include by default (auto-derivation):
```bash
# Middleware Manager included automatically with basic Pangolin
DOMAIN=example.com EMAIL=admin@example.com docker compose -f docker-compose-setup.yml up
```

Exclude middleware-manager:
```bash
# Only Pangolin, no middleware manager
COMPONENTS="pangolin" DOMAIN=example.com EMAIL=admin@example.com docker compose -f docker-compose-setup.yml up
```

Explicitly include with other components:
```bash
# Pangolin + Middleware Manager + CrowdSec (manual component selection)
COMPONENTS="pangolin,middleware-manager,crowdsec" \
DOMAIN=example.com EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

**Accessing Middleware Manager:**
Once deployed, the Middleware Manager integrates with Pangolin and is accessible through the Pangolin dashboard. It runs as a backend service and doesn't expose a separate web interface - all management is done through Pangolin's interface.

### Static Page

The Static Page component creates a custom landing page for your deployment and configures Traefik to serve it. This component doesn't add new Docker services but modifies existing configuration files.

**What it does:**
- Creates a static HTML landing page in the `public_html/` directory
- Modifies Traefik's dynamic configuration to add security headers and static file serving
- Supports conditional content based on available components (removes sections for unavailable services)
- Uses templates from `templates/html/index.html` if available, otherwise creates a basic fallback

**Configuration:**
- Triggered by setting `STATIC_PAGE_SUBDOMAIN` environment variable
- Creates files in `public_html/` directory
- Modifies `config/traefik/rules/dynamic_config.yml` to add middleware and routing
- **Requires middleware-manager component** to function properly

**Usage scenarios:**

Enable static page:
```bash
# Static page with custom subdomain (basic Pangolin)
STATIC_PAGE_SUBDOMAIN=www DOMAIN=example.com EMAIL=admin@example.com \
docker compose -f docker-compose-setup.yml up
```

Combined with other components:
```bash
# Static page + CrowdSec + other components (requires admin credentials for CrowdSec)
STATIC_PAGE_SUBDOMAIN=www \
DOMAIN=example.com EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

**Important Notes:**
- The static-page component requires the middleware-manager component to be included
- The component will automatically remove sections for unavailable services (e.g., removes Komodo section if `KOMODO_HOST_IP` is not set)
- Uses the Statiq plugin for Traefik to serve static files

### Traefik Log Dashboard

The Traefik Log Dashboard component provides enhanced logging, monitoring, and analytics for your Traefik deployment with OpenTelemetry (OTLP) support and GeoIP capabilities.

**What it does:**
- Real-time log analysis and visualization of Traefik access logs
- OpenTelemetry tracing integration with OTLP endpoints (GRPC and HTTP)
- GeoIP location tracking using MaxMind databases
- Performance metrics and request analytics
- Automatic MaxMind database updates

**Configuration:**
- Triggered by setting `MAXMIND_LICENSE_KEY` environment variable
- Creates `config/maxmind/` directory for GeoIP databases
- Adds OTLP tracing configuration to `traefik_config.yml`
- Exposes OTLP endpoints on ports 4317 (GRPC) and 4318 (HTTP)
- Frontend accessible on port 3000, backend on port 3001

**Getting a MaxMind License Key:**
1. Get a free MaxMind account: Sign up at https://www.maxmind.com/en/geolite2/signup
2. Generate a license key in your account dashboard
3. Use the license key in your deployment

**Usage scenarios:**

Enable log dashboard:
```bash
# Basic setup with log dashboard (basic Pangolin)
MAXMIND_LICENSE_KEY=your-license-key \
DOMAIN=example.com EMAIL=admin@example.com \
docker compose -f docker-compose-setup.yml up
```

Combined with other components:
```bash
# Full stack with log dashboard + CrowdSec (requires admin credentials)
MAXMIND_LICENSE_KEY=your-license-key \
CROWDSEC_ENROLLMENT_KEY=your-crowdsec-key \
DOMAIN=example.com EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
docker compose -f docker-compose-setup.yml up
```

**Performance Optimization (Optional):**

For high-traffic environments, consider these optimizations:

*Reduce OTLP Sampling:*
```yaml
# In traefik_config.yml
tracing:
  sampleRate: 0.1  # 10% sampling for production
```

*Use GRPC for Better Performance:*
```yaml
# In traefik_config.yml
tracing:
  otlp:
    grpc:
      endpoint: "log-dashboard-backend:4317"
      insecure: true
```

*Optimize Resource Usage:*
```yaml
# In docker-compose.yml
environment:
  - GOGC=20  # More aggressive garbage collection
  - GOMEMLIMIT=1GiB
```

**Documentation:**
- Full documentation: https://github.com/hhftechnology/traefik-log-dashboard
- Middleware Manager: https://github.com/hhftechnology/middleware-manager

## Where outputs go

- compose.yaml
- container-setup.sh
- DEPLOYMENT_INFO.txt
- config/
  - config.yml (Pangolin configuration)
  - traefik/ (Traefik configuration and rules)
  - middleware-manager/ (Middleware Manager configuration, if included)
  - maxmind/ (GeoIP databases, if traefik-log-dashboard is included)
  - letsencrypt/ (SSL certificates)

All at the repository root (mounted as `/host-setup` in the setup container).

## Notes

- The old monolithic `container-setup.sh` and inline heredoc compose generation were removed. The setup compose now only drives the orchestrator.
- Keep ports 80/443/51820 open.
- Ensure your domain DNS points to the host.
