#!/usr/bin/env sh
set -eu

nvim --headless -n -i NONE \
  "+luafile tests/characterization.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/snacks_resume.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/dadbod_state.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/dadbod_dependencies.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/dadbod_sql.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/dadbod_runtime.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/dadbod_immediate_load.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/lsp_config.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/plugin_entrypoints.lua" \
  +qa

nvim --headless -n -i NONE \
  "+luafile tests/module_cycles.lua" \
  +qa
