# Oh My Zsh and Powerlevel10k configuration
# Ensure ZSH environment variable is set in exports.zsh before sourcing this file.

# Set Zsh theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Define Oh My Zsh plugins
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)

# Source Oh My Zsh
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "Warning: Oh My Zsh script not found at $ZSH/oh-my-zsh.sh. Please ensure Oh My Zsh is installed." >&2
fi

# Source Powerlevel10k configuration
# This should be sourced after Oh My Zsh.
if [[ -f "$HOME/.p10k.zsh" ]]; then
  source "$HOME/.p10k.zsh"
else
  echo "Warning: Powerlevel10k configuration file (~/.p10k.zsh) not found. Please run 'p10k configure' to create it." >&2
fi
