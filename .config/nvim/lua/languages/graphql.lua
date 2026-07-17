-- lua/languages/graphql.lua
-- Language config for GraphQL.
-- Requires opt-in in project-local .nvim.lua via:
-- vim.g.project_lsp_servers = { "graphql" }
-- LSP server overrides live in lua/plugins/lsp/servers/graphql.lua

---@type LanguageConfig
return {
  opt_in = true,
  lsp = {
    servers = { "graphql" },
    mason   = { "graphql" },
  },
}
