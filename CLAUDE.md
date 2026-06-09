# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

**Manidae** is the Docker Compose orchestrator that runs **on a provisioned VPS** to set up the application stack. It is not a web server or API — it is a bash-driven build system that outputs a `compose.yaml` and `container-setup.sh` from a set of environment variables.

This repo is the sibling of `manidae-cloud` (the FastAPI/React platform that provisions VPSes). When manidae-cloud provisions a VPS via Terraform, its startup script clones this repo and runs `orchestrator/build-compose.sh` to set up the stack.

## ⚠️ Branch Strategy — read before touching any file

> **HARD RULE: Never develop on `main` or commit directly without going through `dev` first.** All changes follow the same workflow as `manidae-cloud`.

```
dev  →  test on preprod VPS  →  PR dev → main  →  live VPS picks up main
```

- Active development branch: **`dev`**
- Production branch: **`main`** (cloned on every live VPS provision via `MANIDAE_BRANCH=main`)
- `whitelabel` branch was deleted (2026-06-09)

How `MANIDAE_BRANCH` connects this repo to `manidae-cloud`:
- The Terraform startup scripts and BYOVPS bootstrap in `manidae-cloud` clone this repo at the branch set by `MANIDAE_BRANCH` in the backend `.env`
- **Live server** (`manidae-cloud`): `MANIDAE_BRANCH=main` → VPSes clone `manidae/main`
- **Preprod server** (`manidae-cloud`): `MANIDAE_BRANCH=dev` → VPSes clone `manidae/dev`

Always confirm `git branch` shows `dev` before editing anything here.

---

## Repo Structure

```
orchestrator/
  build-compose.sh        # Main entry point — detects platform, assembles components
components/
  agentgateway/           # Pangolin + Komodo + MCP Auth + OpenShell Controller
  nemoclaw/               # NemoClaw AI sandbox (OpenShell + Pangolin)
  openclaw/               # OpenClaw agent stack
  hermes-agent/           # Hermes dashboard agent
  pangolin/               # Pangolin reverse proxy (base platform)
  coolify/                # Coolify deployment platform (base platform)
  komodo/                 # Komodo orchestration agent
  crowdsec/               # CrowdSec security engine
  crowdsec-manager/       # CrowdSec management UI
  mcpauth/                # MCP OAuth authentication
  openshell/              # OpenShell terminal gateway (Pangolin resource)
  middleware-manager/     # Traefik middleware management
  nlweb/                  # NLWeb AI interface
  openai-chatkit/         # OpenAI chat interface
  mcp-gateway/            # MCP gateway component
  static-page/            # Static landing page
  traefik-log-dashboard/  # Traefik log analytics
templates/                # Shared templates (if any)
docker-compose-setup.yml  # Meta compose for running build-compose.sh itself
```

Each component directory contains:
- `component.json` — declared `required_env` and `optional_env` arrays
- `compose.yaml` — the Docker Compose fragment for this component
- `config-setup.sh` — bash script that generates config files from env vars
- `deployment-info.txt` — (optional) post-deploy info printed to the user

---

## How the Orchestrator Works

`orchestrator/build-compose.sh` is the only entry point. It:

1. **Auto-detects the platform** from env vars (see table below) OR uses explicit `COMPONENTS=` env var
2. Runs each selected component's `config-setup.sh`
3. Merges all component `compose.yaml` fragments into a single `compose.yaml`
4. Writes `container-setup.sh` for any post-start init (DB migrations, etc.)

### Platform Detection Logic (order matters — first match wins)

| Platform | Trigger env vars | Components added |
|---|---|---|
| Coolify | `DB_USERNAME` or `REDIS_PASSWORD` or `PUSHER_*` | `coolify` |
| AgentGateway | `OPENAI_API_KEY` + `WORKFLOW_ID` + `ADMIN_USERNAME` + `ADMIN_PASSWORD` | `agentgateway, middleware-manager, crowdsec, crowdsec-manager, mcpauth` |
| NemoClaw | `NEMOCLAW_PROVIDER` + `NEMOCLAW_MODEL` + `NEMOCLAW_INFERENCE_API_KEY` | `nemoclaw` |
| OpenClaw | `OPENCLAW_PROVIDER` + `OPENCLAW_MODEL` + `OPENCLAW_INFERENCE_API_KEY` | `openclaw` |
| Hermes | `HERMES_DOMAIN` + `HERMES_AUTH_PASSWORD_HASH` | `hermes-agent` |
| OpenAI Chatkit | `OPENAI_API_KEY` + `WORKFLOW_ID` (no `ADMIN_USERNAME`) | `openai-chatkit` |
| Pangolin (default) | `DOMAIN` + `EMAIL` | `pangolin, middleware-manager` |

**Optional add-ons** (appended after platform detection):
- `CROWDSEC_ENROLLMENT_KEY` → adds `crowdsec`
- `CLIENT_ID`/`CLIENT_SECRET` or `PROVIDER` → adds `mcpauth`
- `KOMODO_HOST_IP` → adds `komodo`
- `STATIC_PAGE_SUBDOMAIN` → adds `static-page` (except on AgentGateway, which handles it separately)

### Explicit COMPONENTS override

```bash
COMPONENTS="pangolin,crowdsec,mcpauth,komodo" OUTPUT_DIR=./out ./orchestrator/build-compose.sh
```

---

## Adding or Editing a Component

Each component is self-contained. To add a new one:

1. Create `components/{name}/` directory
2. Write `component.json`:
   ```json
   {
     "name": "mycomponent",
     "required_env": [{"name": "REQUIRED_VAR", "hint": "description"}],
     "optional_env": [{"name": "OPTIONAL_VAR", "hint": "description"}],
     "description": "What this component does"
   }
   ```
3. Write `compose.yaml` — a Docker Compose fragment (services, networks, volumes)
4. Write `config-setup.sh` — generates any config files needed; sourced with `ROOT_HOST_DIR` pointing at the VPS host config directory
5. Add detection logic in `orchestrator/build-compose.sh` if this component auto-detects from env vars

**Key invariants in `config-setup.sh`:**
- Always use `ROOT_HOST_DIR="${ROOT_HOST_DIR:-/host-setup}"` for path prefix — the orchestrator sets this
- Use portable `sed -i` (macOS and Linux differ): copy the `_sed_i()` helper from `agentgateway/config-setup.sh`
- Script runs in a Docker container during provisioning — do not assume host tools beyond `sh`, `openssl`, `sed`, `cat`

---

## Testing

There are no built-in tests in this repo. Tests for the orchestrator logic live in **manidae-cloud**:

```bash
# From manidae-cloud repo:
backend/venv/bin/python3 -m pytest backend/tests/test_agentgateway_invariants.py -v -k orchestrator
```

These tests run `build-compose.sh` with `DRY_RUN=1 SKIP_ENVSUBST=1` and verify platform detection output. **If you change the detection logic in `build-compose.sh`, update those tests.**

### Manual test of build-compose.sh:

```bash
# Test AgentGateway detection
OPENAI_API_KEY=sk-test WORKFLOW_ID=wf-test ADMIN_USERNAME=admin ADMIN_PASSWORD=pw \
DOMAIN=test.example.com EMAIL=test@example.com \
DRY_RUN=1 SKIP_ENVSUBST=1 OUTPUT_DIR=/tmp/test-ag \
./orchestrator/build-compose.sh

# Test NemoClaw detection
NEMOCLAW_PROVIDER=openai-api NEMOCLAW_MODEL=gpt-4o NEMOCLAW_INFERENCE_API_KEY=sk-test \
DOMAIN=test.example.com EMAIL=test@example.com \
DRY_RUN=1 SKIP_ENVSUBST=1 OUTPUT_DIR=/tmp/test-nemo \
./orchestrator/build-compose.sh

# Verify no platform detected (should error)
DRY_RUN=1 SKIP_ENVSUBST=1 OUTPUT_DIR=/tmp/test-empty \
./orchestrator/build-compose.sh
```

---

## Relationship to manidae-cloud

The Terraform startup scripts in `manidae-cloud` (`backend/app/core/deployment/terraform_templates/includes/startup_agentgateway.sh.j2`, etc.) clone this repo and invoke `orchestrator/build-compose.sh` with the appropriate env vars. The BYOVPS bootstrap (`byovps_bootstrap.py`) does the equivalent for bring-your-own-VPS installs.

**Critical coupling:** If you change which env vars trigger a platform in `build-compose.sh`, you **must** update the corresponding Terraform startup script in manidae-cloud that sets those env vars, and vice versa. Otherwise a newly provisioned VPS will silently fall through to the wrong platform or hit the error branch.

The env vars set in the Terraform templates are the contract between these two repos.

---

## ⚠️ Key Rules for Coding Agents

- **Do not change platform detection order** without checking that all existing Terraform startup scripts still set the right trigger vars. AgentGateway detection must come before Pangolin (both need `DOMAIN`+`EMAIL`).
- **`config-setup.sh` scripts must be idempotent** — they can be re-run on the same VPS without corrupting config. Use `>` not `>>` for files written from scratch; use guards before appending.
- **Do not use bash-isms in `config-setup.sh`** — these run under `#!/bin/sh` (not bash). No `[[`, no `$()` inside `[`, no `local` in some shells. Test with `sh -n`.
- **Never hardcode a domain or IP** — all config values come from env vars. Use `${DOMAIN}`, `${ADMIN_SUBDOMAIN:-pangolin}` with defaults.
- **Branch:** active development is on `dev`, not `main`. Always confirm `git branch` before making commits. See the Branch Strategy section at the top of this file.
