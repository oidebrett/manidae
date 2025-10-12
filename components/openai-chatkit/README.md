# 🤖 OpenAI Chatkit Standalone Component

The OpenAI Chatkit component provides a standalone conversational AI interface using the `oideibrett/chatkit-embed` Docker image. This component works as a complete standalone platform with its own Traefik reverse proxy, requiring no additional services like Pangolin or databases.

## 📋 Requirements

### Required Environment Variables
- `OPENAI_API_KEY` - Your OpenAI API key (e.g., `sk-proj-...`)
- `WORKFLOW_ID` - Your workflow identifier (e.g., `wf_...`)

### Optional Environment Variables
- `CHATKIT_SUBDOMAIN` - Subdomain for chatkit access (default: `chatkit`)
- `CHATKIT_THEME_JSON` - JSON configuration for theme customization
- `CHATKIT_GREETING` - Custom greeting message
- `CHATKIT_PLACEHOLDER` - Placeholder text for input field
- `CHATKIT_PROMPTS_JSON` - JSON array of predefined prompts
- `EMBED_MODE` - Embedding mode: `standalone`, `iframe`, or `script`
- `SHOW_EMBED_CODE` - Whether to show "Get Embed Code" button (`true`/`false`)

## 🚀 Usage

### Automatic Detection (Recommended)
When both `OPENAI_API_KEY` and `WORKFLOW_ID` are set, the component is automatically detected as a standalone platform:

```bash
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
docker compose -f docker-compose-setup.yml up
```

### Manual Component Selection
```bash
COMPONENTS="openai-chatkit" \
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
docker compose -f docker-compose-setup.yml up
```

### With Custom Configuration
```bash
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
CHATKIT_SUBDOMAIN=chat \
CHATKIT_GREETING="Welcome! How can I help you today?" \
CHATKIT_THEME_JSON='{"color":{"accent":{"primary":"#2563eb"}},"radius":"smooth"}' \
docker compose -f docker-compose-setup.yml up
```

## 🌐 Access

After deployment, the chatkit interface will be available at:
- `https://chatkit.yourdomain.com` (default)
- `https://your-custom-subdomain.yourdomain.com` (if `CHATKIT_SUBDOMAIN` is set)

## 🔧 Configuration Details

### Docker Service
- **Image**: `oideibrett/chatkit-embed:latest`
- **Port**: 8000 (internal and external)
- **Health Check**: HTTP check on `localhost:8000`
- **Restart Policy**: `unless-stopped`

### Traefik Integration
The component automatically configures Traefik routing with:
- HTTP to HTTPS redirect
- SSL certificate management via Let's Encrypt
- Subdomain-based routing

### Environment File
All configuration is loaded from the `.env` file, including both required and optional variables.

## 🧪 Testing

Run the included test script to verify the implementation:

```bash
./test-openai-chatkit.sh
```

This will test:
- Component auto-detection
- Docker Compose integration
- Setup script execution
- Container startup and health

## 📁 Files

- `component.json` - Component metadata and environment variable definitions
- `compose.yaml` - Docker Compose service definition
- `config-setup.sh` - Setup script for Traefik routing configuration
- `README.md` - This documentation file

## 🔗 Dependencies

- **Standalone platform** - No dependencies on Pangolin, Coolify, or other services
- **Self-contained** - Includes its own Traefik reverse proxy
- **Minimal setup** - Only requires Docker and the Manidae orchestrator
