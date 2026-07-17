-- Disable default Neovim mode indicator in command line (since it is shown in statusline)
vim.opt.showmode = false

-- Use global statusline at the bottom of the screen instead of per-window statuslines
vim.opt.laststatus = 3

-- Configure diagnostic display options (Clean Virtual Text / Native Error Lens)
vim.diagnostic.config({
  virtual_text = {
    spacing = 4,
    source = "if_many", -- Show source (e.g. eslint, vtsls) if multiple exist
    prefix = "",        -- No icon prefix as requested (rely on line color / sign instead)
  },
  float = {
    border = "rounded",
    source = "always",
  },
  jump = {
    on_jump = function(diagnostic)
      vim.diagnostic.open_float({ diagnostic = diagnostic })
    end,
  },
  -- Configure modern Neovim 0.10+ diagnostic signs (replaces legacy E/W indicator)
  signs = false, -- Disable diagnostic signs in the sign column entirely (keep for Git signs only)
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})

-- Override default virtual text handler to show ONLY ONE diagnostic per line (the most severe)
-- This solves the issue of multiple LSPs (like TS and ESLint) showing overlapping/duplicate text.
local orig_virt_text_handler = vim.diagnostic.handlers.virtual_text

vim.diagnostic.handlers.virtual_text = {
  show = function(ns, bufnr, diagnostics, opts)
    local filtered_diagnostics = {}
    local line_diagnostics = {}

    for _, d in ipairs(diagnostics) do
      local line = d.lnum
      local current = line_diagnostics[line]

      -- Keep only the highest severity diagnostic for each line
      -- (severity levels: ERROR = 1, WARN = 2, INFO = 3, HINT = 4)
      local d_severity = d.severity or 1
      local current_severity = current and (current.severity or 1) or 99
      if not current or d_severity < current_severity then
        line_diagnostics[line] = d
      end
    end

    -- Flatten the map back to an array
    for _, d in pairs(line_diagnostics) do
      table.insert(filtered_diagnostics, d)
    end

    orig_virt_text_handler.show(ns, bufnr, filtered_diagnostics, opts)
  end,
  hide = orig_virt_text_handler.hide,
}

-- Silence default ugly file-written messages
vim.opt.shortmess:append("W")

