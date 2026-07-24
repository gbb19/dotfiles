#!/usr/bin/env sh
set -eu

nvim --headless -n -i NONE \
  "+luafile tests/characterization.lua" \
  +qa
