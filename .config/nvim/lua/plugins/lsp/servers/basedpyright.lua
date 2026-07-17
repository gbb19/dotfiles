-- lua/plugins/lsp/servers/basedpyright.lua
-- Overrides for Basedpyright Python LSP server.

return {
  settings = {
    basedpyright = {
      analysis = {
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = "openFilesOnly", -- "workspace" can be slow on large projects
        typeCheckingMode = "basic",      -- "off", "basic", "standard", "strict"
        -- Enable inlay hints natively in Basedpyright
        inlayHints = {
          variableTypes = true,
          functionReturnTypes = true,
          callArgumentNames = true,
          pytestParameters = true,
        },
      },
    },
  },
}
