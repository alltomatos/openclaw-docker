#!/bin/bash
set -e

# check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Error: git is not installed."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: ./add_skill.sh <github-repo-url> [skill-name]"
    echo "Example: ./add_skill.sh https://github.com/vercel-labs/skill-search"
    exit 1
fi

REPO_URL=$1
SKILL_NAME=$2

# If skill name not provided, extract from repo URL
if [ -z "$SKILL_NAME" ]; then
    SKILL_NAME=$(basename "$REPO_URL" .git)
fi

TARGET_DIR="./skills/$SKILL_NAME"

if [ -d "$TARGET_DIR" ]; then
    echo "⚠️  Skill directory '$TARGET_DIR' already exists."
    read -p "Do you want to update (pull) it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$TARGET_DIR"
        git pull
        echo "✅ Skill '$SKILL_NAME' updated."
    else
        echo "⏭️  Skipping."
    fi
else
    echo "⬇️  Cloning '$SKILL_NAME' from $REPO_URL..."
    git clone "$REPO_URL" "$TARGET_DIR"
    echo "✅ Skill '$SKILL_NAME' installed successfully to ./skills/$SKILL_NAME"
fi

echo "🔄 Please restart your OpenClaw agent to load the new skill:"
echo "   docker compose restart openclaw"
