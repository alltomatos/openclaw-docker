#!/bin/bash

# Configuration
SKILLS_DIR="/home/openclaw/.openclaw/workspace/skills"
LOG_FILE="/home/openclaw/.openclaw/workspace/skill_scan.log"

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
        
        # 1. Handle Node.js Skills (package.json)
        if [ -f "$skill_path/package.json" ]; then
            # Check if node_modules exists
            if [ ! -d "$skill_path/node_modules" ]; then
                log "New Node.js skill detected: $SKILL_NAME. Installing dependencies..."
                
                cd "$skill_path" || continue
                
                if npm install >> "$LOG_FILE" 2>&1; then
                    log "Node dependencies installed for $SKILL_NAME"
                    CHANGES_DETECTED=true
                else
                    log "Failed to install Node dependencies for $SKILL_NAME"
                fi
            fi
        fi

        # 2. Handle Python Skills (requirements.txt)
        if [ -f "$skill_path/requirements.txt" ]; then
            # Use a flag directory inside the persistent PYTHONUSERBASE
            # This ensures that if the volume is wiped, we reinstall dependencies
            # even if the skill folder (bind mount) remains.
            
            # Default to a local hidden dir if PYTHONUSERBASE is not set
            DEPS_BASE="${PYTHONUSERBASE:-$HOME/.local}"
            FLAGS_DIR="$DEPS_BASE/.installed_flags"
            
            # Create flags directory if it doesn't exist
            mkdir -p "$FLAGS_DIR"
            
            # Generate a unique hash for the requirements file to detect changes
            REQ_HASH=$(md5sum "$skill_path/requirements.txt" | awk '{print $1}')
            FLAG_FILE="$FLAGS_DIR/${SKILL_NAME}_${REQ_HASH}.flag"
            
            if [ ! -f "$FLAG_FILE" ]; then
                log "New or updated Python skill detected: $SKILL_NAME. Installing dependencies..."
                
                # We use --break-system-packages if needed, or install to user level
                # Since we are the 'openclaw' user, --user is safer and standard
                # Note: With PYTHONUSERBASE set, --user installs to that location.
                if pip install --user -r "$skill_path/requirements.txt" >> "$LOG_FILE" 2>&1; then
                    log "Python dependencies installed for $SKILL_NAME"
                    
                    # Remove old flags for this skill to avoid clutter
                    rm -f "$FLAGS_DIR/${SKILL_NAME}_*.flag"
                    
                    # Create new flag
                    touch "$FLAG_FILE"
                    CHANGES_DETECTED=true
                else
                    log "Failed to install Python dependencies for $SKILL_NAME"
                fi
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
