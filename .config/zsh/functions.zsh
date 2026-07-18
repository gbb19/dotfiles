# Zsh functions (widgets)

# zfghqcd_widget: Fuzzy find ghq repositories and cd into them
zfghqcd_widget() {
  local dir
  # Ensure ghq and fzf are installed and in PATH for this to work
  if command -v ghq &>/dev/null && command -v fzf &>/dev/null; then
    dir=$(ghq list --full-path | fzf)

    if [[ -n "$dir" ]]; then
      cd "$dir"

      # Re-run precmd functions to update prompt (e.g., git status)
      # This ensures the prompt updates correctly after changing directory
      local precmd
      for precmd in $precmd_functions; do
        $precmd
      done

      zle reset-prompt # Reset prompt to reflect new directory
    fi
  else
    echo "Error: 'ghq' or 'fzf' not found. Cannot use zfghqcd_widget." >&2
  fi
}

# zfcd_widget: Fuzzy find zoxide history and cd into them
zfcd_widget() {
  local dir
  # Ensure zoxide and fzf are installed for this to work
  if command -v zoxide &>/dev/null && command -v fzf &>/dev/null; then
    dir=$(zoxide query -l | fzf)

    if [[ -n "$dir" ]]; then
      cd "$dir"

      # Re-run precmd functions to update prompt
      local precmd
      for precmd in $precmd_functions; do
        $precmd
      done

      zle reset-prompt # Reset prompt to reflect new directory
    fi
  else
    echo "Error: 'zoxide' or 'fzf' not found. Cannot use zfcd_widget." >&2
  fi
}

bootwin() {
  win_id=$(efibootmgr | grep -i windows | head -n1 | sed 's/Boot\([0-9A-F]*\).*/\1/')

  if [[ -z "$win_id" ]]; then
    echo "Windows boot entry not found!"
    return 1
  fi

  echo "Booting Windows (Boot$win_id) on next reboot..."
  sudo efibootmgr --bootnext "$win_id" && sudo systemctl reboot
}

function gpg-reload() {
  echo "🔄 Restarting GPG Agent..."
  gpgconf --kill gpg-agent
  gpg-connect-agent reloadagent /bye
  echo "✅ GPG Agent successfully reset!"
}


infi() {
    if [[ -z "$1" ]]; then
        echo "Usage: infi <env>"
        return 1
    fi

    local ENV="$1"
    shift

    infisical secrets --env="$ENV" --plain --silent | \
    grep -v '^$' | \
    while IFS= read -r line; do
        if [[ "$line" == *=* ]]; then
            local key="${line%%=*}"
            local val="${line#*=}"
            eval "export $key=$(printf '%q' "$val")"
        fi
    done

    echo "Environment '$ENV' loaded."
}

git-gc() {
  git diff --cached --quiet && {
    echo "No staged changes"
    return 1
  }

  local tmp
  tmp=$(mktemp) || return 1

  agy \
    --model 'Gemini 3.5 Flash (Low)' \
    --print \
    "$(
      cat ~/.config/zsh/git.md
      printf '\n\nOnly analyze staged changes below:\n\n'
      git diff --cached
    )" > "$tmp"

  [[ -s "$tmp" ]] || {
    rm -f "$tmp"
    echo "Failed to generate commit message"
    return 1
  }
  echo "---- Commit Message ----"
  echo "$(cat "$tmp")"
  echo "------------------------"
  "${EDITOR:-vim}" "$tmp" || {
    rm -f "$tmp"
    echo "Commit aborted"
    return 1
  }

  git commit -F "$tmp"
  local rc=$?

  rm -f "$tmp"

  return $rc
}

git-st() {
  local lines
  lines=("${(@f)$(git status --short --no-renames | fzf -m --ansi)}")

  [[ ${#lines[@]} -eq 0 ]] && return 0

  local line index_status file
  for line in "${lines[@]}"; do
    index_status="${line[1]}"
    file="${line[4,-1]}"

    if [[ "$index_status" == " " || "$index_status" == "?" ]]; then
      git add -- "$file"
    else
      git restore --staged -- "$file"
    fi
  done
}

# Copy to host clipboard via OSC 52 (Tmux Supported)
# clip() {
#   local input=$(tr -d '\n\r ' | base64 -w 0)
#   if [ -n "$TMUX" ]; then
#     printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$input"
#   else
#     printf "\033]52;c;%s\a" "$input"
#   fi
# }
#

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

_get_dev_project_name() {
  local ws_dir=$(pwd)
  while [[ "$ws_dir" != "/" && ! -d "$ws_dir/.devcontainer" && ! -d "$ws_dir/.git" ]]; do
    ws_dir=$(dirname "$ws_dir")
  done
  if [[ "$ws_dir" == "/" ]]; then
    ws_dir=$(pwd)
  fi

  local container_id
  container_id=$(docker ps -a --filter "label=devcontainer.local_folder=$ws_dir" -q | head -n 1)

  if [[ -z "$container_id" ]]; then
    echo "⚠️ Error: No devcontainer found for workspace '$ws_dir'." >&2
    return 1
  fi

  local project_name
  project_name=$(docker inspect "$container_id" --format='{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)

  if [[ -z "$project_name" ]]; then
    project_name=$(basename "$ws_dir" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')
  fi
  echo "$project_name"
}

# Stop devcontainer services
dev-stop() {
  local project
  project=$(_get_dev_project_name) || return 1
  echo "⏸️ Stopping devcontainer project '$project'..."
  docker compose -p "$project" stop "$@"
}

# Tear down devcontainer services (down or down -v)
dev-down() {
  local project
  project=$(_get_dev_project_name) || return 1
  echo "⬇️ Shutting down devcontainer project '$project'..."
  docker compose -p "$project" down "$@"
}

# Start devcontainer services
dev-start() {
  local project
  project=$(_get_dev_project_name) || return 1
  echo "▶️ Starting devcontainer project '$project'..."
  docker compose -p "$project" start "$@"
}


# Load .env variables to environment
load-env() {
  local file="${1:-.env}"
  if [ -f "$file" ]; then
    export $(grep -v '^#' "$file" | xargs)
    echo "✅ Environment variables loaded from '$file'"
  else
    echo "❌ Error: File '$file' not found." >&2
    return 1
  fi
}

