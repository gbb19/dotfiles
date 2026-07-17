-- lua/languages/lua.lua
-- Language config for Lua (Neovim configuration development).
-- LSP server overrides live in lua/plugins/lsp/servers/lua_ls.lua

---@type LanguageConfig
return {
  lsp = {
    servers = { "lua_ls" },
    mason   = { "lua_ls" },
  },
  formatters = {
    lua = { "stylua" },
  },
}
