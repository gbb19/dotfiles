# SDKMAN initialization
# THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  source "$HOME/.sdkman/bin/sdkman-init.sh"
# else
#   # Removed echo to prevent console output during instant prompt init
#   # echo "Warning: SDKMAN initialization script not found. Skipping SDKMAN setup." >&2
fi
