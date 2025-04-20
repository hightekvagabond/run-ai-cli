#!/bin/bash
# Simple script to debug the Codex installation in a Docker container

echo "Starting debug session for Codex in Docker..."

# Create a simple interactive Docker container with Node 22
docker run -it --rm \
    -v "$(pwd)":/workspace \
    -e OPENAI_API_KEY="$OPENAI_API_KEY" \
    -w /workspace \
    --entrypoint /bin/bash \
    node:22

# Inside the container, you can run these commands manually:
# apt-get update
# apt-get install -y git
# git clone https://github.com/openai/codex.git /tmp/codex
# cd /tmp/codex/codex-cli
# node -v
# corepack enable
# npm install
# npm run build
# npm link
# which codex
# export NODE_PATH=$(npm root -g)
# codex --help
