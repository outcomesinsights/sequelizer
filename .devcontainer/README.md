# Development Container Setup

This directory contains the development container configuration for the Sequelizer Ruby gem project.

## What's Included

- **Ruby 3.3** with bundler and common development tools
- **Ruby LSP** for intelligent code completion and navigation
- **RuboCop** integration for code formatting and linting
- **PostgreSQL client** for database connectivity testing
- **Git** and **GitHub CLI** for version control workflow
- **Overcommit** hooks for pre-commit validation

## VS Code Extensions

The devcontainer includes these extensions:
- **Shopify.ruby-lsp**: Ruby Language Server Protocol support
- **GitHub.copilot**: AI-powered code completion
- **connorshea.vscode-ruby-test-adapter**: Test integration

## Getting Started

1. **Open in Cursor/VS Code**: Open the project folder in Cursor or VS Code
2. **Reopen in Container**: When prompted, click "Reopen in Container" or use the Command Palette (`Ctrl+Shift+P`) and select "Dev Containers: Reopen in Container"
3. **Wait for Setup**: The container will build and run the setup script automatically
4. **Start Developing**: Once setup is complete, you can run:
   ```bash
   bundle exec rake test      # Run all tests
   bundle exec rake lint      # Check code style
   bundle exec rake coverage  # Generate coverage report
   ```

## Working with Git Worktrees

Since you mentioned using git worktrees, here's how to set up a new worktree with the devcontainer:

```bash
# Create a new worktree for feature development
git worktree add ../sequelizer-feature-branch feature-branch-name

# Navigate to the worktree
cd ../sequelizer-feature-branch

# Open in Cursor/VS Code - the devcontainer will work in any worktree
cursor .  # or code .
```

## Customization

- **Dockerfile**: Modify system-level dependencies
- **devcontainer.json**: Adjust VS Code settings, extensions, and container configuration
- **setup.sh**: Add custom setup commands that run after container creation

## Troubleshooting

If you encounter issues:
1. **Rebuild Container**: Use Command Palette → "Dev Containers: Rebuild Container"
2. **Check Logs**: View the container creation logs for errors
3. **Manual Setup**: Run `bash .devcontainer/setup.sh` manually if needed