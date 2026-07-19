-- lua/languages/init.lua
-- Central language registry — auto-discovers all language modules in this directory.
-- To add a new language: create lua/languages/{lang}.lua with the standard contract.
-- No other files need to be modified.

---@class LanguageConfig
---@field lsp? { servers: string[], mason?: string[] }
---@field formatters? table<string, any>
---@field treesitter? string[]

---@class LanguageRegistry
---@field lsp_servers string[]   All LSP server names to enable
---@field mason_servers string[] Servers for Mason to auto-install
---@field dap_servers string[]   DAP servers to auto-install
---@field formatters table<string, any> conform-compatible formatters_by_ft
---@field treesitter_parsers string[] All Treesitter parser names to install

local M = {
  lsp_servers        = {},
  mason_servers      = {},
  dap_servers        = {},
  formatters         = {},
  treesitter_parsers = {},
}

local utils = require("core.utils")
local lang_dir = vim.fn.stdpath("config") .. "/lua/languages"
local files = vim.fn.glob(lang_dir .. "/*.lua", false, true)

for _, filepath in ipairs(files) do
  local name = vim.fn.fnamemodify(filepath, ":t:r")
  if name ~= "init" then
    ---@type boolean, LanguageConfig|string
    local ok, config = pcall(require, "languages." .. name)
    if not ok then
      utils.notify("language_load_failed", name .. ": " .. tostring(config))
    elseif type(config) == "table" then
      if config.lsp then
        local is_opt_in = config.opt_in == true
        local project_servers = vim.g.project_lsp_servers or {}
        local should_enable = not is_opt_in

        if is_opt_in then
          for _, s in ipairs(config.lsp.servers or {}) do
            if vim.tbl_contains(project_servers, s) then
              should_enable = true
              break
            end
          end
        end

        if should_enable then
          vim.list_extend(M.lsp_servers, config.lsp.servers or {})
        end
        vim.list_extend(M.mason_servers, config.lsp.mason or {})
      end
      if config.dap then
        vim.list_extend(M.dap_servers, config.dap.mason or {})
      end
      if config.formatters then
        M.formatters = vim.tbl_extend("force", M.formatters, config.formatters)
      end
      if config.treesitter then
        vim.list_extend(M.treesitter_parsers, config.treesitter)
      end
    else
      utils.notify("language_invalid_module", name)
    end
  end
end

return M
