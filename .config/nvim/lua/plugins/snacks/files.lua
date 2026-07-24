-- File and colorscheme picker entry points.

local M = {}

--- Register file-related Snacks picker mappings.
--- @param opts { ensure_unfixed_window: function, picker_resume: table }
function M.setup(opts)
  vim.keymap.set("n", "<leader>ff", function()
    opts.ensure_unfixed_window()
    if vim.v.count == 0 and opts.picker_resume.has("files") then
      opts.picker_resume.resume("files")
    else
      local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:~"):gsub("/+$", "")
      opts.picker_resume.open("files", Snacks.picker.files, { title = "Files (" .. cwd .. ")" })
    end
  end, { desc = "Find Files (Resume; [count]=new search)" })

  vim.keymap.set("n", "<leader>fF", function()
    opts.ensure_unfixed_window()
    local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:~"):gsub("/+$", "")
    opts.picker_resume.open("files", Snacks.picker.files, { title = "Files (" .. cwd .. ")" })
  end, { desc = "Find Files (Fresh Search)" })

  vim.keymap.set("n", "<leader>ft", function()
    opts.ensure_unfixed_window()
    Snacks.picker.colorschemes()
  end, { desc = "Select Colorscheme / Themes" })
end

return M
