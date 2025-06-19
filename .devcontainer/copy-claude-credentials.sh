#!/bin/bash
set -euo pipefail

echo "Copying Claude credentials and GitHub config from host..."

# Create .claude directory if it doesn't exist
mkdir -p ~/.claude

# Copy credentials from temporary mounts to proper locations
if [ -d "/tmp/host-claude" ]; then
    cp -r /tmp/host-claude/* ~/.claude/ 2>/dev/null || true
fi

if [ -d "/tmp/host-claude-config" ]; then
    cp -r /tmp/host-claude-config/* ~/.config/claude/ 2>/dev/null || true
fi

if [ -f "/tmp/host-claude.json" ]; then
    cp /tmp/host-claude.json ~/.claude.json
fi

# Create writable GitHub config directory and copy from readonly mount
mkdir -p ~/.config/gh
if [ -d "/tmp/host-gh" ]; then
    cp -r /tmp/host-gh/* ~/.config/gh/ 2>/dev/null || true
fi

# Set proper permissions
chmod 700 ~/.claude
chmod 700 ~/.config/gh 2>/dev/null || true

echo "Done copying Claude credentials and GitHub config"