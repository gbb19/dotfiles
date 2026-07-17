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

echo "🚀 Starting dotfiles setup..."

# 1. Symlink configurations from repo's .config to ~/.config
SRC_CONFIG="$REPO_DIR/.config"
DEST_CONFIG="$HOME/.config"
echo "⚙️ Setting up .config files..."
create_symlinks "$SRC_CONFIG" "$DEST_CONFIG"

# 2. Copy home configuration files from repo's home to ~/
SRC_HOME="$REPO_DIR/home"
DEST_HOME="$HOME"
echo "🏠 Setting up home dotfiles..."
copy_files "$SRC_HOME" "$DEST_HOME"

echo "✅ Dotfiles setup completed successfully!"
