# 🔄 Backup Service Configuration

The Manidae deployment generator can automatically include a backup service in your Docker Compose configuration when the `MAX_BACKUPS` environment variable is set to a value greater than 0.

## 📋 Requirements

- `MAX_BACKUPS` environment variable set to a value > 0
- Directory name ending with `_setup-stack` (e.g., `ivobrett-432212_setup-stack`)
- SSH private key configured in your `.env` file for Git repository access

## 🚀 Usage

### Enable Backup Service

Set the `MAX_BACKUPS` environment variable when running the deployment generator:

```bash
# Enable backup service with 7 days retention
# Run from a directory named like: ivobrett-432212_setup-stack
MAX_BACKUPS=7 docker compose -f docker-compose-setup.yml up
```

### Disable Backup Service

Set `MAX_BACKUPS=0` or omit the variable entirely:

```bash
# No backup service will be added
MAX_BACKUPS=0 docker compose -f docker-compose-setup.yml up
```

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `MAX_BACKUPS` | Number of backups to retain (0 = disabled) | Yes | 0 |

### Auto-Generated Configuration

When enabled, the backup service will be configured with:

- **Repository URL**: `git@github.com:ManidaeCloud/{DEPLOYMENT_NAME}_syncresources.git`
- **Source Path**: `/etc/komodo/stacks/{DEPLOYMENT_NAME}_setup-stack/config`
- **Volume Mount**: `/etc/komodo/stacks/{DEPLOYMENT_NAME}_setup-stack:/etc/komodo/stacks/{DEPLOYMENT_NAME}_setup-stack:ro`
- **Backup Schedule**: Daily (every 24 hours)
- **Email**: `backup@{DOMAIN}`

### Deployment Name Resolution

The deployment name is automatically derived from the current directory name:

1. **Directory ends with `_setup-stack`**: Extract the prefix (e.g., `ivobrett-432212_setup-stack` → `ivobrett-432212`)
2. **Other directory names**: Use the directory name as-is
3. **Paths**: Always use `/etc/komodo/stacks/{DEPLOYMENT_NAME}_setup-stack/` structure

## 📁 Generated Service Configuration

```yaml
backup-job:
  image: oideibrett/manidae-backup:latest
  container_name: manidae-backup-job
  restart: unless-stopped
  env_file:
    - ./.env  # Load SSH_PRIVATE_KEY and other variables
  environment:
    # Repository configuration
    - REPO_URL=git@github.com:ManidaeCloud/my-deployment_syncresources.git
    - BACKUP_SOURCE_PATH=/etc/komodo/stacks/my-deployment_setup-stack/config
    - BACKUP_MODE=backup
    - GIT_USER_NAME=Backup Bot
    - GIT_USER_EMAIL=backup@example.com
    # Backup configuration
    - MAX_BACKUPS=7
  volumes:
    # Mount the actual /etc/komodo directory from your VPS
    - /etc/komodo/stacks/my-deployment_setup-stack:/etc/komodo/stacks/my-deployment_setup-stack:ro
  command: >
    sh -c "while true; do
      echo 'Running backup at $(date)' &&
      /usr/local/bin/backup_script.sh &&
      echo 'Backup completed. Sleeping for 1 day ...' &&
      sleep 86400;
    done"
  healthcheck:
    test: ["CMD", "pgrep", "-f", "backup_script.sh"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 10s
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
```

## 🔧 Prerequisites

1. **SSH Key**: Ensure your `.env` file contains the SSH private key for Git repository access
2. **Repository**: The target Git repository should exist at `git@github.com:ManidaeCloud/{DEPLOYMENT_NAME}_syncresources.git`
3. **Directory Structure**: The backup expects the standard Komodo directory structure at `/etc/komodo/stacks/{DEPLOYMENT_NAME}_setup-stack/`

## 📝 Examples

### Example 1: Production Deployment
```bash
# In directory: /etc/komodo/stacks/ivobrett-432212_setup-stack/
COMPONENTS="pangolin+,crowdsec" \
DOMAIN=contextware.ai \
EMAIL=admin@contextware.ai \
MAX_BACKUPS=7 \
docker compose -f docker-compose-setup.yml up
# Will use "ivobrett-432212" as deployment name
```

### Example 2: Staging Environment
```bash
# In directory: /etc/komodo/stacks/staging-env_setup-stack/
MAX_BACKUPS=14 docker compose -f docker-compose-setup.yml up
# Will use "staging-env" as deployment name
```

### Example 3: Disable Backup
```bash
# No backup service will be added
docker compose -f docker-compose-setup.yml up
```
