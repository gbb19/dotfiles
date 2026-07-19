vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })

local ts_ok, ts = pcall(require, "nvim-treesitter")
if ts_ok then
  local install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  ts.setup({
    install_dir = install_dir,
  })

  local ensure_installed = {
    "typescript",
    "tsx",
    "javascript",
    "lua",
    "vim",
    "vimdoc",
    "markdown",
    "markdown_inline",
    "json",
    "graphql",
    "sql",
  }

  local config = require("nvim-treesitter.config")
  local installed = config.get_installed()

  local to_install = {}
  for _, lang in ipairs(ensure_installed) do
    if not vim.list_contains(installed, lang) then
      table.insert(to_install, lang)
    end
  end

  if #to_install > 0 then
    vim.schedule(function()
      pcall(vim.cmd, "TSInstall " .. table.concat(to_install, " "))
    end)
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("TreesitterCore", { clear = true }),
    callback = function(args)
      local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
      if lang and pcall(vim.treesitter.start, args.buf, lang) then
      end
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end,
  })
end
