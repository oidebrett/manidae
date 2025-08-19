# Manidae - Modular Orchestrator Setup

A pre-packaged, modular, containerized deployment of Pangolin with Middleware-Manager, CrowdSec, Traefik, and optional components. The setup container now delegates all file/folder creation and compose.yaml generation to a modular orchestrator.

**Core Components:**
- **Pangolin** - Main application platform
- **Middleware-Manager** - Dynamic Traefik middleware management (included by default)
- **Traefik** - Reverse proxy and load balancer
- **Gerbil** - WireGuard VPN management

**Optional Components:**
- **CrowdSec** - Collaborative security engine
- **MCPAuth** - OAuth authentication
- **Komodo** - Infrastructure management
- **NLWeb** - Natural language web interface

## Refactored Setup Flow

- Run the setup container once with your environment variables
- The setup container validates envs and runs `orchestrator/build-compose.sh`
- The orchestrator generates:
  - compose.yaml
  - container-setup.sh (from components)
  - DEPLOYMENT_INFO.txt
  - config/… files and folders as needed
- Then you start the stack with `docker compose up -d`

### Quick Start

```bash
# From this repository root
DOMAIN=example.com \
EMAIL=admin@example.com \
ADMIN_USERNAME=admin@example.com \
ADMIN_PASSWORD=changeme \
docker compose -f docker-compose-setup.yml up

# Start services
docker compose up -d
```

### Auto-derived COMPONENTS

If you do not set `COMPONENTS`, the setup derives it automatically:
- Always includes `pangolin` and `middleware-manager`
- Adds `crowdsec` if `CROWDSEC_ENROLLMENT_KEY` is set
- Adds `mcpauth` if both `CLIENT_ID` and `CLIENT_SECRET` are set
- Adds `komodo` if `KOMODO_HOST_IP` is set
- Adds `nlweb` if any of `OPENAI_API_KEY`, `AZURE_OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `GEMINI_API_KEY` are set

You can override:
```bash
COMPONENTS="pangolin,middleware-manager,crowdsec,mcpauth,komodo" docker compose -f docker-compose-setup.yml up
```

## Common Scenarios

- Pangolin with Middleware Manager (default):
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme docker compose -f docker-compose-setup.yml up
```

- Pangolin with Middleware Manager + CrowdSec:
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

- Full stack:
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key CLIENT_ID=your-client-id CLIENT_SECRET=your-client-secret \
OPENAI_API_KEY=your-key \
KOMODO_HOST_IP=127.0.0.1 \
docker compose -f docker-compose-setup.yml up
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
# Middleware Manager included automatically
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme docker compose -f docker-compose-setup.yml up
```

Exclude middleware-manager:
```bash
# Only Pangolin, no middleware manager
COMPONENTS="pangolin" DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme docker compose -f docker-compose-setup.yml up
```

Explicitly include with other components:
```bash
# Pangolin + Middleware Manager + CrowdSec
COMPONENTS="pangolin,middleware-manager,crowdsec" DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme CROWDSEC_ENROLLMENT_KEY=your-key docker compose -f docker-compose-setup.yml up
```

**Accessing Middleware Manager:**
Once deployed, the Middleware Manager integrates with Pangolin and is accessible through the Pangolin dashboard. It runs as a backend service and doesn't expose a separate web interface - all management is done through Pangolin's interface.

## Where outputs go

- compose.yaml
- container-setup.sh
- DEPLOYMENT_INFO.txt
- config/
  - config.yml (Pangolin configuration)
  - traefik/ (Traefik configuration and rules)
  - middleware-manager/ (Middleware Manager configuration, if included)
  - letsencrypt/ (SSL certificates)

All at the repository root (mounted as `/host-setup` in the setup container).

## Notes

- The old monolithic `container-setup.sh` and inline heredoc compose generation were removed. The setup compose now only drives the orchestrator.
- Keep ports 80/443/51820 open.
- Ensure your domain DNS points to the host.
