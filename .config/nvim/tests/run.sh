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
