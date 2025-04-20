# AI CLI Runner

A unified script to run AI coding assistants in Docker containers.

## Overview

This script allows you to run either Claude Code CLI or OpenAI Codex in Docker containers from any directory on your system. It handles configuration, API keys, and environment setup automatically.

## Features

- Run either Claude Code CLI or OpenAI Codex from any directory
- Docker containerization for security and isolation
- Automatic configuration management
- Secure storage of API keys in project-specific .env files
- Automatic .gitignore management to prevent accidental credential leaks
- Interactive mode to guide you through setup
- Support for Bitwarden secret management

## Prerequisites

- Docker installed on your system
- Bash shell
- (Optional) Bitwarden CLI for secure credential management
- API keys for the services you want to use

## Installation

1. Download all three scripts to a directory on your system:
   - `ai-launcher.sh` - The main launcher script
   - `claude-cli.sh` - The Claude-specific script
   - `codex-cli.sh` - The Codex-specific script

2. Make all scripts executable:
   ```bash
   chmod +x ai-launcher.sh claude-cli.sh codex-cli.sh
   ```

3. Create an alias in your shell configuration:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   alias ai='~/path/to/ai-launcher.sh'
   ```

4. Reload your shell configuration:
   ```bash
   source ~/.bashrc  # or source ~/.zshrc
   ```

## Usage

### Basic Usage

Simply navigate to the directory you want to work in and run:

```bash
ai
```

You'll be prompted to choose which AI tool to use, and the script will handle the rest.

### Specifying a Tool

```bash
ai --tool claude    # Run Claude Code CLI
ai --tool codex     # Run OpenAI Codex CLI
```

### Advanced Options

```bash
# Use OpenAI Codex with a specific model and auto-approve code changes
ai --tool codex --model gpt-4.1 --auto-approve

# Run in non-interactive mode (for scripts)
ai --tool claude --non-interactive

# Show help for environment variables and configuration
ai --env-help
```

## Configuration

The script automatically handles configuration for both tools:

### Claude Code CLI

- Automatically installs the Claude Code CLI in a Docker container
- Uses your existing Claude API key from environment or Bitwarden
- Mounts your current directory as the workspace

### OpenAI Codex CLI

- Clones and builds the OpenAI Codex CLI directly from GitHub
- Creates necessary configuration in the container
- Uses your OpenAI API key from environment, .env file, or Bitwarden
- Prompts for the API key if not found

## Environment Variables

- `CLAUDE_API_KEY` - API key for Claude
- `OPENAI_API_KEY` - API key for OpenAI
- `CODEX_MODEL` - Model to use with Codex (default: o4-mini)

## Security

- API keys are stored in project-specific `.env` files
- `.env` files are automatically added to `.gitignore`
- All code execution happens in isolated Docker containers
- Network access is restricted within containers

## Troubleshooting

### OpenAI Codex Issues

If you encounter issues with Codex:
- Ensure your OpenAI API key is valid and has appropriate permissions
- The first run might take a few minutes as it needs to clone and build the Codex CLI
- You can use the included `debug-codex.sh` script for manual debugging

### Claude Code CLI Issues

If you encounter issues with Claude Code:
- Ensure your Anthropic API key is valid
- Check that you have sufficient permissions in your project directory

## Support

For issues with this script, please open an issue in the repository.

## License

This script is provided under the MIT License.
