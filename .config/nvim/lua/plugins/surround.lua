-- lua/plugins/surround.lua
-- Add nvim-surround using built-in vim.pack
vim.pack.add({ "https://github.com/kylechui/nvim-surround" })

local ok, surround = pcall(require, "nvim-surround")
if ok then
  surround.setup({
    -- Keymaps are defined automatically by default:
    -- ys{motion}{char} : Add surround (e.g. ysiw" -> surround inner word with ")
    -- ds{char}         : Delete surround (e.g. ds" -> delete surrounding ")
    -- cs{target}{new}   : Change surround (e.g. cs"' -> change " to ')
  })
end
