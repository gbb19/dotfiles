-- lua/languages/golang.lua
-- Language config for Go.
-- LSP server overrides live in lua/plugins/lsp/servers/gopls.lua

---@type LanguageConfig
return {
  lsp = {
    servers = { "gopls" },
    mason   = { "gopls" }, -- gopls is a Neovim-specific binary; Mason-managed is appropriate
  },
  formatters = {
    -- gofumpt is a superset of gofmt; run via system PATH (not Mason)
    go = { "gofumpt", stop_after_first = true },
  },
  treesitter = { "go", "gomod", "gowork", "gosum" },
}
