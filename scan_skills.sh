#!/bin/bash

# Configuration
SKILLS_DIR="/home/openclaw/workspace/skills"
LOG_FILE="/home/openclaw/workspace/skill_scan.log"

# Ensure log file exists and is writable
touch "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting daily skill scan..."

# Check if skills directory exists
if [ ! -d "$SKILLS_DIR" ]; then
    log "Skills directory not found at $SKILLS_DIR"
    exit 0
fi

CHANGES_DETECTED=false

# Loop through each subdirectory in skills
for skill_path in "$SKILLS_DIR"/*; do
    if [ -d "$skill_path" ]; then
        SKILL_NAME=$(basename "$skill_path")
        
        # Check for package.json
        if [ -f "$skill_path/package.json" ]; then
            # Check if node_modules exists
            if [ ! -d "$skill_path/node_modules" ]; then
                log "New skill detected: $SKILL_NAME. Installing dependencies..."
                
                cd "$skill_path" || continue
                
                if npm install >> "$LOG_FILE" 2>&1; then
                    log "Dependencies installed for $SKILL_NAME"
                    CHANGES_DETECTED=true
                else
                    log "Failed to install dependencies for $SKILL_NAME"
                fi
            else
                # Optional: Check if package.json is newer than node_modules
                # For now, we assume if node_modules exists, it's fine.
                # Use a flag file or similar logic for updates if needed.
                :
            fi
        fi
    fi
done

if [ "$CHANGES_DETECTED" = true ]; then
    log "Changes detected. Restarting OpenClaw..."
    # Restart the process managed by PM2
    pm2 restart openclaw >> "$LOG_FILE" 2>&1
    log "OpenClaw restarted."
else
    log "No new skills requiring installation found."
fi
