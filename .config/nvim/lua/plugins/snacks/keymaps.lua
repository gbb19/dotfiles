-- Snacks keymap orchestration by domain.

local M = {}

--- Register all configured Snacks keymap domains.
--- @param opts { ensure_unfixed_window: function, picker_resume: table }
function M.setup(opts)
  require("plugins.snacks.files").setup({
    ensure_unfixed_window = opts.ensure_unfixed_window,
    picker_resume = opts.picker_resume,
  })
  require("plugins.snacks.grep").setup({
    ensure_unfixed_window = opts.ensure_unfixed_window,
    picker_resume = opts.picker_resume,
  })
  require("plugins.snacks.git").setup({
    ensure_unfixed_window = opts.ensure_unfixed_window,
  })
  require("plugins.snacks.misc").setup(opts.ensure_unfixed_window)
end

return M
