# Aliases
alias gq='ghq get -l -p'
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias hms="home-manager switch --flake ~/.config/home-manager#nenz"
alias kps='keepassxc-cli show ~/KeePass/onez-password.kdbx'

alias dev-exec='devcontainer exec --workspace-folder . zsh'
alias dev-up='devcontainer up \
  --workspace-folder . \
  --dotfiles-repository https://github.com/gbb19/devcontainer-dotfile.git \
  --dotfiles-install-command devcontainer/install-dotfiles'
