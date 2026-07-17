# Zoxide initialization
# Ensure zoxide is installed before sourcing
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
# else
#   # Removed echo to prevent console output during instant prompt init
#   # echo "Warning: zoxide not found. Skipping zoxide initialization." >&2
fi

