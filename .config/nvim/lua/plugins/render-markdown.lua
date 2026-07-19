-- lua/plugins/render-markdown.lua
-- Beautify markdown documents directly inside the Neovim buffer.

-- Add render-markdown.nvim using built-in vim.pack
vim.pack.add({ "https://github.com/MeanderingProgrammer/render-markdown.nvim" })

local ok, render_markdown = pcall(require, "render-markdown")
if ok then
  render_markdown.setup({
    heading = {
      enabled = true,
      sign = true,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
    },
    bullet = {
      enabled = true,
      icons = { "●", "○", "◆", "◇" },
    },
    checkbox = {
      enabled = true,
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰄵 " },
    },
    pipe_table = {
      enabled = true,
      style = "full",
    },
    code = {
      enabled = true,
      style = "full",
      left_pad = 0,
      right_pad = 0,
      width = "block",
      language = false,
    },
  })

  -- Immediately render the current buffer if we just lazy loaded the plugin
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.bo[current_buf].filetype == "markdown" then
    local winid = vim.fn.bufwinid(current_buf)
    pcall(require("render-markdown").render, {
      buf = current_buf,
      win = winid ~= -1 and winid or nil
    })
  end

  -- Toggle keymap to turn on/off rendering easily (buffer-local to markdown files to avoid conflicts)
  local function set_keymap(bufnr)
    vim.keymap.set("n", "<leader>cm", "<cmd>RenderMarkdown toggle<CR>", {
      desc = "Toggle Markdown Render",
      silent = true,
      buffer = bufnr,
    })
  end

  set_keymap(vim.api.nvim_get_current_buf())

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("RenderMarkdownKeymap", { clear = true }),
    pattern = "markdown",
    callback = function(args)
      set_keymap(args.buf)
    end,
  })
end
