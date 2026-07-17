-- Add gitsigns using built-in vim.pack
vim.pack.add({
  "https://github.com/lewis6991/gitsigns.nvim",
})

-- Safely configure gitsigns
local ok, gitsigns = pcall(require, "gitsigns")
if ok then
  gitsigns.setup({
    signs = {
      add          = { text = "┃" },
      change       = { text = "┃" },
      delete       = { text = "_" },
      topdelete    = { text = "‾" },
      changedelete = { text = "~" },
      untracked    = { text = "┆" },
    },
    signcolumn = true,
    numhl      = false,
    linehl     = false,
    word_diff  = false,
    watch_gitdir = {
      follow_files = true,
    },
    auto_attach = true,
    attach_to_untracked = false,
    current_line_blame = true,
    current_line_blame_opts = {
      virt_text = false, -- Disable inline virtual text in the code area
      delay = 0,         -- No delay: blame runs immediately on CursorHold (bounded by updatetime = 250ms)
    },
    current_line_blame_formatter = ' <author>, <author_time:%R>',
    sign_priority = 20,
    update_debounce = 100,
    max_file_length = 40000,
    preview_config = {
      border = "rounded",
      style = "minimal",
      relative = "cursor",
      row = 0,
      col = 1,
    },
  })

  -- Git keymaps (under <leader>g)
  vim.keymap.set("n", "<leader>gp", function() gitsigns.preview_hunk() end, { desc = "Preview Hunk" })
  vim.keymap.set("n", "<leader>gr", function() gitsigns.reset_hunk() end, { desc = "Reset Hunk" })
  vim.keymap.set("n", "<leader>gs", function() gitsigns.stage_hunk() end, { desc = "Stage Hunk" })
  vim.keymap.set("n", "<leader>gR", function() gitsigns.reset_buffer() end, { desc = "Reset Buffer" })
  vim.keymap.set("n", "<leader>gb", function() gitsigns.blame_line({ full = true }) end, { desc = "Blame Line" })
  vim.keymap.set("n", "<leader>gl", function() Snacks.picker.git_log_line() end, { desc = "Git Log (Current Line)" })
  vim.keymap.set("n", "<leader>gL", function() Snacks.picker.git_log_file() end, { desc = "Git Log (Current File)" })
  -- Toggle diff split and clean up native diff mode options automatically
  local function toggle_diff()
    if vim.wo.diff then
      vim.cmd("diffoff!")
      -- Close any remaining gitsigns index buffers in the current tabpage
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:find("^gitsigns://") then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    else
      gitsigns.diffthis()
    end
  end

  vim.keymap.set("n", "<leader>gd", toggle_diff, { desc = "Toggle Git Diff (split)" })
end
