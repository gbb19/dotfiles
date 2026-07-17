-- lua/plugins/colorizer.lua
-- Add nvim-colorizer.lua using built-in vim.pack (NvChad fork is highly maintained)
vim.pack.add({ "https://github.com/NvChad/nvim-colorizer.lua" })

local ok, colorizer = pcall(require, "colorizer")
if ok then
  colorizer.setup({
    filetypes = { "css", "scss", "sass", "html", "javascriptreact", "typescriptreact", "vue", "svelte", "less" },
    user_default_options = {
      RGB = true,          -- #RGB hex codes
      RRGGBB = true,       -- #RRGGBB hex codes
      names = false,       -- Disable color names like "Blue", "Red" to avoid false highlights on normal text
      RRGGBBAA = true,     -- #RRGGBBAA hex codes
      AARRGGBB = true,     -- 0xAARRGGBB hex codes
      rgb_fn = true,       -- CSS rgb() and rgba() functions
      hsl_fn = true,       -- CSS hsl() and hsla() functions
      css = true,          -- Enable all CSS features
      css_fn = true,       -- Enable all CSS functions
      mode = "background", -- Highlight the background of the color text
      tailwind = true,     -- Support tailwind color highlights
    },
  })
  -- Attach to the buffer that triggered lazy loading; future buffers are handled by colorizer.
  pcall(function() colorizer.attach_to_buffer(0) end)
end
