-- lua/plugins/conform.lua
-- Load conform.nvim formatter package using built-in vim.pack
vim.pack.add({ "https://github.com/stevearc/conform.nvim" })

-- formatters_by_ft is aggregated from all language modules in lua/languages/
local languages = require("languages")

local ok, conform = pcall(require, "conform")
if ok then
  conform.setup({
    formatters_by_ft = languages.formatters,
    -- Automatically format when writing the buffer (saving the file)
    format_on_save = {
      timeout_ms = 2000,
      lsp_format = "fallback",
    },
    formatters = {
      sql_formatter = {
        args = function(self, ctx)
          local db_url = vim.b[ctx.buf].db or vim.g.db
          if type(db_url) == "table" then
            db_url = db_url.url or db_url[1]
          end
          local adapter = db_url and require("plugins.dadbod.shared").get_adapter(db_url) or "sql"
          local dialect = "sql"
          if adapter == "postgres" then dialect = "postgresql"
          elseif adapter == "mysql" then dialect = "mysql"
          elseif adapter == "sqlite" then dialect = "sqlite"
          end

          local config = {
            language = dialect,
            keywordCase = "upper",
            dataTypeCase = "upper",
            functionCase = "upper",
            tabWidth = 2,
            linesBetweenQueries = 2,
          }

          return { "-c", vim.json.encode(config) }
        end,
      },
    },
  })

  -- Manual formatting keymap (under <leader>c)
  vim.keymap.set("n", "<leader>cf", function()
    conform.format({ async = true, lsp_format = "fallback" })
  end, { desc = "Format Buffer" })
end

-- Hook conform formatting events to show progress in fidget
local conform_handles = {}

vim.api.nvim_create_autocmd("User", {
  pattern = "ConformFormatPre",
  callback = function(args)
    local bufnr = args.buf
    local ok, progress = pcall(require, "fidget.progress")
    if ok then
      if conform_handles[bufnr] then
        pcall(function() conform_handles[bufnr]:finish() end)
      end
      conform_handles[bufnr] = progress.handle.create({
        title = "Conform",
        message = "Formatting buffer...",
        lsp_client = { name = "conform" },
      })
    end
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "ConformFormatPost",
  callback = function(args)
    local bufnr = args.buf
    local handle = conform_handles[bufnr]
    if handle then
      pcall(function() handle:finish() end)
      conform_handles[bufnr] = nil
    end
  end,
})
