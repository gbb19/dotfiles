#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Get repository root directory
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect Operating System
OS_TYPE="$(uname -s)"

echo "🚀 Starting general setup..."

if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "🍏 macOS detected."
  # Execute macOS setup script (which internally runs setup_settings.sh)
  bash "$REPO_DIR/setup/setup_macos.sh"
elif [[ "$OS_TYPE" == "Linux" ]]; then
  echo "🐧 Linux detected."
  # Execute Linux package installation
  bash "$REPO_DIR/setup/setup_linux.sh"
  # Execute general dotfiles setup
  bash "$REPO_DIR/setup/setup_settings.sh"
else
  echo "❌ Unsupported OS: $OS_TYPE"
  exit 1
fi

echo "✅ Setup finished!"
