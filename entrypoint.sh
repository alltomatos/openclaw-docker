#!/bin/bash
set -e

# Define config paths
CONFIG_DIR="/home/openclaw/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
WORKSPACE_DIR="$CONFIG_DIR/workspace"

# Create config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating config directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
fi

# Ensure Python dependencies directory exists (for persistence)
if [ -n "$PYTHONUSERBASE" ]; then
    if [ ! -d "$PYTHONUSERBASE" ]; then
        echo "Creating Python dependencies directory: $PYTHONUSERBASE"
        mkdir -p "$PYTHONUSERBASE"
    fi
    chown -R openclaw:openclaw "$PYTHONUSERBASE"
fi

# Ensure workspace directory exists
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
    echo "Initializing with secure defaults (Sandboxing: All)..."
    
    if [ -f "/etc/openclaw.defaults.json" ]; then
        cp "/etc/openclaw.defaults.json" "$CONFIG_FILE"
        chown openclaw:openclaw "$CONFIG_FILE"
        echo "✅ Created $CONFIG_FILE with default secure policy."
    else
        echo "❌ Default configuration template not found!"
    fi
    
    echo ""
    echo "To complete configuration (add LLM keys, channels, etc.), run:"
    echo "  docker compose run --rm openclaw-cli configure"
    echo "  (Use 'configure' to edit existing settings without overwriting defaults)"
    echo ""
    echo "The Gateway will start now with limited functionality."
    echo "----------------------------------------------------------------"
fi

# Execute the command as user 'openclaw'
# We use gosu to step down from root to the openclaw user
exec gosu openclaw "$@"
