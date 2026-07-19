#!/usr/bin/env bash
set -e

# devcontainer/install-dotfiles
# POSIX-compliant shell script to install and configure zsh and neovim in dev containers.

echo "🚀 Starting DevContainer Dotfiles installation..."

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# 1. Detect OS/Package Manager and privilege level
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi
fi

# Check if we can run commands with root privileges (either as root or via passwordless sudo)
can_run_root() {
    [ "$(id -u)" -eq 0 ] || { [ -n "$SUDO" ] && $SUDO -n true 2>/dev/null; }
}

# Detect package manager and install packages
install_packages() {
    if ! can_run_root; then
        echo "⚠️ Warning: No root or passwordless sudo privileges. Skipping system package installation."
        echo "   Please ensure zsh, git, curl, tar, and unzip are pre-installed in the container image."
        return 0
    fi

    # Packages to install: zsh, git, curl, tar, unzip, ripgrep
    # Neovim and ripgrep will be downloaded as binary releases if missing.
    echo "📦 Installing system packages (zsh, git, curl, tar, unzip, ripgrep)..."
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -y
        $SUDO apt-get install -y zsh git curl tar unzip ripgrep
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache zsh git curl tar unzip ripgrep
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y zsh git curl tar unzip ripgrep
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -S --noconfirm zsh git curl tar unzip ripgrep
    elif command -v xbps-install >/dev/null 2>&1; then
        $SUDO xbps-install -y zsh git curl tar unzip ripgrep
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y zsh git curl tar unzip ripgrep
    else
        echo "⚠️ Unknown package manager. Skipping package installation. Please ensure zsh, git, curl, and tar are installed."
    fi
}

install_packages

# Ensure git is available (required for cloning plugins/themes later)
if ! command -v git >/dev/null 2>&1; then
    echo "📥 git not found. Attempting to install git..."
    if can_run_root; then
        if command -v apt-get >/dev/null 2>&1; then
            $SUDO apt-get update -y && $SUDO apt-get install -y git
        elif command -v apk >/dev/null 2>&1; then
            $SUDO apk add --no-cache git
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y git
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO pacman -S --noconfirm git
        elif command -v xbps-install >/dev/null 2>&1; then
            $SUDO xbps-install -y git
        elif command -v zypper >/dev/null 2>&1; then
            $SUDO zypper install -y git
        else
            echo "❌ Unable to install git: unknown package manager."
            exit 1
        fi
    else
        echo "❌ git is required but not installed, and no root/sudo privileges available."
        echo "   Please install git in the container image before running this script."
        exit 1
    fi
fi

# Detect system architecture
ARCH=$(uname -m)
NVIM_ARCH=""
RG_ARCH=""

case "$ARCH" in
    x86_64)
        NVIM_ARCH="x86_64"
        RG_ARCH="x86_64-unknown-linux-musl"
        ;;
    aarch64|arm64)
        NVIM_ARCH="arm64"
        RG_ARCH="aarch64-unknown-linux-gnu"
        ;;
    *)
        echo "⚠️ Warning: Unsupported architecture ($ARCH) for portable binaries. Will default to x86_64."
        NVIM_ARCH="x86_64"
        RG_ARCH="x86_64-unknown-linux-musl"
        ;;
esac

# 2. Install Zsh if missing (either from package manager above, or portable zsh-bin)
if ! command -v zsh >/dev/null 2>&1; then
    echo "📥 Installing portable Zsh via zsh-bin..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" -- -d "$HOME/.local" -e no -q
    export PATH="$HOME/.local/bin:$PATH"
fi

# 3. Install Ripgrep if missing
RG_VERSION="15.1.0"
if ! command -v rg >/dev/null 2>&1; then
    echo "📥 Installing Ripgrep (${ARCH})..."
    TEMP_DIR=$(mktemp -d)
    curl -sL "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-${RG_ARCH}.tar.gz" | tar xzf - -C "$TEMP_DIR"
    mkdir -p "$HOME/.local/bin"
    find "$TEMP_DIR" -type f -name "rg" -exec cp {} "$HOME/.local/bin/" \;
    rm -rf "$TEMP_DIR"
    export PATH="$HOME/.local/bin:$PATH"
fi

# 4. Install/Upgrade Neovim (requires v0.12.0+ to support your config)
NVIM_REQUIRED_MAJOR=0
NVIM_REQUIRED_MINOR=12
NVIM_VERSION_TAG="v0.12.4"

INSTALL_NVIM=false

if command -v nvim >/dev/null 2>&1; then
    CURRENT_VERSION=$(nvim --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    if [ -n "$CURRENT_VERSION" ]; then
        MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
        MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
        if [ "$MAJOR" -lt "$NVIM_REQUIRED_MAJOR" ] || { [ "$MAJOR" -eq "$NVIM_REQUIRED_MAJOR" ] && [ "$MINOR" -lt "$NVIM_REQUIRED_MINOR" ]; }; then
            echo "⚠️ Installed Neovim ($CURRENT_VERSION) is older than v${NVIM_REQUIRED_MAJOR}.${NVIM_REQUIRED_MINOR}.0. Upgrading to ${NVIM_VERSION_TAG}..."
            INSTALL_NVIM=true
        else
            echo "✅ Neovim ($CURRENT_VERSION) is already installed and compatible."
        fi
    else
        echo "⚠️ Failed to detect Neovim version. Reinstalling to be safe..."
        INSTALL_NVIM=true
    fi
else
    echo "🔍 Neovim is not installed. Installing ${NVIM_VERSION_TAG}..."
    INSTALL_NVIM=true
fi

if [ "$INSTALL_NVIM" = true ]; then
    echo "📥 Downloading Neovim ${NVIM_VERSION_TAG} pre-built binary release (${NVIM_ARCH})..."
    mkdir -p "$HOME/.local"
    # Download the Linux pre-built binary
    curl -sL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION_TAG}/nvim-linux-${NVIM_ARCH}.tar.gz" | tar xzf - -C "$HOME/.local" --strip-components=1
    export PATH="$HOME/.local/bin:$PATH"
fi

# 5. Install Tree-sitter CLI if missing
TS_VERSION="v0.26.11"
if ! command -v tree-sitter >/dev/null 2>&1; then
    echo "📥 Installing Tree-sitter CLI (${ARCH})..."
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    TS_OS="linux"
    if [ "$OS" = "darwin" ]; then
        TS_OS="macos"
    fi

    TS_ARCH="x64"
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        TS_ARCH="arm64"
    fi

    TEMP_DIR=$(mktemp -d)
    if curl -sL --fail "https://github.com/tree-sitter/tree-sitter/releases/download/${TS_VERSION}/tree-sitter-cli-${TS_OS}-${TS_ARCH}.zip" -o "$TEMP_DIR/tree-sitter.zip"; then
        unzip -q "$TEMP_DIR/tree-sitter.zip" -d "$TEMP_DIR"
        mkdir -p "$HOME/.local/bin"
        cp "$TEMP_DIR/tree-sitter" "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/tree-sitter"
        export PATH="$HOME/.local/bin:$PATH"
        echo "✅ Tree-sitter CLI version ${TS_VERSION} installed successfully."
    else
        echo "⚠️ Failed to download Tree-sitter CLI pre-built binary."
    fi
    rm -rf "$TEMP_DIR"
fi

# 6. Install Oh My Zsh and plugins (non-interactive)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "🚀 Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "$ZSH_CUSTOM/themes" "$ZSH_CUSTOM/plugins"

# Install Powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    echo "🎨 Installing Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# Install zsh-autosuggestions plugin
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    echo "🔌 Installing zsh-autosuggestions plugin..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# Install zsh-syntax-highlighting plugin
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    echo "🔌 Installing zsh-syntax-highlighting plugin..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# 7. Copy configuration files (avoiding broken symlinks in transient containers)
echo "📋 Copying configuration files..."
mkdir -p "$HOME/.config"

# Copy configurations from repo to ~/.config
for dir in nvim zsh; do
    if [ -d "$REPO_DIR/.config/$dir" ]; then
        rm -rf "$HOME/.config/$dir"
        cp -R "$REPO_DIR/.config/$dir" "$HOME/.config/$dir"
        echo "   Copied config: ~/.config/$dir <- $REPO_DIR/.config/$dir"
    fi
done

# Copy files from repo/home to ~
if [ -d "$REPO_DIR/home" ]; then
    for file in "$REPO_DIR"/home/* "$REPO_DIR"/home/.*; do
        if [ -e "$file" ]; then
            basename_file=$(basename "$file")
            if [ "$basename_file" != "." ] && [ "$basename_file" != ".." ] && [ "$basename_file" != ".git" ] && [ "$basename_file" != "*" ]; then
                rm -rf "$HOME/$basename_file"
                cp -R "$file" "$HOME/$basename_file"
                echo "   Copied home: ~/$basename_file <- $file"
            fi
        fi
    done
fi

# 8. Bootstrap Neovim plugins
if command -v nvim >/dev/null 2>&1; then
    echo "⚡ Bootstrapping Neovim plugins (vim.pack)..."
    nvim --headless "+PackRevert" +qa || true
fi

echo "🎉 DevContainer Dotfiles Setup Complete!"
