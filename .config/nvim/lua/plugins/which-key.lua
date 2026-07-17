-- Add which-key.nvim using built-in vim.pack
vim.pack.add({ "https://github.com/folke/which-key.nvim" })

-- Configure which-key.nvim
local ok, wk = pcall(require, "which-key")
if ok then
  wk.setup({
    preset = "classic", -- Classic look and feel
    win = {
      border = "rounded",
      padding = { 1, 2 },
    },
  })

  -- Register keymap groups
  wk.add({
    { "<leader>b",  group = "Buffers" },
    { "<leader>c",  group = "Code/LSP/Format" },
    { "<leader>d",  group = "Debug" },
    { "<leader>dv", group = "View" },
    { "<leader>f",  group = "Find/Search" },
    { "<leader>g",  group = "Git" },
    { "<leader>go", group = "Git Diff Base" },
    { "<leader>r",  group = "Database" },
    { "<leader>s",  group = "Session" },
    { "<leader>t",  group = "Task Runner" },
  })
end
