-- Add fidget.nvim using built-in vim.pack
vim.pack.add({
  "https://github.com/j-hui/fidget.nvim",
})

local ok, fidget = pcall(require, "fidget")
if ok then
  fidget.setup({
    notification = {
      override_vim_notify = false, -- Do NOT override vim.notify (let snacks.notifier handle general notifications)
      window = {
        normal_hl = "Comment",     -- Dimmed text color matching comments
        winblend = 0,              -- Opaque background for clean readability
        border = "none",           -- Clean borderless layout
      },
    },
  })
end
