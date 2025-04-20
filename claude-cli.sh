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
# --- STEP 1: Bitwarden Session ---
debug_msg "Checking for BW_SESSION environment variable..."
if [ -z "${BW_SESSION:-}" ]; then
    debug_msg "No BW_SESSION found, logging in to Bitwarden..."
    source "$HOME/bin/bw-login.sh" || exit 1
else
    debug_msg "BW_SESSION found: ${BW_SESSION:0:10}..."
    echo "Using existing Bitwarden session."
fi
# --- STEP 2: Get the current directory ---
CALL_DIR="$(pwd -P)"
debug_msg "Current directory: $CALL_DIR"
# --- STEP 3: Check if env-keys file exists ---
ENV_DOCKER_ARGS=""
ENV_KEYS_FILE="$CALL_DIR/env-keys"
if [ -f "$ENV_KEYS_FILE" ]; then
    debug_msg "Found env-keys file: $ENV_KEYS_FILE"
    # Read each line from the env-keys file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or comments
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi
        
        # Parse environment variable name and source
        if [[ "$line" =~ ^([^=]+)=([^:]+):(.+)$ ]]; then
            ENV_NAME="${BASH_REMATCH[1]}"
            SOURCE="${BASH_REMATCH[2]}"
            VALUE_NAME="${BASH_REMATCH[3]}"
            
            debug_msg "Processing: $ENV_NAME from $SOURCE:$VALUE_NAME"
            
            # Handle different source types
            if [ "$SOURCE" = "Bitwarden-note" ]; then
                # Get value from Bitwarden note
                ENV_VALUE=$(bw get notes "$VALUE_NAME" --session "$BW_SESSION" 2>/dev/null)
                if [ -z "$ENV_VALUE" ]; then
                    debug_msg "Failed to get value as note, trying as password..."
                    ENV_VALUE=$(bw get password "$VALUE_NAME" --session "$BW_SESSION" 2>/dev/null)
                fi
                
                if [ -n "$ENV_VALUE" ]; then
                    # Add to docker arguments
                    ENV_DOCKER_ARGS="$ENV_DOCKER_ARGS -e $ENV_NAME=\"$ENV_VALUE\""
                    debug_msg "Added environment variable: $ENV_NAME"
                else
                    echo "Warning: Failed to get value for $ENV_NAME from Bitwarden"
                fi
            else
                echo "Warning: Unsupported source type: $SOURCE"
            fi
        else
            echo "Warning: Invalid format in env-keys file: $line"
        fi
    done < "$ENV_KEYS_FILE"
else
    debug_msg "No env-keys file found at $ENV_KEYS_FILE"
fi
# --- STEP 3.5: Check for .env file and pass AWS credentials ---
ENV_FILE="$CALL_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    debug_msg "Found .env file: $ENV_FILE"
    # Extract AWS credentials from .env file and add to Docker args
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or comments
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi
        
        # Only process AWS-related environment variables
        if [[ "$line" =~ ^(AWS_[^=]+)=(.+)$ ]]; then
            ENV_NAME="${BASH_REMATCH[1]}"
            ENV_VALUE="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            ENV_VALUE="${ENV_VALUE%\"}"
            ENV_VALUE="${ENV_VALUE#\"}"
            ENV_VALUE="${ENV_VALUE%\'}"
            ENV_VALUE="${ENV_VALUE#\'}"
            
            debug_msg "Adding AWS credential: $ENV_NAME"
            ENV_DOCKER_ARGS="$ENV_DOCKER_ARGS -e $ENV_NAME=\"$ENV_VALUE\""
        fi
    done < "$ENV_FILE"
else
    debug_msg "No .env file found at $ENV_FILE"
fi
# --- STEP 4: Create a Docker container that emulates a local Claude Code CLI installation ---
echo "Starting Claude Code CLI in $CALL_DIR..."
# Build the docker command and execute it
DOCKER_CMD="docker run -it --rm \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    -v \"$CALL_DIR\":/workspace \
    -v claude-code-bashhistory:/commandhistory \
    -v claude-code-config:/home/node/.claude \
    -e NODE_OPTIONS=\"--max-old-space-size=4096\" \
    -e CLAUDE_CONFIG_DIR=\"/home/node/.claude\" \
    -e POWERLEVEL9K_DISABLE_GITSTATUS=\"true\" \
    $ENV_DOCKER_ARGS \
    -w /workspace \
    --entrypoint /bin/bash \
    node:20 -c \"npm install -g @anthropic-ai/claude-code && claude $*\""
debug_msg "Executing Docker command: $DOCKER_CMD"
eval "$DOCKER_CMD"
EXIT_CODE=$?
debug_msg "Docker command exited with code: $EXIT_CODE"
exit $EXIT_CODE
