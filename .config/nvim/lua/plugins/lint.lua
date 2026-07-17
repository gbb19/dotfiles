-- Add nvim-lint using built-in vim.pack
vim.pack.add({ "https://github.com/mfussenegger/nvim-lint" })

local ok, lint = pcall(require, "lint")
if ok then
  local project = require("core.project")

  -- Define global/default linters by filetype
  local default_linters = {
    -- sh = { "shellcheck" },
  }

  -- Automatically run linters on buffer write/read
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
    group = vim.api.nvim_create_augroup("DynamicLinting", { clear = true }),
    callback = function(args)
      local filetype = vim.bo[args.buf].filetype
      if filetype == "" then return end

      local defaults = default_linters[filetype] or {}
      local active_linters = project.get_linters(filetype, defaults)

      if #active_linters > 0 then
        lint.linters_by_ft[filetype] = active_linters
        lint.try_lint()
      else
        lint.linters_by_ft[filetype] = nil
      end
    end,
  })
end
