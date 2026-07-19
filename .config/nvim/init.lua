-- Track startup start time (must be at the absolute top)
_G.startup_start_time = vim.uv.hrtime()

-- Load core configurations
require("core.options")
require("core.keymaps")
require("core.commands")
require("core.ui")
require("core.layout").setup()

-- Global safety wrapper for nvim_buf_call to prevent async plugin crashes
-- when plugins try to execute operations on closed/deleted buffers.
local original_buf_call = vim.api.nvim_buf_call
vim.api.nvim_buf_call = function(bufnr, cb)
  if vim.api.nvim_buf_is_valid(bufnr) then
    return original_buf_call(bufnr, cb)
  end
end
-- Mock nvim-web-devicons for plugins that require it
-- since we don't use file/section icons in our clean text-only config.
package.preload["nvim-web-devicons"] = function()
  return {
    get_icon = function() return "" end,
    get_icon_by_filetype = function() return "" end,
    get_icon_color = function() return "" end,
    get_icon_colors = function() return "", "" end,
    setup = function() end,
  }
end

-- Load plugins
require("plugins.theme")
require("plugins.snacks")
require("plugins.lualine")

-- Lazy load file-buffer tooling on first file buffer read/create
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("LazyFileTooling", { clear = true }),
  callback = function()
    require("plugins.fidget")
    require("plugins.conform")
    require("plugins.gitsigns")
    require("plugins.bufferline")
    require("plugins.lsp")
    require("plugins.treesitter")
    require("plugins.treesitter-context")
  end,
  once = true,
})

-- Lazy load insert-mode helpers only when editing starts
vim.api.nvim_create_autocmd("InsertEnter", {
  group = vim.api.nvim_create_augroup("LazyInsertTooling", { clear = true }),
  callback = function()
    require("plugins.autopairs")
  end,
  once = true,
})

-- Lazy load color highlighting only for frontend filetypes
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("LazyColorizer", { clear = true }),
  pattern = { "css", "scss", "sass", "html", "javascriptreact", "typescriptreact", "vue", "svelte", "less" },
  callback = function()
    require("plugins.colorizer")
  end,
  once = true,
})

-- Lazy load database tooling only for SQL files
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("LazyDadbod", { clear = true }),
  pattern = "sql",
  callback = function()
    require("plugins.dadbod")
  end,
  once = true,
})

-- Lazy load markdown rendering only for markdown files
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("LazyMarkdown", { clear = true }),
  pattern = "markdown",
  callback = function()
    require("plugins.render-markdown")
  end,
  once = true,
})
-- Lazy load which-key after UI starts up (simulates VeryLazy)
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("LazyWhichKey", { clear = true }),
  callback = function()
    vim.schedule(function()
      require("plugins.which-key")
    end)
  end,
  once = true,
})

-- Load session commands after the first screen is ready
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("LazySession", { clear = true }),
  callback = function()
    require("plugins.auto-session")
  end,
  once = true,
})
