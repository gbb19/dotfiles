-- lua/languages/python.lua
-- Language config for Python.
-- LSP server overrides live in lua/plugins/lsp/servers/pyright.lua

---@type LanguageConfig
return {
  lsp = {
    servers = { "basedpyright", "ruff" },
    mason   = { "basedpyright", "ruff" }, -- basedpyright and ruff will be installed via Mason
  },
  formatters = {
    -- Use ruff for formatting (black + isort behavior), falling back to black
    python = { "ruff_format", "black", stop_after_first = true },
  },
  treesitter = { "python" },
}
