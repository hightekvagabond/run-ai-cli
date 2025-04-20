#!/bin/bash
# Exit on any failure
set -euo pipefail
# Enable debugging (set to false in production)
DEBUG=true

function debug_msg() {
    if [ "$DEBUG" = true ]; then
        echo "[DEBUG] $1"
    fi
}

# Process command line arguments
TOOL=""  # Empty by default, will prompt user
AUTO_APPROVE=false
CODEX_MODEL="o4-mini"  # Default model for OpenAI Codex
INTERACTIVE=true       # Default to interactive mode

function show_help() {
    echo "Usage: $0 [options] [command arguments]"
    echo ""
    echo "Options:"
    echo "  --tool <tool>       Choose which tool to run: claude or codex (default: prompt user)"
    echo "  --auto-approve      Auto-approve Codex commands (only applicable for codex)"
    echo "  --model <model>     Specify OpenAI model to use with Codex (default: o4-mini)"
    echo "  --non-interactive   Don't prompt for missing values, fail instead"
    echo "  --env-help          Show information about environment variables and configuration"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Prompt for which tool to use"
    echo "  $0 --tool claude    # Run Claude Code CLI"
    echo "  $0 --tool codex     # Run OpenAI Codex CLI"
    echo "  $0 --tool codex --model gpt-4.1 --auto-approve 'Create a simple Flask app'"
}

function show_env_help() {
    echo "============================================================"
    echo "          AI CLI Environment Variables & Configuration       "
    echo "============================================================"
    echo ""
    echo "The script can use the following environment variables:"
    echo ""
    echo "For both tools:"
    echo "  BW_SESSION           - Bitwarden session token (optional, will prompt if needed)"
    echo ""
    echo "For Claude Code CLI:"
    echo "  CLAUDE_API_KEY       - Anthropic API key for Claude"
    echo ""
    echo "For OpenAI Codex:"
    echo "  OPENAI_API_KEY       - OpenAI API key (required)"
    echo "  OPENAI_ORG_ID        - OpenAI organization ID (optional)"
    echo "  CODEX_MODEL          - Model to use (default: o4-mini)"
    echo "  TEMPERATURE          - Temperature setting (default: 0.7)"
    echo "  MAX_TOKENS           - Maximum tokens to generate (default: 4000)"
    echo ""
    echo "Configuration Files:"
    echo "  .config/codex/config.json - Codex configuration file (created automatically if needed)"
    echo ""
    echo "Environment File Support:"
    echo "  env-keys             - File containing Bitwarden secret references"
    echo "                         Format: VAR_NAME=Bitwarden-note:SECRET_NAME"
    echo "  .env                 - Standard .env file for AWS credentials"
    echo "                         Only AWS_* variables are processed"
    echo ""
    echo "Docker Containers:"
    echo "  Claude Code CLI      - Uses node:20 Docker image"
    echo "  OpenAI Codex         - Uses node:22 Docker image"
    echo ""
    echo "Data Persistence:"
    echo "  Claude history       - Stored in Docker volume: claude-code-bashhistory"
    echo "  Claude config        - Stored in Docker volume: claude-code-config"
    echo "  Codex config         - Stored in local directory: .config/codex/"
    echo ""
    echo "============================================================"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool)
            if [ "$2" = "claude" ] || [ "$2" = "codex" ]; then
                TOOL="$2"
                shift 2
            else
                echo "Error: Tool must be either 'claude' or 'codex'"
                exit 1
            fi
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --model)
            CODEX_MODEL="$2"
            shift 2
            ;;
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        --env-help)
            show_env_help
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Store command line arguments for passing to the selected tool
ARGS="$*"

# Get the directory of this script
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# --- Prompt for tool selection if not specified ---
if [ -z "$TOOL" ]; then
    if [ "$INTERACTIVE" = true ]; then
        echo "Please select which AI tool to use:"
        echo "1) Claude Code CLI"
        echo "2) OpenAI Codex"
        read -p "Enter your choice (1 or 2): " choice
        
        case "$choice" in
            1)
                TOOL="claude"
                echo "Selected: Claude Code CLI"
                ;;
            2)
                TOOL="codex"
                echo "Selected: OpenAI Codex"
                ;;
            *)
                echo "Invalid choice. Defaulting to Claude Code CLI."
                TOOL="claude"
                ;;
        esac
    else
        echo "No tool specified and --non-interactive mode is enabled. Defaulting to Claude Code CLI."
        TOOL="claude"
    fi
fi

# Launch the appropriate tool
if [ "$TOOL" = "claude" ]; then
    # Launch the Claude script with all arguments
    "$SCRIPT_DIR/claude-cli.sh" $ARGS
else
    # Build Codex arguments
    CODEX_ARGS=""
    if [ "$AUTO_APPROVE" = true ]; then
        CODEX_ARGS="$CODEX_ARGS --auto-approve"
    fi
    if [ -n "$CODEX_MODEL" ]; then
        CODEX_ARGS="$CODEX_ARGS --model $CODEX_MODEL"
    fi
    if [ "$INTERACTIVE" = false ]; then
        CODEX_ARGS="$CODEX_ARGS --non-interactive"
    fi
    
    # Launch the Codex script with all arguments
    "$SCRIPT_DIR/codex-cli.sh" $CODEX_ARGS $ARGS
fi
