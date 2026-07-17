-- lua/plugins/lsp/servers/gopls.lua
-- Server-specific config for gopls (Go language server).
-- Declared here only; enabled/registered via lua/languages/golang.lua

local M = {}

M.settings = {
  gopls = {
    analyses = {
      unusedparams = true,
      shadow       = true,
    },
    staticcheck = true,
    gofumpt     = true, -- use gofumpt-compatible formatting inside gopls
    hints = {
      assignVariableTypes    = true,
      compositeLiteralFields = true,
      compositeLiteralTypes  = true,
      constantValues         = true,
      functionTypeParameters = true,
      parameterNames         = true,
      rangeVariableTypes     = true,
    },
  },
}

return M
