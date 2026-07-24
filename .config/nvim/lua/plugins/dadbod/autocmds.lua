-- Dadbod SQL/dbout lifecycle autocommand registration.

local M = {}
local state = require("plugins.dadbod.state")

local function handle_execute_pre(args)
  local file_path = args.match:match("^(.*)/DBExecutePre$")
  if not file_path then return end

  state.sql_source_by_output[file_path] = vim.api.nvim_get_current_buf()

  local ok, fidget_progress = pcall(require, "fidget.progress")
  if not ok then return end

  if state.query_handles[file_path] then
    pcall(function() state.query_handles[file_path]:finish() end)
  end

  local db_url = vim.b.db or ""
  local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  local label = url_str:match("[?&]service=([^&#]+)")
    or url_str:match("^[^?#]*/([^/?#]+)")
    or "db"

  state.query_handles[file_path] = fidget_progress.handle.create({
    title = string.format("DB [%s]", label),
    message = "Running...",
    lsp_client = { name = "Dadbod" },
  })
end

--- Register buffer setup and query execution lifecycle events.
--- @param opts { group: integer, setup_sql: function }
function M.setup(opts)
  vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufEnter", "BufWinEnter" }, {
    pattern = { "dbout", "*.dbout", "explain" },
    group = opts.group,
    callback = require("plugins.dadbod.buffers").setup_dbout,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "*dbout/DBExecutePre",
    group = opts.group,
    callback = handle_execute_pre,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "*dbout/DBExecutePost",
    group = opts.group,
    callback = require("plugins.dadbod.results").handle_execute_post,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    group = opts.group,
    callback = opts.setup_sql,
  })
end

return M
