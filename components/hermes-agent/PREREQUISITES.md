# Hermes Agent Standalone — BYOVPS Prerequisites

This document is for **Bring-Your-Own-VPS** deployments only. (Cloud-provider
deployments handle all this via the cloud-init startup script.)

The `compose.yaml` in this directory **only brings up Traefik** (the reverse
proxy with HTTP basic-auth). The Hermes dashboard itself runs as a **host
systemd service** — not in Docker.

You need root on the VPS. Replace placeholders in angle brackets (`<…>`) with
your real values. Any other variable references in this doc are already
filled in for you at compose-generation time.

---

## 1. System dependencies

```bash
sudo apt update
sudo apt install -y git curl ca-certificates apache2-utils ufw
```

(`apache2-utils` provides `htpasswd` for the basic-auth hash in step 5;
`ufw` is for the firewall step.)

## 2. Install Hermes

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
echo 'export PATH="$PATH:/usr/local/bin:/root/.local/bin"' >> ~/.bashrc
export PATH="$PATH:/usr/local/bin:/root/.local/bin"
which hermes   # /usr/local/bin/hermes
```

The installer creates the venv at `/usr/local/lib/hermes-agent/venv/` for root
installs, or `/root/.hermes/hermes-agent/.venv/` for per-user.

## 3. Install dashboard extras

The `[web,pty]` extras pull in FastAPI/Uvicorn (for the dashboard) and pty
support (for the embedded chat tab). `ptyprocess` is needed separately for
the PTY bridge.

```bash
# Find the venv (one of these paths will exist)
HERMES_VENV=""
for cand in /usr/local/lib/hermes-agent/venv /root/.hermes/hermes-agent/.venv; do
  [ -x "$cand/bin/python" ] && HERMES_VENV="$cand" && break
done
[ -z "$HERMES_VENV" ] && { echo "Couldn't locate Hermes venv"; exit 1; }

# Bootstrap pip (the uv-managed venv ships without it) then install extras
"$HERMES_VENV/bin/python" -m ensurepip
"$HERMES_VENV/bin/python" -m pip install 'hermes-agent[web,pty]' ptyprocess
```

## 4. Configure LLM provider

Pick one. Replace `<YOUR_KEY>` with your real API key.

**NVIDIA Endpoints** (OpenAI-compatible, authed via `OPENAI_API_KEY`):

```bash
sudo mkdir -p /root/.hermes
sudo tee /root/.hermes/.env > /dev/null <<ENV_EOF
OPENAI_API_KEY=<YOUR_NVAPI_KEY>
NVIDIA_API_KEY=<YOUR_NVAPI_KEY>
ENV_EOF
sudo chmod 600 /root/.hermes/.env
sudo HOME=/root hermes config set model.provider custom
sudo HOME=/root hermes config set model.base_url https://integrate.api.nvidia.com/v1
sudo HOME=/root hermes config set model.default 'nvidia/<MODEL_ID>'
```

**OpenAI:**

```bash
sudo mkdir -p /root/.hermes
echo "OPENAI_API_KEY=<YOUR_OPENAI_KEY>" | sudo tee /root/.hermes/.env
sudo chmod 600 /root/.hermes/.env
sudo HOME=/root hermes config set model.provider openai
sudo HOME=/root hermes config set model.default 'gpt-4.1'
```

**Anthropic / Gemini:** same pattern — `ANTHROPIC_API_KEY` / `GEMINI_API_KEY`
in `.env`, `model.provider anthropic|gemini`, model default e.g. `claude-opus-4-6`
or `gemini-2.5-pro`.

## 5. Generate basic-auth hash for Traefik

The compose generator placed an APR1 hash into `config/traefik/rules/hermes-agent.yml`
using the password you set in Manidae Cloud. If you want to **change** the password
later, regenerate the hash and edit that file:

```bash
htpasswd -nb admin '<YOUR_NEW_PASSWORD>'
# Output is like:  admin:$apr1$XXXXXX$YYYYYYYYYYYYYYYYYYYYY
# Paste the part after "admin:" into:
#   config/traefik/rules/hermes-agent.yml
# under  middlewares.hermes-auth.basicAuth.users  → keep the "admin:" prefix.
```

Traefik auto-reloads on file changes (no restart needed).

## 6. Create dashboard systemd unit

The dashboard binds to `0.0.0.0:9119` inside the host. **The firewall in step 7
keeps it private** — Traefik on the same host reverse-proxies it via localhost.

```bash
HERMES_BIN=$(which hermes)
sudo tee /etc/systemd/system/hermes-dashboard.service > /dev/null <<SERVICE_EOF
[Unit]
Description=Hermes Agent Web Dashboard
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment=HOME=/root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/root/.local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=-/root/.hermes/.env
# --host 0.0.0.0 + --insecure required: Traefik proxies WebSocket connections,
# and uvicorn rewrites ws.client.host via X-Forwarded-For to the original
# public IP. _ws_client_is_allowed would otherwise reject. UFW (next step)
# keeps the port private at the network layer.
ExecStart=${HERMES_BIN} dashboard --host 0.0.0.0 --port 9119 --no-open --insecure
Restart=always
RestartSec=10
TimeoutStopSec=30
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SERVICE_EOF

sudo systemctl daemon-reload
sudo systemctl enable hermes-dashboard
sudo systemctl start hermes-dashboard
```

## 7. Firewall — CRITICAL

Port 9119 must NOT be reachable from outside the host. Only Traefik
(also on the host, port 80/443) should ever reach it.

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 9119/tcp
sudo ufw --force enable
sudo ufw status                 # confirm 9119 is "DENY"
```

## 8. Verify

```bash
sudo systemctl is-active hermes-dashboard            # → active
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9119/   # → 200
```

## 9. Now start Traefik

```bash
docker compose up -d
```

Public URL: `https://${HERMES_SUBDOMAIN}.${HERMES_DOMAIN}` — login with
`admin` + the password you set.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Public URL → 502 Bad Gateway | Dashboard not listening | `systemctl status hermes-dashboard` + `journalctl -u hermes-dashboard -n 50` |
| Login works, chat tab → "events feed disconnected" | WebSocket blocked | Confirm `config/traefik/rules/hermes-agent.yml` has the `hermes-agent-api` router (priority 100, no auth) AND `hermes-agent` router (priority 10, basic-auth). The generated file should already do this — if you edited it, restore the two-router split. |
| Chat tab → "Chat unavailable: out of pty devices" | Missing `ptyprocess` | Re-run step 3 |
| Chat tab → "Chat unavailable: The `ptyprocess` package is missing" | Wrong venv pip | Step 3 — confirm `$HERMES_VENV/bin/python -c 'import ptyprocess'` succeeds |
| "API call failed after 3 retries: Connection error" | Wrong provider config | Re-run step 4 — check `cat /root/.hermes/config.yaml` and `cat /root/.hermes/.env` |
| Chrome refuses `/api/...` requests with "URL includes credentials" | You typed `https://admin:pw@host/…` in the address bar | Visit the plain URL and enter creds in the browser dialog instead |

Hermes upstream docs: https://hermes-agent.nousresearch.com/docs
