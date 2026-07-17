-- lua/plugins/autopairs.lua
-- Add nvim-autopairs using built-in vim.pack
vim.pack.add({ "https://github.com/windwp/nvim-autopairs" })

local ok, autopairs = pcall(require, "nvim-autopairs")
if ok then
  autopairs.setup({
    check_ts = false,                  -- Disabled Treesitter integration as Treesitter is not loaded
    enable_check_bracket_line = true,  -- Don't add pairs if it already has a closing bracket on the line
  })
end
