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
      cat ~/Repos/github.com/gbb19/dotfiles/AI/git/git.md
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
