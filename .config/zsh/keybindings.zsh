# Keybindings
bindkey '^D' autosuggest-accept # Ctrl+D to move forward a word (example, might conflict with default)

# Bind custom widgets to keys
zle -N zfghqcd_widget     # Register the widget
bindkey '^r' zfghqcd_widget # Ctrl+R to activate ghq fuzzy find

zle -N zfcd_widget        # Register the widget
bindkey '^f' zfcd_widget  # Ctrl+F to activate zoxide fuzzy find
