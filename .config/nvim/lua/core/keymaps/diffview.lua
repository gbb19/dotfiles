local function actions()
  require("plugins.diffview")
  return require("plugins.diffview.actions")
end

vim.api.nvim_create_user_command("DiffviewOpen", function(opts)
  vim.api.nvim_del_user_command("DiffviewOpen")
  actions().open_command("DiffviewOpen " .. opts.args)
end, { nargs = "*" })

vim.api.nvim_create_user_command("DiffviewFileHistory", function(opts)
  vim.api.nvim_del_user_command("DiffviewFileHistory")
  actions().open_command("DiffviewFileHistory " .. opts.args)
end, { nargs = "*" })

vim.api.nvim_create_user_command("DiffviewResetBase", function()
  actions().reset_base()
end, {})

vim.keymap.set("n", "<leader>gD", function()
  actions().open_command("DiffviewOpen")
end, { desc = "Open Git Diffview" })

vim.keymap.set("n", "<leader>gx", function()
  actions().close()
end, { desc = "Close Git Diffview" })

vim.keymap.set("n", "<leader>gh", function()
  actions().open_command("DiffviewFileHistory --first-parent %")
end, { desc = "List File History (current file, clean)" })

vim.keymap.set("n", "<leader>gH", function()
  actions().open_command("DiffviewFileHistory --first-parent")
end, { desc = "List Project History (clean)" })

vim.keymap.set("n", "<leader>gov", function()
  actions().open_branch_diff()
end, { desc = "View PR / Branch Diff (Diffview)" })

vim.keymap.set("n", "<leader>goh", function()
  actions().open_branch_history()
end, { desc = "View File PR History" })

vim.keymap.set("n", "<leader>gm", function()
  actions().open_line_feature_diff()
end, { desc = "View Merge/Feature Diff for Current Line" })
