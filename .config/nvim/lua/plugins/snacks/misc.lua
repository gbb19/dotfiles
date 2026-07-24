-- Small utility picker mappings.

local M = {}

function M.setup(ensure_unfixed_window)
  vim.keymap.set("n", "<leader>fr", function()
    ensure_unfixed_window()
    Snacks.picker.recent()
  end, { desc = "Recent Files" })
  vim.keymap.set("n", "<leader>fh", function()
    ensure_unfixed_window()
    Snacks.picker.help()
  end, { desc = "Help Tags" })
  vim.keymap.set("n", "<leader>cd", function()
    ensure_unfixed_window()
    Snacks.picker.diagnostics({ filter = { bufnr = 0 } })
  end, { desc = "Search Diagnostics (Current File)" })
  vim.keymap.set("n", "<leader>cD", function()
    ensure_unfixed_window()
    Snacks.picker.diagnostics()
  end, { desc = "Search Diagnostics (Workspace)" })
end

return M
