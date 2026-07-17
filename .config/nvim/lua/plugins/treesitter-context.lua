-- lua/plugins/treesitter-context.lua
-- Highlight/sticky code structure context at the top of the screen when scrolling.

-- Add nvim-treesitter-context using built-in vim.pack
vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter-context" })

local ok, context = pcall(require, "treesitter-context")
if ok then
  context.setup({
    enable = true,            -- Enable this plugin (Can be toggled by :TSContextToggle)
    max_lines = 4,            -- Keep the context header compact (max 4 lines)
    min_window_height = 15,   -- Don't show context in very small splits
    line_numbers = true,      -- Align line numbers in the context gutter with the buffer
    multiline_threshold = 5,  -- Maximum lines to display for a single code block
    trim_scope = "outer",     -- Discard outer lines first when max_lines is exceeded
    mode = "cursor",          -- Use cursor position (instead of topline) for context calculations
    separator = "─",          -- Thin divider line below context (styled via TreesitterContextSeparator)
    zindex = 20,              -- Maintain rendering stack height
  })

  -- Keymap to toggle context sticky headers on/off
  vim.keymap.set("n", "<leader>cx", "<cmd>TSContextToggle<CR>", {
    desc = "Toggle Treesitter Sticky Context",
  })
end
