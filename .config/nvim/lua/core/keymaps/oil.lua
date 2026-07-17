-- Lazy load oil on :Oil command
vim.api.nvim_create_user_command("Oil", function(opts)
  require("plugins.oil")
  vim.api.nvim_del_user_command("Oil")
  _G.came_from_dashboard = (vim.bo.filetype == "snacks_dashboard")
  vim.cmd("Oil " .. opts.args)
end, { nargs = "*" })

-- Map minus (-) to open oil for the current file's directory (standard keymap)
vim.keymap.set("n", "-", function()
  require("plugins.oil")
  _G.came_from_dashboard = (vim.bo.filetype == "snacks_dashboard")
  vim.cmd("Oil")
end, { desc = "Open parent directory" })
