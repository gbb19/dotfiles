-- Clear search highlights on pressing Esc in normal mode
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- :Q / :Qa — quit all tabs at once (avoids cycling through tabs opened by gf etc.)
vim.api.nvim_create_user_command("Q", "qa", { bang = true, desc = "Quit all" })
vim.api.nvim_create_user_command("Qa", "qa", { bang = true, desc = "Quit all" })

-- Easy window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Stay in visual mode after indenting
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and keep selection" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and keep selection" })

-- Move lines in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move visual block down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move visual block up" })

-- Disable Neovim 0.11+ default LSP mappings to prevent input latency and default split windows
pcall(vim.keymap.del, "n", "grr")
pcall(vim.keymap.del, "n", "gri")
pcall(vim.keymap.del, "n", "grn")
pcall(vim.keymap.del, "n", "gra")
pcall(vim.keymap.del, "v", "gra")
pcall(vim.keymap.del, "n", "grt")
pcall(vim.keymap.del, "n", "grx")
pcall(vim.keymap.del, "n", "gO")
pcall(vim.keymap.del, "i", "<C-S>")
pcall(vim.keymap.del, "i", "<C-s>")

-- Generic buffer/file renaming keymap
vim.keymap.set("n", "<leader>br", function() require("core.utils").rename_current_buffer() end, { desc = "Rename Buffer/File" })
vim.keymap.set("n", "<leader>yp", function()
  require("core.utils").copy_relative_file_path()
end, { desc = "Copy Relative File Path" })

-- Plugin-specific keymaps (split by domain)
require("core.keymaps.overseer")
require("core.keymaps.diffview")
require("core.keymaps.oil")
require("core.keymaps.dap")
