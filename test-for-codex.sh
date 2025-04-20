#!/bin/sh

# Inside the container, you can run these commands manually:
apt-get update
apt-get install -y git
git clone https://github.com/openai/codex.git /tmp/codex
cd /tmp/codex/codex-cli
node -v
corepack enable
npm install
npm run build
npm link
which codex
export NODE_PATH=$(npm root -g)
codex --help
