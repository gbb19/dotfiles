-- lua/core/layout.lua
-- Central layout and window size manager
local M = {}

-- Checks if a window's buffer is a sidebar or utility buffer
function M.is_sidebar(bufnr)
  local buftype = vim.bo[bufnr].buftype
  local filetype = vim.bo[bufnr].filetype

  return buftype ~= ""
    or filetype == "neo-tree"
    or filetype == "NvimTree"
    or filetype:match("^dapui_")
    or filetype == "dap-repl"
    or filetype == "trouble"
    or filetype == "qf"
    or filetype == "help"
end

-- Safely jumps the cursor to the first normal (non-sidebar) window in the tabpage
function M.jump_to_normal_window()
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)

  if not M.is_sidebar(current_buf) then
    return
  end

  -- Find a normal window in the current tabpage
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if not M.is_sidebar(buf) then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end
end

-- Rules for resizing specific plugin windows directly
local layout_rules = {
  ["OverseerList"] = { type = "height", size = 14 },
  ["neo-tree"]     = { type = "width", size = 30 },
  ["qf"]           = { type = "height", size = 8 },
}

-- Checks if DAP UI is open and resizes it using its internal reset engine,
-- and resizes other registered windows using direct rules.
function M.resize_layout()
  vim.defer_fn(function()
    -- 1. Handle DAP UI resetting if open
    local ok, dapui = pcall(require, "dapui")
    if ok then
      local is_dap_open = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.bo[buf].filetype
          if ft:match("^dapui_") or ft == "dap-repl" then
            is_dap_open = true
            break
          end
        end
      end

      if is_dap_open then
        pcall(dapui.open, { reset = true })
      end
    end

    -- 2. Handle other utility windows using layout rules
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype
        local rule = layout_rules[ft]
        if rule then
          if rule.type == "height" then
            pcall(vim.api.nvim_win_set_height, win, rule.size)
          elseif rule.type == "width" then
            pcall(vim.api.nvim_win_set_width, win, rule.size)
          end
        end
      end
    end
  end, 100)
end

-- Setup global autocommands to listen to window updates
function M.setup()
  local group = vim.api.nvim_create_augroup("LayoutManager", { clear = true })
  vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
    group = group,
    pattern = "*",
    callback = M.resize_layout,
  })
end

return M
