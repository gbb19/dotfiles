local M = {}
local project = require("core.project")

-- Restrict eslint LSP startup to projects with explicit eslint configuration files
M.root_dir = function(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  if not fname or fname == "" then return end

  -- If eslint is explicitly requested in project_lsp_servers, bypass config check and launch at project root
  if project.is_lsp_explicitly_enabled("eslint") then
    local root = vim.fs.root(fname, { ".git", "package.json" })
    if root then
      on_dir(root)
    end
    return
  end

  local eslint_configs = {
    "eslint.config.js",
    "eslint.config.mjs",
    "eslint.config.cjs",
    ".eslintrc",
    ".eslintrc.js",
    ".eslintrc.json",
    ".eslintrc.yaml",
    ".eslintrc.yml",
  }

  local root = vim.fs.find(eslint_configs, { upward = true, path = vim.fs.dirname(fname) })[1]
  if root then
    -- Return the directory containing the config file
    on_dir(vim.fn.fnamemodify(root, ":h"))
  end
end

return M
