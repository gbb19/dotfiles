-- lua/languages/sql.lua
-- Language config for SQL.
-- Integrates with conform.nvim for formatting.

---@type LanguageConfig
return {
  lsp = {
    servers = {}, -- Handled entirely by vim-dadbod-completion (no heavy LSP needed)
    mason   = { "postgres_lsp" },
  },
  formatters = {
    sql = { "sql_formatter" }, -- Installed via npm project-locally or system-wide
  },
}
