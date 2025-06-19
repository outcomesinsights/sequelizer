#!/bin/bash
set -e

echo "Setting up Claude Code credentials..."

# Check if we have read-only mounted credentials
if [ -d "/tmp/host-claude" ]; then
    echo "Found mounted credentials at /tmp/host-claude"

    # Create the .claude directory in the user's home
    mkdir -p ~/.claude

    # Copy credentials file specifically
    if [ -f "/tmp/host-claude/.credentials.json" ]; then
        cp "/tmp/host-claude/.credentials.json" ~/.claude/
        chmod 600 ~/.claude/.credentials.json
        echo "✓ Claude credentials copied and secured"
    else
        echo "⚠ No .credentials.json found in mounted directory"
    fi

    # Copy other configuration files if they exist
    for file in /tmp/host-claude/*.json; do
        if [ -f "$file" ] && [ "$(basename "$file")" != ".credentials.json" ]; then
            cp "$file" ~/.claude/
        fi
    done

    # Set proper permissions for security
    chmod 700 ~/.claude
    find ~/.claude -type f -not -name ".credentials.json" -exec chmod 644 {} \;

    echo "✓ Claude configuration files copied"

    # Verify credential files exist
    if [ -f ~/.claude/.credentials.json ]; then
        echo "✓ Credentials file found and accessible"
    else
        echo "⚠ Warning: No credentials file found in ~/.claude"
        echo "Available files:"
        ls -la ~/.claude/ || echo "Directory is empty"
    fi
else
    echo "⚠ No Claude credentials found at /tmp/host-claude"
    echo "You may need to authenticate Claude Code manually after container startup"
    echo "Run: claude auth login"
fi

# Install Ruby gems
echo "Installing Ruby gems..."
if [ -f "Gemfile" ]; then
    bundle install
    echo "✓ Ruby gems installed successfully"
else
    echo "⚠ No Gemfile found, skipping gem installation"
fi

# Initialize firewall if script exists and we have required capabilities
if [ -f "/usr/local/bin/init-firewall.sh" ]; then
    echo "Initializing firewall..."
    if sudo /usr/local/bin/init-firewall.sh; then
        echo "✓ Firewall initialized successfully"
    else
        echo "⚠ Firewall initialization failed - continuing without network restrictions"
        echo "Note: Container may need NET_ADMIN and NET_RAW capabilities for firewall"
    fi
else
    echo "⚠ Firewall script not found, skipping network security setup"
fi

# Verify Claude Code installation
echo "Verifying Claude Code installation..."
if command -v claude >/dev/null 2>&1; then
    echo "✓ Claude Code CLI found at: $(which claude)"

    # Test basic Claude Code functionality (non-interactive)
    if claude --version >/dev/null 2>&1; then
        echo "✓ Claude Code is working correctly"
    else
        echo "⚠ Claude Code binary found but may not be properly configured"
    fi
else
    echo "⚠ Claude Code CLI not found in PATH"
    echo "You may need to install it manually with: npm install -g @anthropic-ai/claude-code"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. If credentials weren't found, authenticate with: claude auth login"
echo "2. Test Claude Code with: claude --help"
echo "3. Start coding with AI assistance: claude"
echo ""

