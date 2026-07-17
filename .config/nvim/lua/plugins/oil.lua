-- Add oil.nvim using built-in vim.pack
vim.pack.add({
  "https://github.com/stevearc/oil.nvim",
})

-- Configure oil.nvim
local oil_ok, oil = pcall(require, "oil")
if oil_ok then
  oil.setup({
    -- Disable icons for a clean text-only layout matching user preferences
    columns = {},
    -- Skip confirming filesystem edits for faster saves
    skip_confirm_for_simple_edits = true,
    -- Configure keymaps inside oil buffer
    keymaps = {
      ["g?"] = "actions.show_help",
      ["<CR>"] = "actions.select",
      ["<C-s>"] = "actions.select_vsplit",
      ["<C-h>"] = "actions.select_split",
      ["<C-t>"] = "actions.select_tab",
      ["<C-p>"] = "actions.preview",
      ["<C-c>"] = function()
        require("oil").close()
        if _G.came_from_dashboard then
          _G.came_from_dashboard = false
          pcall(function() require("snacks").dashboard.open() end)
        end
      end,
      ["<C-l>"] = "actions.refresh",
      ["-"] = "actions.parent",
      ["_"] = "actions.open_cwd",
      ["`"] = "actions.cd",
      ["~"] = "actions.tcd",
      ["gs"] = "actions.change_sort",
      ["gx"] = "actions.open_external",
      ["g."] = "actions.toggle_hidden",
      ["g\\"] = "actions.toggle_trash",
    },
  })
end
