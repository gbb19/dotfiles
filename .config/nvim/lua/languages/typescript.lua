local project = require("core.project")

-- Helper to dynamically select formatter based on configuration files in workspace
local function get_formatter(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return { "prettierd", "prettier", stop_after_first = true }
  end

  local function default_check()
    -- Detect Oxc/Oxfmt configs upward from the current buffer's file location
    local root = vim.fs.find({ ".oxfmtrc.json", ".oxlintrc.json", "oxlint.json" }, {
      upward = true,
      path = vim.fs.dirname(bufname),
    })[1]

    if root then
      return { "oxfmt" }
    end

    return { "prettierd", "prettier", stop_after_first = true }
  end

  return project.get_formatter("typescript", default_check)
end

---@type LanguageConfig
return {
  lsp = {
    servers = { "vtsls", "eslint", "oxlint", "emmet_ls" },
    -- eslint: managed by Mason (Neovim-specific tooling)
    -- Prettier/prettierd: intentionally excluded — use project-local node_modules/.bin instead
    mason = { "vtsls", "eslint", "oxlint", "emmet_ls" },
  },
  dap = {
    mason = { "js-debug-adapter" },
  },
  formatters = {
    javascript      = get_formatter,
    typescript      = get_formatter,
    javascriptreact = get_formatter,
    typescriptreact = get_formatter,
    css             = { "prettierd", "prettier", stop_after_first = true },
    html            = { "prettierd", "prettier", stop_after_first = true },
    json            = { "prettierd", "prettier", stop_after_first = true },
    markdown        = { "prettierd", "prettier", stop_after_first = true },
  },
  treesitter = { "typescript", "tsx", "javascript" },
}
