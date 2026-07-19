vim.pack.add({
  "https://github.com/nvim-treesitter/nvim-treesitter",
  "https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
})

local ts_ok, ts = pcall(require, "nvim-treesitter")
if ts_ok then
  local install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  ts.setup({
    install_dir = install_dir,
    textobjects = {
      select = {
        enable = true,
        lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
        keymaps = {
          -- Capture groups defined in textobjects.scm
          ["af"] = { query = "@function.outer", desc = "Around function outer" },
          ["if"] = { query = "@function.inner", desc = "Inside function inner" },
          ["ac"] = { query = "@class.outer", desc = "Around class outer" },
          ["ic"] = { query = "@class.inner", desc = "Inside class inner" },
          ["ai"] = { query = "@conditional.outer", desc = "Around conditional outer" },
          ["ii"] = { query = "@conditional.inner", desc = "Inside conditional inner" },
          ["al"] = { query = "@loop.outer", desc = "Around loop outer" },
          ["il"] = { query = "@loop.inner", desc = "Inside loop inner" },
          ["a,"] = { query = "@parameter.outer", desc = "Around parameter outer" },
          ["i,"] = { query = "@parameter.inner", desc = "Inside parameter inner" },
        },
      },
      move = {
        enable = true,
        set_jumps = true, -- whether to set jumps in the jumplist
        goto_next_start = {
          ["]m"] = { query = "@function.outer", desc = "Next function start" },
          ["]c"] = { query = "@class.outer", desc = "Next class start" },
        },
        goto_next_end = {
          ["]M"] = { query = "@function.outer", desc = "Next function end" },
          ["]C"] = { query = "@class.outer", desc = "Next class end" },
        },
        goto_previous_start = {
          ["[m"] = { query = "@function.outer", desc = "Previous function start" },
          ["[c"] = { query = "@class.outer", desc = "Previous class start" },
        },
        goto_previous_end = {
          ["[M"] = { query = "@function.outer", desc = "Previous function end" },
          ["[C"] = { query = "@class.outer", desc = "Previous class end" },
        },
      },
    },
  })

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
