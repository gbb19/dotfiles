#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory where this script is located and resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Function to create symlinks (as requested by the user)
create_symlinks() {
  local src_dir="$1"
  local dest_dir="$2"
  local ts
  ts=$(date +%s)

  # Ensure destination directory exists
  mkdir -p "$dest_dir"

  # Use globbing for normal and hidden files
  for item in "$src_dir"/* "$src_dir"/.*; do
    [ -e "$item" ] || continue
    base=$(basename "$item")
    # Skip . and ..
    if [[ "$base" == "." || "$base" == ".." ]]; then
      continue
    fi
    # Skip home-manager to copy it instead of symlinking
    if [[ "$base" == "home-manager" ]]; then
      continue
    fi
    # Skip ghq on macOS since the one in repo is a Linux binary
    if [[ "$base" == "ghq" && "$(uname -s)" == "Darwin" ]]; then
      echo "⏭️ Skipping ghq symlink on macOS (Linux binary format)"
      continue
    fi

    target="$dest_dir/$base"

    # If target is a symlink pointing to same location, skip
    if [[ -L "$target" ]]; then
      if [[ "$(readlink -f "$target")" == "$(readlink -f "$item")" ]]; then
        echo "↩️ Symlink exists for $target; skipping"
        continue
      else
        mv "$target" "$target.backup.$ts"
        echo "⚠️ Moved existing symlink $target to backup"
      fi
    elif [[ -e "$target" ]]; then
      mv "$target" "$target.backup.$ts"
      echo "⚠️ Moved existing $target to $target.backup.$ts"
    fi

    ln -s "$item" "$target" || { echo "❌ Failed to create symlink $target -> $item"; exit 1; }
    echo "🔗 Linked $target -> $item"
  done
}

# Function to copy files instead of symlinking
copy_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local ts
  ts=$(date +%s)

  # Ensure destination directory exists
  mkdir -p "$dest_dir"

  # Use globbing for normal and hidden files
  for item in "$src_dir"/* "$src_dir"/.*; do
    [ -e "$item" ] || continue
    base=$(basename "$item")
    # Skip . and ..
    if [[ "$base" == "." || "$base" == ".." ]]; then
      continue
    fi

    target="$dest_dir/$base"

    # If target is a symlink, back it up
    if [[ -L "$target" ]]; then
      mv "$target" "$target.backup.$ts"
      echo "⚠️ Moved existing symlink $target to backup"
    # If target exists as a file or directory
    elif [[ -e "$target" ]]; then
      # If both are files, compare them first. If they are identical, skip.
      if [[ -f "$target" && -f "$item" ]]; then
        if cmp -s "$target" "$item"; then
          echo "↩️ File $target is identical to $item; skipping"
          continue
        fi
      fi
      mv "$target" "$target.backup.$ts"
      echo "⚠️ Moved existing $target to $target.backup.$ts"
    fi

    # Copy files/directories recursively
    cp -R "$item" "$target" || { echo "❌ Failed to copy $item -> $target"; exit 1; }
    echo "📋 Copied $item -> $target"
  done
}
# Helper function to print section titles
echo_title() {
  echo -e "\n🔷 $1"
}

# Function to change default shell to zsh
change_default_shell_to_zsh() {
  if [[ "$SHELL" != *"zsh" ]]; then
    echo_title "🔄 Changing default shell to zsh..."
    local zsh_path
    zsh_path="$(command -v zsh)" # Find zsh path
    if [[ -n "$zsh_path" ]]; then
      chsh -s "$zsh_path" || { echo "❌ Failed to change default shell to zsh. Check permissions or zsh path."; exit 1; }
      echo "✅ Default shell changed to zsh. Please log out and log back in for changes to take effect."
    else
      echo "❌ zsh not found in PATH. Please ensure zsh is installed correctly."
    fi
  else
    echo "✅ Shell is already zsh."
  fi
}

# Function to install Oh My Zsh and plugins
install_oh_my_zsh_and_plugins() {
  echo_title "🚀 Installing Oh My Zsh and Plugins..."

  # Check if Oh My Zsh is already installed
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "➕ Installing Oh My Zsh..."
    # Use curl to download and run the Oh My Zsh installation script
    # Added --unattended for non-interactive installation
    # Added || true to prevent the script from exiting if there are minor issues with Oh My Zsh's initial setup
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
    echo "✅ Oh My Zsh installed."
  else
    echo "✅ Oh My Zsh already installed."
  fi

  # Define ZSH_CUSTOM for cloning themes and plugins
  # Oh My Zsh will set ZSH_CUSTOM automatically, but we define it for certainty
  export ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/themes" "$ZSH_CUSTOM/plugins" || { echo "❌ Failed to create Oh My Zsh custom directories."; exit 1; }

  # Install Powerlevel10k
  if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
    echo "➕ Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" || { echo "❌ Failed to clone Powerlevel10k. Check git and network."; exit 1; }
    echo "✅ Powerlevel10k installed."
  else
    echo "✅ Powerlevel10k already installed."
  fi

  # Install zsh-autosuggestions
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    echo "➕ Installing zsh-autosuggestions plugin..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || { echo "❌ Failed to clone zsh-autosuggestions. Check git and network."; exit 1; }
    echo "✅ zsh-autosuggestions installed."
  else
    echo "✅ zsh-autosuggestions already installed."
  fi

  # Install zsh-syntax-highlighting
  # Install or update zsh-syntax-highlighting
  plugin_dir="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  if [[ -d "$plugin_dir" ]]; then
    if [[ -d "$plugin_dir/.git" ]]; then
      echo "↻ Updating zsh-syntax-highlighting..."
      if git -C "$plugin_dir" pull --rebase --autostash; then
        echo "✅ zsh-syntax-highlighting updated."
      else
        echo "⚠️ Failed to update zsh-syntax-highlighting via git; leaving existing directory." >&2
      fi
    else
      ts=$(date +%s)
      mv "$plugin_dir" "$plugin_dir.backup.$ts"
      echo "⚠️ Existing non-git directory moved to $plugin_dir.backup.$ts; cloning fresh."
      git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir" || { echo "❌ Failed to clone zsh-syntax-highlighting. Check git and network."; exit 1; }
      echo "✅ zsh-syntax-highlighting installed."
    fi
  else
    echo "➕ Installing zsh-syntax-highlighting plugin..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugin_dir" || { echo "❌ Failed to clone zsh-syntax-highlighting. Check git and network."; exit 1; }
    echo "✅ zsh-syntax-highlighting installed."
  fi

  echo "ℹ️ After setup, you may need to run 'p10k configure' in your new Zsh session to set up your Powerlevel10k prompt."
}

echo "🚀 Starting dotfiles setup..."

# 1. Symlink configurations from repo's .config to ~/.config
SRC_CONFIG="$REPO_DIR/.config"
DEST_CONFIG="$HOME/.config"
echo "⚙️ Setting up .config files..."
create_symlinks "$SRC_CONFIG" "$DEST_CONFIG"

# Copy home-manager configuration instead of symlinking
if [[ -d "$SRC_CONFIG/home-manager" ]]; then
  echo "🏠 Setting up home-manager configuration (copying)..."
  copy_files "$SRC_CONFIG/home-manager" "$DEST_CONFIG/home-manager"
fi

# 2. Symlink bin scripts from repo's bin to ~/.local/bin
SRC_BIN="$REPO_DIR/bin"
DEST_BIN="$HOME/.local/bin"
if [[ -d "$SRC_BIN" ]]; then
  echo "🚀 Setting up bin scripts..."
  # Ensure scripts in repo's bin are executable first
  chmod +x "$SRC_BIN"/* 2>/dev/null || true
  create_symlinks "$SRC_BIN" "$DEST_BIN"
fi

# 3. Change default shell to zsh
change_default_shell_to_zsh

# 4. Install Oh My Zsh and plugins
install_oh_my_zsh_and_plugins

# 5. Copy home configuration files from repo's home to ~/
SRC_HOME="$REPO_DIR/home"
DEST_HOME="$HOME"
echo "🏠 Setting up home dotfiles..."
copy_files "$SRC_HOME" "$DEST_HOME"

echo "✅ Dotfiles setup completed successfully!"

