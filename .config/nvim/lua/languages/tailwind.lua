-- lua/languages/tailwind.lua
-- Language config for Tailwind CSS.
-- Requires opt-in in project-local .nvim.lua via:
-- vim.g.project_lsp_servers = { "tailwindcss" }

---@type LanguageConfig
return {
  opt_in = true,
  lsp = {
    servers = { "tailwindcss" },
    mason   = { "tailwindcss" },
  },
  formatters = {},
  treesitter = { "css" },
}
