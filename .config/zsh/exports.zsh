export EDITOR=nvim
# Environment variables
export PATH=$PATH:/usr/local/go/bin
export GOPATH="$HOME/Tools/go"
export PATH="$PATH:$(go env GOBIN):$(go env GOPATH)/bin"
export PATH="$HOME/.local/bin:$PATH" # Local bin path

# Oh My Zsh directory
export ZSH="$HOME/.oh-my-zsh"

# Android
export ANDROID_SDK_ROOT=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
export PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin

export LM_STUDIO=$HOME/.lmstudio/bin
export PATH=$PATH:$LM_STUDIO

# cargo
. "$HOME/.cargo/env"

# volta
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

# SDK
#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# GPG
export GPG_TTY=$TTY
