#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Get repository root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting macOS setup with Nix and Home Manager..."

# 1. Install Nix using the Determinate Nix Installer
if ! command -v nix &> /dev/null; then
  echo "📦 Nix not found. Installing Nix via Determinate Nix Installer..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  
  # Source Nix profile to make it immediately available in the current session
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
else
  echo "✅ Nix is already installed."
fi

# Double check if nix is now available
if ! command -v nix &> /dev/null; then
  echo "❌ Nix installation succeeded, but the 'nix' command is not available in the current session."
  echo "💡 Please open a new terminal session or run: source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  exit 1
fi

# 2. Run setup_settings.sh to set up general dotfiles and configurations
echo "⚙️ Running general dotfiles setup..."
"$SCRIPT_DIR/setup_settings.sh"

# 3. Run Home-Manager switch
echo "🏠 Activating Home Manager configuration..."
nix run github:nix-community/home-manager --extra-experimental-features "nix-command flakes" -- switch --flake "$HOME/.config/home-manager#default" --impure

echo "✅ macOS Nix and Home Manager setup completed successfully!"
