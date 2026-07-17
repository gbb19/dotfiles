#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Helper function to print section titles
echo_title() {
  echo -e "\n🔷 $1"
}

# Detect OS distribution
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # Sourcing os-release to get ID
    . /etc/os-release
    OS="$ID"
    # Map derivatives to parent OS if necessary
    if [[ "$OS" == "ubuntu" || "$OS" == "linuxmint" || "$OS" == "pop" ]]; then
      OS="debian"
    elif [[ "$OS" == "opensuse-leap" || "$OS" == "opensuse-tumbleweed" ]]; then
      OS="opensuse"
    fi
  else
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  fi

  # Fallback if OS is empty
  OS="${OS:-unknown}"
}

# Function to install packages
install_packages() {
  # Define common packages
  local common_packages=(
    git
    git-delta
    neovim
    zsh
    zoxide
    htop
    tmux
    unzip
    zip
    ripgrep
    fzf
    rsync
    curl
  )

  local os_specific_packages=("${common_packages[@]}") # Start with common packages

  # Add Go and fd-find based on OS
  if [[ "$OS" == "fedora" ]]; then
    os_specific_packages+=(fd-find)
  elif [[ "$OS" == "arch" ]]; then
    os_specific_packages+=(fd) # Arch uses 'fd'
  elif [[ "$OS" == "void" ]]; then
    os_specific_packages+=(fd) # Void uses 'go' and 'fd'
  elif [[ "$OS" == "debian" ]]; then
    os_specific_packages+=(fd-find) # Debian uses 'golang-go' and 'fd-find'
  elif [[ "$OS" == "opensuse" ]]; then
    os_specific_packages+=(fd) # openSUSE uses 'go' and 'fd'
  fi

  echo_title "📦 Installing essential packages for $OS..."

  for pkg in "${os_specific_packages[@]}"; do
    if [[ "$OS" == "void" && "$pkg" == "fish" ]]; then
        pkg="fish-shell"
    fi

    echo "➕ Installing $pkg..."
    if [[ "$OS" == "arch" ]]; then
      sudo pacman -S --noconfirm "$pkg" || { echo "❌ Failed to install $pkg. Please check your network or repository settings."; exit 1; }
    elif [[ "$OS" == "fedora" ]]; then
      sudo dnf install -y "$pkg" || { echo "❌ Failed to install $pkg. Please check your network or repository settings."; exit 1; }
    elif [[ "$OS" == "void" ]]; then
      sudo xbps-install -y "$pkg" || { echo "❌ Failed to install $pkg. Please check your network or repository settings."; exit 1; }
    elif [[ "$OS" == "debian" ]]; then
      # For Debian, ensure apt is updated before installing
      sudo apt update -y && sudo apt install -y "$pkg" || { echo "❌ Failed to install $pkg. Please check your network or repository settings."; exit 1; }
    elif [[ "$OS" == "opensuse" ]]; then
      # For openSUSE, use zypper to install packages
      sudo zypper install -y "$pkg" || { echo "❌ Failed to install $pkg. Please check your network or repository settings."; exit 1; }
    else
      echo "Skipping package installation: Unsupported OS."
      return 1 # Exit this function if OS is unknown
    fi
    echo "✅ $pkg installation command sent."
  done
}

# Function to install devcontainer CLI
install_devcontainer_cli() {
  if ! command -v devcontainer &> /dev/null; then
    echo_title "📦 Installing devcontainer CLI..."
    curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh
  else
    echo "✅ devcontainer CLI is already installed."
  fi
}

# Main execution
detect_os
install_packages
install_devcontainer_cli
