# This file is sourced by Zsh on startup.
# It primarily sources other configuration files for better organization.

# Powerlevel10k instant prompt (load as early as possible for fastest startup)
# This must be sourced before Zsh's own initialization and other plugins.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Source common Zsh configuration files
# Check if ~/.config/zsh directory exists
if [[ -d "$HOME/.config/zsh" ]]; then
  # Helper function to source a file if it exists, silently.
  # All output from this function (echo, warning) is removed to prevent P10k warnings.
  source_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
      source "$file" 2>/dev/null || true # Source the file, redirect stderr to /dev/null
    fi
    # No echo messages here to avoid Powerlevel10k instant prompt warnings.
  }

  # Core environment variables and options (load first)
  source_if_exists "$HOME/.config/zsh/exports.zsh"
  # source_if_exists "$HOME/.config/zsh/options.zsh" # Uncomment if you add a general options file

  # Oh My Zsh and Powerlevel10k (load after core exports)
  source_if_exists "$HOME/.config/zsh/custom_apps/oh_my_zsh.zsh"

  # Aliases, Functions, and Keybindings
  source_if_exists "$HOME/.config/zsh/aliases.zsh"
  source_if_exists "$HOME/.config/zsh/functions.zsh"
  source_if_exists "$HOME/.config/zsh/keybindings.zsh"

  # Other Plugin/App specific initializations
  source_if_exists "$HOME/.config/zsh/custom_apps/zoxide.zsh"
  source_if_exists "$HOME/.config/zsh/custom_apps/sdkman.zsh"
  source_if_exists "$HOME/.config/zsh/custom_apps/jabba.zsh"

  # Prompt/Theme (usually loaded last if you have a custom one, but Powerlevel10k is handled in oh_my_zsh.zsh)
  # source_if_exists "$HOME/.config/zsh/prompt.zsh" # Uncomment if you have a custom prompt file (not P10k)
else
  # This error message will still appear if the entire ~/.config/zsh directory is missing.
  echo "Error: ~/.config/zsh directory not found. Zsh configurations may not be loaded." >&2
fi

# Ensure completion system is initialized (essential for Zsh)
# This can be placed directly in .zshrc or a dedicated completions.zsh file
# Note: Oh My Zsh often handles compinit, but it's good to have a fallback/explicit call.
autoload -Uz compinit
compinit

ZSH_AUTOSUGGEST_STRATEGY=(completion)

ZSH_AUTOSUGGEST_IGNORE_COMMANDS=(
  "export *"
  "*SECRET*"
  "*TOKEN*"
  "*KEY*"
  "*PASSWORD*"
)

setopt HIST_IGNORE_SPACE