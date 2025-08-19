# Manidae - Modular Orchestrator Setup

A pre-packaged, modular, containerized deployment of Pangolin, Middleware-Manager, CrowdSec, Traefik, and optional components. The setup container now delegates all file/folder creation and compose.yaml generation to a modular orchestrator.

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
- Always includes `pangolin`
- Adds `crowdsec` if `CROWDSEC_ENROLLMENT_KEY` is set
- Adds `mcpauth` if both `CLIENT_ID` and `CLIENT_SECRET` are set
- Adds `komodo` if `KOMODO_HOST_IP` is set

You can override:
```bash
COMPONENTS="pangolin,crowdsec,mcpauth,komodo" docker compose -f docker-compose-setup.yml up
```

## Common Scenarios

- Pangolin only:
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme docker compose -f docker-compose-setup.yml up
```

- Pangolin + CrowdSec:
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key \
docker compose -f docker-compose-setup.yml up
```

- Full stack:
```bash
DOMAIN=example.com EMAIL=admin@example.com ADMIN_USERNAME=admin@example.com ADMIN_PASSWORD=changeme \
CROWDSEC_ENROLLMENT_KEY=your-key CLIENT_ID=your-client-id CLIENT_SECRET=your-client-secret \
KOMODO_HOST_IP=127.0.0.1 \
docker compose -f docker-compose-setup.yml up
```

## Where outputs go

- compose.yaml
- container-setup.sh
- DEPLOYMENT_INFO.txt
- config/

All at the repository root (mounted as `/host-setup` in the setup container).

## Notes

- The old monolithic `container-setup.sh` and inline heredoc compose generation were removed. The setup compose now only drives the orchestrator.
- Keep ports 80/443/51820 open.
- Ensure your domain DNS points to the host.
