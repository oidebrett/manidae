# OpenClaw Standalone — BYOVPS Prerequisites

This document is for **Bring-Your-Own-VPS** deployments only. (Cloud-provider
deployments handle all this via the cloud-init startup script.)

The `compose.yaml` in this directory **only brings up Traefik** (the reverse
proxy that terminates SSL and gates access). The OpenClaw gateway itself
runs as a **host systemd service**, installed and managed by the `openclaw`
CLI tool — not in Docker.

You need root on the VPS. Replace placeholders in angle brackets (`<…>`) with
your real values. Any other variable references in this doc are already
filled in for you at compose-generation time.

---

## 1. Install the OpenClaw CLI

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
export PATH="$PATH:/usr/local/bin:/root/.local/bin"
which openclaw   # should print /usr/local/bin/openclaw or similar
```

## 2. Install the gateway scaffold

```bash
HOME=/root openclaw gateway install --force
```

This creates `/root/.openclaw/openclaw.json` (default config) and a user-level
systemd unit. We'll replace the user unit with a system-level one in step 4.

## 3. Configure provider + auth token

Pick your inference provider and run the corresponding block. All commands
need `HOME=/root` so the CLI writes to `/root/.openclaw/openclaw.json`.

**Common settings (required for all providers):**

```bash
HOME=/root openclaw config set gateway.auth.token "${OPENCLAW_AUTH_TOKEN}"
HOME=/root openclaw config set gateway.auth.mode token
HOME=/root openclaw config set gateway.bind custom
HOME=/root openclaw config set gateway.customBindHost '0.0.0.0'
HOME=/root openclaw config set gateway.controlUi.allowedOrigins \
  '["https://${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN}"]' --strict-json
HOME=/root openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth \
  true --strict-json
HOME=/root openclaw config set gateway.mode local
```

**NVIDIA Endpoints:**

```bash
HOME=/root openclaw config set agents.defaults.model 'nvidia/<MODEL_ID>'
HOME=/root openclaw config set models.providers.nvidia \
  '{"baseUrl":"https://integrate.api.nvidia.com/v1","api":"openai-completions","apiKey":"<YOUR_NVAPI_KEY>","models":[{"id":"<MODEL_ID>","name":"NVIDIA Model","input":["text"],"contextWindow":262144}]}' --strict-json
HOME=/root openclaw config set env.vars.NVIDIA_API_KEY '<YOUR_NVAPI_KEY>'
```

**OpenAI:**

```bash
HOME=/root openclaw config set agents.defaults.model 'openai/<MODEL_ID>'   # e.g. openai/gpt-4.1
HOME=/root openclaw config set env.vars.OPENAI_API_KEY '<YOUR_OPENAI_KEY>'
```

**Anthropic / Gemini / OpenAI-compatible:** same pattern — swap the
`agents.defaults.model` provider prefix and the corresponding `env.vars.*_API_KEY`.

## 4. Create a system-level systemd service

User-level systemd doesn't survive boot in a cloud-init context. Replace it
with a system unit:

```bash
# Locate the ExecStart line the user-systemd unit was using
EXEC_START=$(grep '^ExecStart=' /root/.config/systemd/user/openclaw-gateway.service 2>/dev/null \
              | head -1 | sed 's/^ExecStart=//')
[ -z "$EXEC_START" ] && \
  EXEC_START="/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789"

sudo tee /etc/systemd/system/openclaw-gateway.service > /dev/null <<SERVICE_EOF
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=root
ExecStart=${EXEC_START}
Restart=always
RestartSec=10
TimeoutStopSec=30
TimeoutStartSec=60
Environment=HOME=/root
Environment=TMPDIR=/tmp
Environment=NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
Environment=PATH=/usr/bin:/root/.nvm/current/bin:/root/.local/bin:/root/.npm-global/bin:/root/bin:/usr/local/bin:/bin
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_NO_RESPAWN=1
Environment=OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
# Add provider API key environment here too if needed, e.g.:
# Environment=NVIDIA_API_KEY=<YOUR_NVAPI_KEY>

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Disable the user-level service so it doesn't fight the system one
XDG_RUNTIME_DIR=/run/user/0 systemctl --user disable openclaw-gateway 2>/dev/null || true
sudo loginctl disable-linger root 2>/dev/null || true

sudo systemctl daemon-reload
sudo systemctl enable openclaw-gateway
sudo systemctl start openclaw-gateway
```

## 5. Verify

```bash
sudo systemctl is-active openclaw-gateway        # → active
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:18789/   # → not 000 / not "connection refused"
```

If `systemctl status openclaw-gateway` shows errors, check `journalctl -u openclaw-gateway -n 50`.

## 6. Now start Traefik

```bash
docker compose up -d
```

The public URL `https://${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN}` will reverse-proxy
to the gateway on `127.0.0.1:18789`. Open it with the tokenized link:

```
https://${OPENCLAW_SUBDOMAIN}.${OPENCLAW_DOMAIN}/#token=${OPENCLAW_AUTH_TOKEN}
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `systemctl status openclaw-gateway` shows "exit 78" | `gateway.mode` not set | Re-run `openclaw config set gateway.mode local` |
| Public URL → 502 Bad Gateway | Gateway not listening | `systemctl is-active openclaw-gateway` + `curl 127.0.0.1:18789` |
| Public URL loads but "Browser origin not allowed" | `gateway.controlUi.allowedOrigins` missing your public origin | Re-run the `openclaw config set gateway.controlUi.allowedOrigins` command in step 3 |
| "Token mismatch" on login | Token in URL `#token=…` doesn't match `gateway.auth.token` in openclaw.json | Re-set the token in step 3 to match the auto-generated `${OPENCLAW_AUTH_TOKEN}` |

OpenClaw upstream docs: https://openclaw.ai/docs
