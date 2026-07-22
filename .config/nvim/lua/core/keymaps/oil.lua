local function safe_open_oil(args)
  require("plugins.oil")
  _G.came_from_dashboard = (vim.bo.filetype == "snacks_dashboard")

  local cur_win = vim.api.nvim_get_current_win()
  if vim.wo[cur_win].winfixbuf then
    local unfixed_win = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if not vim.wo[win].winfixbuf and vim.api.nvim_win_get_config(win).relative == "" then
        unfixed_win = win
        break
      end
    end
    if unfixed_win then
      vim.api.nvim_set_current_win(unfixed_win)
    else
      vim.wo[cur_win].winfixbuf = false
    end
  end

  if args and args ~= "" then
    vim.cmd("Oil " .. args)
  else
    vim.cmd("Oil")
  end
end

-- Lazy load oil on :Oil command
vim.api.nvim_create_user_command("Oil", function(opts)
  vim.api.nvim_del_user_command("Oil")
  safe_open_oil(opts.args)
end, { nargs = "*" })

-- Map minus (-) to open oil for the current file's directory (standard keymap)
vim.keymap.set("n", "-", function()
  safe_open_oil()
end, { desc = "Open parent directory" })
