-- lua/languages/json.lua
-- Language config for JSON and JSONC (JSON with Comments)
-- LSP server: jsonls (configured via mason)
-- Formatter: prettier / prettierd

---@type LanguageConfig
return {
  lsp = {
    servers = { "jsonls" },
    mason   = { "jsonls" },
  },
  formatters = {
    json  = { "prettierd", "prettier", stop_after_first = true },
    jsonc = { "prettierd", "prettier", stop_after_first = true },
  },
}
