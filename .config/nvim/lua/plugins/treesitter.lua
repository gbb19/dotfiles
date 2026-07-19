vim.pack.add({
  "https://github.com/nvim-treesitter/nvim-treesitter",
  "https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
})

local ts_ok, ts = pcall(require, "nvim-treesitter")
if ts_ok then
  local install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  ts.setup({
    install_dir = install_dir,
  })

  local to_ok, to = pcall(require, "nvim-treesitter-textobjects")
  if to_ok then
    to.setup({
      select = {
        enable = true,
        lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
      },
      move = {
        enable = true,
        set_jumps = true, -- whether to set jumps in the jumplist
      },
    })

    -- Explicit Text Objects selection mappings (Visual 'x' and Operator-pending 'o' modes)
    local select_ts = require("nvim-treesitter-textobjects.select").select_textobject
    local ts_maps = {
      ["af"] = "@function.outer",
      ["if"] = "@function.inner",
      ["ac"] = "@class.outer",
      ["ic"] = "@class.inner",
      ["ai"] = "@conditional.outer",
      ["ii"] = "@conditional.inner",
      ["al"] = "@loop.outer",
      ["il"] = "@loop.inner",
      ["a,"] = "@parameter.outer",
      ["i,"] = "@parameter.inner",
    }
    for key, query in pairs(ts_maps) do
      vim.keymap.set({ "x", "o" }, key, function()
        select_ts(query, "textobjects")
      end, { desc = "Select " .. query })
    end

    -- Explicit Move mappings
    local move_ts = require("nvim-treesitter-textobjects.move")
    vim.keymap.set({ "n", "x", "o" }, "]m", function() move_ts.goto_next_start("@function.outer", "textobjects") end, { desc = "Next function start" })
    vim.keymap.set({ "n", "x", "o" }, "]c", function() move_ts.goto_next_start("@class.outer", "textobjects") end, { desc = "Next class start" })
    vim.keymap.set({ "n", "x", "o" }, "]M", function() move_ts.goto_next_end("@function.outer", "textobjects") end, { desc = "Next function end" })
    vim.keymap.set({ "n", "x", "o" }, "]C", function() move_ts.goto_next_end("@class.outer", "textobjects") end, { desc = "Next class end" })
    vim.keymap.set({ "n", "x", "o" }, "[m", function() move_ts.goto_previous_start("@function.outer", "textobjects") end, { desc = "Previous function start" })
    vim.keymap.set({ "n", "x", "o" }, "[c", function() move_ts.goto_previous_start("@class.outer", "textobjects") end, { desc = "Previous class start" })
    vim.keymap.set({ "n", "x", "o" }, "[M", function() move_ts.goto_previous_end("@function.outer", "textobjects") end, { desc = "Previous function end" })
    vim.keymap.set({ "n", "x", "o" }, "[C", function() move_ts.goto_previous_end("@class.outer", "textobjects") end, { desc = "Previous class end" })
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("TreesitterCore", { clear = true }),
    callback = function(args)
      local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
      if lang and pcall(vim.treesitter.start, args.buf, lang) then
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
end
