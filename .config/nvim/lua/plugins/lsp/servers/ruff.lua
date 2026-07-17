-- lua/plugins/lsp/servers/ruff.lua
-- Overrides for Ruff LSP server.

return {
  on_attach = function(client, bufnr)
    -- Disable hover provider in favor of basedpyright
    client.server_capabilities.hoverProvider = false
  end,
}
