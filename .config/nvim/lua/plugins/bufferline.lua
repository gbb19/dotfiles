-- lua/plugins/bufferline.lua
-- Add bufferline.nvim using built-in vim.pack (without web-devicons since icons are disabled)
vim.pack.add({ "https://github.com/akinsho/bufferline.nvim" })

-- Helper to safely switch buffers when current window is locked with winfixbuf
local function safe_buffer_switch(bufnr)
  if vim.wo.winfixbuf then
    local moved = false
    -- Move focus to a non-winfixbuf, non-floating window first
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if not vim.wo[win].winfixbuf and vim.api.nvim_win_get_config(win).relative == "" then
        vim.api.nvim_set_current_win(win)
        moved = true
        break
      end
    end
    if not moved then
      vim.wo.winfixbuf = false
    end
  end
  vim.cmd("buffer " .. bufnr)
end

local function safe_buffer_cycle(cmd)
  if vim.wo.winfixbuf then
    local moved = false
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if not vim.wo[win].winfixbuf and vim.api.nvim_win_get_config(win).relative == "" then
        vim.api.nvim_set_current_win(win)
        moved = true
        break
      end
    end
    if not moved then
      vim.wo.winfixbuf = false
    end
  end
  vim.cmd(cmd)
end

local ok, bufferline = pcall(require, "bufferline")
if ok then
  bufferline.setup({
    options = {
      mode = "buffers",
      style_preset = "minimal",
      always_show_bufferline = true,
      show_buffer_icons = false,       -- Disable icons to match our clean iconless theme
      show_buffer_close_icons = false, -- Disable tab close buttons
      show_close_icon = false,         -- Disable global close button
      show_tab_indicators = false,
      separator_style = "thin",        -- Simple thin vertical line as separator
      diagnostics = false,             -- Disable diagnostics on tabs to remove icons/numbers
      indicator = {
        style = "none",                -- Disable the highlighted color bar on the active tab
      },
      modified_icon = "*",             -- Use clean asterisk '*' instead of circle icons for unsaved files
      left_mouse_command = safe_buffer_switch,
      groups = {
        items = {
          require("bufferline.groups").builtin.pinned:with({ icon = "P " }),
        },
      },
      custom_filter = function(buf_number)
        if not buf_number or not vim.api.nvim_buf_is_valid(buf_number) then
          return false
        end
        -- Filter out dbout result buffers from bufferline entirely
        return vim.bo[buf_number].filetype ~= "dbout"
      end,

    },
  })
end

-- Buffer navigation keymaps
vim.keymap.set("n", "[b", function() safe_buffer_cycle("BufferLineCyclePrev") end, { desc = "Prev Buffer" })
vim.keymap.set("n", "]b", function() safe_buffer_cycle("BufferLineCycleNext") end, { desc = "Next Buffer" })

-- Buffer management keymaps (under <leader>b)
vim.keymap.set("n", "<leader>bd", function() Snacks.bufdelete() end, { desc = "Delete Buffer" })
vim.keymap.set("n", "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", { desc = "Close Other Buffers" })
vim.keymap.set("n", "<leader>bp", "<cmd>BufferLineTogglePin<cr>", { desc = "Toggle Pin Buffer" })
