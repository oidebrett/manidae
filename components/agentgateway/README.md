# 🤖 AgentGateway Platform

The AgentGateway platform is a comprehensive solution based on Pangolin that integrates AI-powered chat capabilities through chatkit-embed, along with security, monitoring, and management tools. It's designed as an all-in-one platform for organizations that need secure infrastructure management with integrated AI assistance.

## 🏗️ Architecture

AgentGateway is built on the proven Pangolin platform and includes:

- **🦎 Pangolin Core** - Application platform with WireGuard VPN management
- **🤖 Chatkit-Embed** - AI-powered conversational interface
- **🛡️ CrowdSec Security** - Collaborative threat protection
- **📊 Logs Dashboard** - Real-time monitoring and analytics
- **🔐 MCPAuth** - OAuth authentication management
- **⚙️ Middleware Manager** - Dynamic Traefik configuration
- **🌐 Traefik** - Reverse proxy with SSL termination

## 📋 Requirements

### Required Environment Variables
- `DOMAIN` - Your domain name (e.g., `example.com`)
- `EMAIL` - Email for Let's Encrypt certificates
- `ADMIN_USERNAME` - Admin user email
- `ADMIN_PASSWORD` - Admin user password
- `OPENAI_API_KEY` - Your OpenAI API key (e.g., `sk-proj-...`)
- `WORKFLOW_ID` - Your workflow identifier (e.g., `wf_...`)

### Optional Configuration
- `ADMIN_SUBDOMAIN` - Admin panel subdomain (default: `pangolin`)
- `CHATKIT_SUBDOMAIN` - Chatkit subdomain (default: `chat`)
- `POSTGRES_USER` - Database user (default: `postgres`)
- `POSTGRES_PASSWORD` - Database password (default: `postgres`)
- `POSTGRES_HOST` - Database host (default: `pangolin-postgres`)
- `CROWDSEC_ENROLLMENT_KEY` - CrowdSec enrollment key
- `CLIENT_ID` - OAuth client ID
- `CLIENT_SECRET` - OAuth client secret

### Chatkit Configuration
- `VITE_CHATKIT_API_DOMAIN_KEY` - Domain key for chatkit API
- `GITHUB_REPO_URL` - GitHub repository URL (e.g., `git+ssh://git@github.com/user/repo.git`)
- `SSH_KEY_PATH` - SSH key path for Git access
- `CHATKIT_THEME_JSON` - UI theme configuration
- `CHATKIT_GREETING` - Welcome message
- `CHATKIT_PLACEHOLDER` - Input placeholder text
- `CHATKIT_PROMPTS_JSON` - Predefined prompts
- `EMBED_MODE` - Embed mode (default: `standalone`)
- `SHOW_EMBED_CODE` - Show embed code option
- `VITE_CHATKIT_API_URL` - API URL (default: `/api/chatkit`)
- `BACKEND_HOST` - Backend host (default: `0.0.0.0`)

## 🚀 Usage

### Automatic Detection
AgentGateway is automatically detected when all required variables are set:

```bash
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
ADMIN_USERNAME=admin@yourdomain.com \
ADMIN_PASSWORD=changeme \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
docker compose -f docker-compose-setup.yml up
```

### Manual Component Selection
```bash
COMPONENTS="agentgateway" \
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
ADMIN_USERNAME=admin@yourdomain.com \
ADMIN_PASSWORD=changeme \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
docker compose -f docker-compose-setup.yml up
```

### With Enhanced Security
```bash
COMPONENTS="agentgateway" \
DOMAIN=yourdomain.com \
EMAIL=admin@yourdomain.com \
ADMIN_USERNAME=admin@yourdomain.com \
ADMIN_PASSWORD=changeme \
OPENAI_API_KEY=sk-proj-your-key \
WORKFLOW_ID=wf_your-workflow \
CROWDSEC_ENROLLMENT_KEY=your-enrollment-key \
CLIENT_ID=your-oauth-client-id \
CLIENT_SECRET=your-oauth-client-secret \
docker compose -f docker-compose-setup.yml up
```

## 🌐 Access Points

After deployment, the following services will be available:

- **Admin Dashboard**: `https://pangolin.yourdomain.com` (or your custom subdomain)
- **AI Chat Interface**: `https://chat.yourdomain.com` (or your custom subdomain)
- **Chat Admin**: `https://chat.yourdomain.com/admin`
- **Traefik Dashboard**: `https://traefik.yourdomain.com/dashboard/`
- **Middleware Manager**: `https://middleware-manager.yourdomain.com`
- **Logs Dashboard**: `https://logs.yourdomain.com`

## 🔧 Post-Deployment Setup

1. **Initialize Database**:
   ```bash
   docker exec agentgateway-pangolin-1 pangctl set-admin-credentials --email "admin@yourdomain.com" --password "Password123"
   chmod +x initialize_sqlite.sh
   ./initialize_sqlite.sh
   ```

2. **Configure DNS**: Ensure all subdomains point to your server's IP address

3. **Access Chat Interface**: Visit `https://chat.yourdomain.com` to start using the AI assistant

## 🛡️ Security Features

- **CrowdSec Integration** - Real-time threat detection and blocking
- **SSL/TLS Encryption** - Automatic Let's Encrypt certificates
- **OAuth Authentication** - Secure user authentication
- **VPN Access** - WireGuard VPN for secure remote access
- **Access Control** - Role-based resource access management

## 🔗 Dependencies

AgentGateway automatically includes:
- **pangolin** - Core platform
- **middleware-manager** - Traefik management
- **logs** - Log dashboard
- **crowdsec** - Security engine
- **mcpauth** - Authentication service

## 📊 Monitoring

The platform includes comprehensive monitoring through:
- Traefik access logs
- Application health checks
- Real-time log dashboard
- CrowdSec security metrics

## 🤝 Integration

AgentGateway integrates seamlessly with:
- OpenAI API for AI capabilities
- GitHub repositories for code management
- CrowdSec community for threat intelligence
- OAuth providers for authentication
