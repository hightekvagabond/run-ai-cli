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
AUTO_APPROVE=false
CODEX_MODEL="o4-mini"  # Default model for OpenAI Codex
INTERACTIVE=true       # Default to interactive mode

function show_help() {
    echo "Usage: $0 [options] [command arguments]"
    echo ""
    echo "Options:"
    echo "  --auto-approve      Auto-approve Codex commands"
    echo "  --model <model>     Specify OpenAI model to use with Codex (default: o4-mini)"
    echo "  --non-interactive   Don't prompt for missing values, fail instead"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                  # Run OpenAI Codex with defaults"
    echo "  $0 --model gpt-4.1                 # Run with a specific model"
    echo "  $0 --auto-approve                  # Auto-approve commands"
    echo "  $0 --auto-approve 'Create a Flask app'  # Run with auto-approval and a prompt"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
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
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Function to add a value to .env file
function add_to_env_file() {
    local var_name="$1"
    local var_value="$2"
    local env_file="$CALL_DIR/.env"
    
    # Check if the variable has a value
    if [ -z "$var_value" ]; then
        debug_msg "Not adding empty value for $var_name to .env file"
        return 0
    fi
    
    debug_msg "Adding $var_name to .env file"
    
    # Create or update .env file
    if [ -f "$env_file" ]; then
        # Check if variable already exists in .env
        if grep -q "^$var_name=" "$env_file"; then
            # Variable exists, update it
            debug_msg "Updating existing $var_name in .env file"
            # Use sed to replace the line
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS version of sed requires empty string for -i
                sed -i '' "s|^$var_name=.*|$var_name=\"$var_value\"|" "$env_file"
            else
                # Linux version
                sed -i "s|^$var_name=.*|$var_name=\"$var_value\"|" "$env_file"
            fi
        else
            # Variable doesn't exist, append it
            debug_msg "Appending $var_name to .env file"
            echo "$var_name=\"$var_value\"" >> "$env_file"
        fi
    else
        # File doesn't exist, create it
        debug_msg "Creating .env file with $var_name"
        echo "$var_name=\"$var_value\"" > "$env_file"
    fi
}

# Function to ensure .env is in .gitignore
function ensure_gitignore() {
    local gitignore_file="$CALL_DIR/.gitignore"
    
    # Check if .git directory exists (i.e., it's a git repository)
    if [ -d "$CALL_DIR/.git" ]; then
        debug_msg "Git repository detected, ensuring .env is in .gitignore"
        
        # Create .gitignore if it doesn't exist
        if [ ! -f "$gitignore_file" ]; then
            debug_msg "Creating .gitignore file"
            echo ".env" > "$gitignore_file"
        else
            # Check if .env is already in .gitignore
            if ! grep -q "^\.env$" "$gitignore_file"; then
                debug_msg "Adding .env to .gitignore"
                echo ".env" >> "$gitignore_file"
            else
                debug_msg ".env is already in .gitignore"
            fi
        fi
    else
        debug_msg "Not a git repository, skipping .gitignore update"
    fi
}

# Function to interactively prompt for required values
function prompt_for_value() {
    local var_name="$1"
    local prompt_text="$2"
    local secure="$3"
    local default_value="${4:-}"
    local save_to_env="${5:-false}"
    
    # Check if the variable already has a value
    if [ -n "${!var_name:-}" ]; then
        debug_msg "$var_name already set to: ${!var_name:0:3}..."
        return 0
    fi
    
    # If non-interactive mode, use default or fail
    if [ "$INTERACTIVE" = false ]; then
        if [ -n "$default_value" ]; then
            eval "$var_name=\"$default_value\""
            debug_msg "Using default value for $var_name: $default_value"
            return 0
        else
            echo "Error: Required value $var_name is missing and --non-interactive mode is enabled."
            return 1
        fi
    fi
    
    # Prepare default value display
    local default_display=""
    if [ -n "$default_value" ]; then
        default_display=" [$default_value]"
    fi
    
    # Prompt for the value
    local input_value=""
    if [ "$secure" = "true" ]; then
        # For secure input (passwords, API keys)
        echo -n "$prompt_text$default_display: " >&2
        read -s input_value
        echo "" >&2  # Add a newline after the secure input
    else
        # For regular input
        echo -n "$prompt_text$default_display: " >&2
        read input_value
    fi
    
    # Use default if empty input and default exists
    if [ -z "$input_value" ] && [ -n "$default_value" ]; then
        input_value="$default_value"
    fi
    
    # Set the variable in the parent scope
    eval "$var_name=\"$input_value\""
    
    # Save to .env file if requested and the value is not empty
    if [ "$save_to_env" = "true" ] && [ -n "$input_value" ]; then
        add_to_env_file "$var_name" "$input_value"
    fi
    
    # Return success if we have a value, failure otherwise
    [ -n "$input_value" ]
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

# --- STEP 3: Ensure .gitignore includes .env ---
ensure_gitignore

# --- STEP 3.5: Check if env-keys file exists ---
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

# --- STEP 3.6: Check for .env file and pass AWS credentials ---
ENV_FILE="$CALL_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    debug_msg "Found .env file: $ENV_FILE"
    # Extract AWS credentials from .env file and add to Docker args
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or comments
        if [ -z "$line" ] || [[ "$line" == \#* ]]; then
            continue
        fi
        
        # Process all environment variables
        if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
            ENV_NAME="${BASH_REMATCH[1]}"
            ENV_VALUE="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            ENV_VALUE="${ENV_VALUE%\"}"
            ENV_VALUE="${ENV_VALUE#\"}"
            ENV_VALUE="${ENV_VALUE%\'}"
            ENV_VALUE="${ENV_VALUE#\'}"
            
            debug_msg "Adding environment variable: $ENV_NAME"
            ENV_DOCKER_ARGS="$ENV_DOCKER_ARGS -e $ENV_NAME=\"$ENV_VALUE\""
        fi
    done < "$ENV_FILE"
else
    debug_msg "No .env file found at $ENV_FILE"
fi

# --- STEP 4: Create and set up configuration files ---
# Check if codex.json exists, create it if not
CODEX_CONFIG_DIR="$CALL_DIR/.config/codex"
CODEX_CONFIG_FILE="$CODEX_CONFIG_DIR/config.json"

echo "Creating configuration for Codex..."

# Create the config directory if it doesn't exist
if [ ! -d "$CODEX_CONFIG_DIR" ]; then
    echo "Creating Codex config directory: $CODEX_CONFIG_DIR"
    mkdir -p "$CODEX_CONFIG_DIR"
    echo "Directory creation result: $?"
fi

# Check if config file exists
if [ ! -f "$CODEX_CONFIG_FILE" ]; then
    echo "Config file not found, creating: $CODEX_CONFIG_FILE"
    
    # Check for OPENAI_API_KEY
echo "Checking for OpenAI API key..."
if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "OPENAI_API_KEY not found in environment variables."
    # Check in .env file
    if [ -f "$CALL_DIR/.env" ]; then
        echo "Checking .env file for OPENAI_API_KEY..."
        if grep -q "OPENAI_API_KEY" "$CALL_DIR/.env"; then
            echo "Found OPENAI_API_KEY in .env file."
            # Source the .env file
            set -a
            source "$CALL_DIR/.env"
            set +a
        fi
    fi
    
    # Try to get from Bitwarden if still not set
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        echo "Trying to get OPENAI_API_KEY from Bitwarden..."
        OPENAI_API_KEY=$(bw get password "OPENAI_API_KEY" --session "$BW_SESSION" 2>/dev/null)
        if [ -z "$OPENAI_API_KEY" ]; then
            echo "OPENAI_API_KEY not found in Bitwarden."
            echo "Please set OPENAI_API_KEY in your environment or .env file."
            echo "You can generate an API key at https://platform.openai.com/account/api-keys"
            
            if [ "$INTERACTIVE" = true ]; then
                read -p "Do you have an OpenAI API key to enter now? (y/n): " HAVE_KEY
                if [[ "$HAVE_KEY" =~ ^[Yy] ]]; then
                    prompt_for_value "OPENAI_API_KEY" "Please enter your OpenAI API key" "true" "" "true"
                    if [ -n "$OPENAI_API_KEY" ]; then
                        echo "API key saved to .env file."
                        export OPENAI_API_KEY
                    fi
                fi
            fi
        else
            echo "Found OPENAI_API_KEY in Bitwarden."
            export OPENAI_API_KEY
        fi
    fi
fi

if [ -n "${OPENAI_API_KEY:-}" ]; then
    ENV_DOCKER_ARGS="$ENV_DOCKER_ARGS -e OPENAI_API_KEY=\"$OPENAI_API_KEY\""
    echo "OpenAI API key is configured."
else
    echo "WARNING: No OpenAI API key found. Codex may not function properly."
fi
    
    # Debug: show the target path
    echo "CONFIG PATH: $CODEX_CONFIG_FILE"
    echo "Parent directory exists: $(if [ -d "$CODEX_CONFIG_DIR" ]; then echo "YES"; else echo "NO"; fi)"
    echo "Parent directory permissions: $(ls -ld "$CODEX_CONFIG_DIR" 2>/dev/null || echo "Cannot list directory")"
    
    # Create the config file using redirection
    echo "Creating config file with cat..."
    cat > "$CODEX_CONFIG_FILE" << EOF
{
  "model": "$CODEX_MODEL",
  "temperature": 0.7,
  "max_tokens": 4000,
  "top_p": 1
}
EOF
    RESULT=$?
    echo "Config file creation result: $RESULT"
    
    # Try another approach if the first failed
    if [ $RESULT -ne 0 ]; then
        echo "Trying alternative approach with echo..."
        echo '{
  "model": "'"$CODEX_MODEL"'",
  "temperature": 0.7,
  "max_tokens": 4000,
  "top_p": 1
}' > "$CODEX_CONFIG_FILE"
        echo "Alternative creation result: $?"
    fi
    
    # Check if file exists
    if [ -f "$CODEX_CONFIG_FILE" ]; then
        echo "Config file exists after creation."
        echo "File content:"
        cat "$CODEX_CONFIG_FILE" || echo "Failed to read file"
    else
        echo "ERROR: Config file still does not exist after creation attempt!"
        echo "Current directory: $(pwd)"
        echo "Listing .config directory:"
        ls -la "$CALL_DIR/.config" || echo "Cannot list .config directory"
    fi
else
    echo "Codex config file already exists: $CODEX_CONFIG_FILE"
    echo "File content:"
    cat "$CODEX_CONFIG_FILE" 2>/dev/null || echo "Could not read config file"
fi

# --- STEP 5: Create a Docker container for Codex ---
echo "Starting OpenAI Codex CLI in $CALL_DIR..."

# Set approval mode flag for codex if auto-approve is true
APPROVAL_FLAG=""
if [ "$AUTO_APPROVE" = true ]; then
    APPROVAL_FLAG="--approval-mode auto"
fi

# Add OPENAI_API_KEY to Docker command
if [ -n "${OPENAI_API_KEY:-}" ]; then
    ENV_DOCKER_ARGS="$ENV_DOCKER_ARGS -e OPENAI_API_KEY=\"$OPENAI_API_KEY\""
fi

# Build the docker command for OpenAI Codex
DOCKER_CMD="docker run -it --rm \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    -v \"$CALL_DIR\":/workspace \
    ${OPENAI_API_KEY:+"-e OPENAI_API_KEY=\"$OPENAI_API_KEY\""} \
    $ENV_DOCKER_ARGS \
    -w /workspace \
    --entrypoint /bin/bash \
    node:22 -c \"
    echo 'Installing dependencies...' && \
    apt-get update -qq && \
    apt-get install -y -qq git && \
    echo 'Cloning OpenAI Codex repository...' && \
    git clone https://github.com/openai/codex.git /tmp/codex && \
    cd /tmp/codex/codex-cli && \
    echo 'Building Codex CLI...' && \
    corepack enable && \
    npm install && \
    npm run build && \
    npm link && \
    echo 'Configuration path: /home/node/.config/codex' && \
    mkdir -p /home/node/.config/codex && \
    echo '{\\\"model\\\": \\\"$CODEX_MODEL\\\", \\\"temperature\\\": 0.7, \\\"max_tokens\\\": 4000, \\\"top_p\\\": 1}' > /home/node/.config/codex/config.json && \
    cat /home/node/.config/codex/config.json && \
    cd /workspace && \
    echo 'Starting OpenAI Codex CLI...' && \
    export NODE_PATH=\\\$(npm root -g) && \
    codex $APPROVAL_FLAG $*\""
    
echo "Executing: OpenAI Codex CLI"
debug_msg "Docker command: $DOCKER_CMD"

# Execute the Docker command
eval "$DOCKER_CMD"
EXIT_CODE=$?
debug_msg "Docker command exited with code: $EXIT_CODE"
exit $EXIT_CODE
