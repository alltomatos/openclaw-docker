#!/bin/bash
set -e

# Define config paths
CONFIG_DIR="/home/openclaw/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="/home/openclaw/workspace"

# Ensure directories exist
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
fi

if [ ! -d "$WORKSPACE_DIR" ]; then
    mkdir -p "$WORKSPACE_DIR"
fi

# Fix permissions (since we start as root)
# We change ownership of home directory to ensure the user can write
# This is important because volumes mounted from host might have different permissions
chown -R openclaw:openclaw /home/openclaw
chmod 700 "$CONFIG_DIR"

# Start cron daemon
service cron start

# Setup daily scan job if not exists
# We add it to the openclaw user's crontab
if ! crontab -u openclaw -l 2>/dev/null | grep -q "scan_skills.sh"; then
    echo "Setting up daily skill scan cron job..."
    # 0 3 * * * = Run at 3 AM daily
    (crontab -u openclaw -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/scan_skills.sh") | crontab -u openclaw -
    echo "✅ Daily skill scan scheduled for 03:00 AM"
fi

# Check if OpenClaw is configured
if [ ! -f "$CONFIG_FILE" ]; then
    echo "----------------------------------------------------------------"
    echo "⚠️  OpenClaw Configuration Missing ⚠️"
    echo ""
    echo "To configure OpenClaw (add LLM keys, channels, etc.), run:"
    echo "  docker compose exec openclaw openclaw onboard"
    echo ""
    echo "The Gateway will start now, but might require configuration."
    echo "----------------------------------------------------------------"
fi

# Execute the command as user 'openclaw'
# We use gosu to step down from root to the openclaw user
exec gosu openclaw "$@"
