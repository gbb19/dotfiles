# dotfiles

Modular configuration files for Zsh, Neovim, Tmux, Kitty, VS Code, Zed, and more.

## Repository Structure

- .config/: Configuration files for Kitty, Neovim, Tmux, VS Code, Zed, and Zsh.
- bin/: Custom helper scripts and binaries.
- home/: Standard user dotfiles (such as .zshrc, .gitconfig, .ideavimrc).
- setup/: Setup and installation scripts for different environments.

## Installation

Run the main setup script from the root of the repository. It will automatically detect your operating system and apply the corresponding configuration.

```bash
./setup.sh
```

## Available Setup Scripts

- setup.sh: Main entry point script. Detects OS and runs the appropriate setups.
- setup/setup_settings.sh: Handles configuration symlinking for .config/ (excluding home-manager) and copying for home/ and .config/home-manager/.
- setup/setup_linux.sh: Installs essential system packages on Linux.
- setup/setup_macos.sh: Installs Nix, configures Home Manager, and applies macOS-specific configurations.
- setup/setup_devcontainer.sh: Tailored script for Docker DevContainers (Zsh and Neovim only, no Tmux).
