vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermClose" }, {
  group = vim.api.nvim_create_augroup("AutoReloadFiles", { clear = true }),
  callback = function()
    if vim.o.buftype == "" then vim.cmd("checktime") end
    if package.loaded["gitsigns"] then
      pcall(function() require("gitsigns").refresh() end)
    end
    if package.loaded["lualine"] then
      pcall(function() require("lualine").refresh() end)
    end
  end,
})
