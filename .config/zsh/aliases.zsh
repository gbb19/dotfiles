# Aliases
alias gq='ghq get -l -p'
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias hms="home-manager switch --flake ~/.config/home-manager#default --impure"
alias kps='keepassxc-cli show ~/KeePass/onez-password.kdbx'
alias tmux='tmux -u'


dev-exec() {
  if [ $# -eq 0 ]; then
    devcontainer exec --workspace-folder . zsh
  else
    devcontainer exec --workspace-folder . "$@"
  fi
}
alias dev-up='devcontainer up \
  --workspace-folder . \
  --dotfiles-repository https://github.com/gbb19/dotfiles.git \
  --dotfiles-install-command setup/setup_devcontainer.sh'
