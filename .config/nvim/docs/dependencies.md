# External dependencies

These tools are optional for opening and editing files, but are required by the
features that invoke them:

- Git: repository status, history, Diffview, and merge workflows.
- ripgrep (`rg`): Snacks grep/search.
- fd: fast file discovery in Snacks pickers.
- Database CLIs: Dadbod connections and query execution (for example `psql`,
  `mysql`, or `sqlite3`, depending on the configured connection).
- tmux: optional terminal/window integration.
- OSC 52 terminal support: clipboard integration when Neovim runs remotely.

Missing optional tools should only disable the related workflow; core editing
and navigation remain available.
