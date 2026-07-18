# Aliases
alias gq='ghq get -l -p'
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'
alias hms="home-manager switch --flake ~/.config/home-manager#default --impure"
alias kps='keepassxc-cli show ~/KeePass/onez-password.kdbx'
alias tmux='tmux -u'


dev-exec() {
  # Find workspace root (parent folder containing .devcontainer or .git)
  local ws_dir=$(pwd)
  while [[ "$ws_dir" != "/" && ! -d "$ws_dir/.devcontainer" && ! -d "$ws_dir/.git" ]]; do
    ws_dir=$(dirname "$ws_dir")
  done
  if [[ "$ws_dir" == "/" ]]; then
    ws_dir=$(pwd)
  fi

  local container_id
  container_id=$(docker ps --filter "label=devcontainer.local_folder=$ws_dir" -q | head -n 1)

  if [[ -z "$container_id" ]]; then
    echo "Error: No running container found for workspace '$ws_dir'." >&2
    return 1
  fi

  # 1. Dynamically extract the remoteUser from the devcontainer metadata label
  local user_name
  user_name=$(docker inspect "$container_id" --format='{{index .Config.Labels "devcontainer.metadata"}}' 2>/dev/null | python3 -c "import sys, json; print(next((x.get(\"remoteUser\") for x in json.loads(sys.stdin.read()) if \"remoteUser\" in x), \"\"))" 2>/dev/null | xargs)

  local exec_args=()
  if [[ -n "$user_name" ]]; then
    exec_args+=("-u" "$user_name")
  fi

  # 2. Ask the container to find where Zsh is (resolving $HOME dynamically inside the container for the detected user)
  local shell_cmd="bash"
  local detected_shell
  detected_shell=$(docker exec "${exec_args[@]}" "$container_id" sh -c '
    if [ -f "$HOME/.local/bin/zsh" ]; then
      echo "$HOME/.local/bin/zsh"
    elif [ -f "/usr/bin/zsh" ]; then
      echo "/usr/bin/zsh"
    elif [ -f "/bin/zsh" ]; then
      echo "/bin/zsh"
    elif command -v zsh >/dev/null 2>&1; then
      echo "zsh"
    fi
  ' 2>/dev/null)

  if [[ -n "$detected_shell" ]]; then
    shell_cmd=$(echo "$detected_shell" | tr -d '\r' | xargs)
  fi

  # 3. Run shell or command inside the container using native docker exec -it
  if [ $# -eq 0 ]; then
    # Run shell as a login shell (-l) with $HOME/.local/bin prepended to PATH
    docker exec -it "${exec_args[@]}" "$container_id" sh -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; exec \"$shell_cmd\" -l"
  else
    # Run command with $HOME/.local/bin prepended to PATH
    docker exec -it "${exec_args[@]}" "$container_id" sh -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; exec \"\$@\"" -- "$@"
  fi
}
alias dev-up='devcontainer up \
  --workspace-folder . \
  --dotfiles-repository https://github.com/gbb19/dotfiles.git \
  --dotfiles-install-command setup/setup_devcontainer.sh'
