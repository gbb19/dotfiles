-- SQL and dbout buffer setup with buffer-local mappings.

local M = {}

---@class DadbodSqlBufferHandlers
---@field auto_bind fun(bufnr: integer)
---@field open_last_result function
---@field show_table_detail function

--- Configure an SQL buffer and its local mappings.
--- @param args table
--- @param handlers DadbodSqlBufferHandlers
function M.setup_sql(args, handlers)
  local bufnr = args and args.buf or vim.api.nvim_get_current_buf()
  vim.bo[bufnr].omnifunc = ""
  handlers.auto_bind(bufnr)

  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "<leader>rr", require("plugins.dadbod.query").run_sql_block, vim.tbl_extend("force", opts, { desc = "Run SQL Block" }))
  vim.keymap.set("v", "<leader>rr", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)

    local status = vim.b[bufnr].db_connection_status
    if status == "connecting" then
      require("core.utils").notify("db_connecting")
      return
    end
    if status == "failed" then
      require("core.utils").notify("db_connection_blocked")
      return
    end

    local db_url = vim.b[bufnr].db
    if not db_url or db_url == "" or (type(db_url) == "table" and not next(db_url)) then
      require("core.utils").notify("db_no_connection")
      return
    end

    local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
    local is_prod = url_str:match("prod") or url_str:match("production")
    local function execute()
      vim.cmd("vertical '<,'>DB")
    end
    if is_prod then
      vim.ui.input({
        prompt = "WARNING: Production DB! Confirm 'Run Visual Selection' by typing 'yes': ",
      }, function(input)
        if input and input:lower() == "yes" then execute() else require("core.utils").notify("db_operation_cancelled") end
      end)
    else
      execute()
    end
  end, vim.tbl_extend("force", opts, { desc = "Run Selection (DB)" }))

  vim.keymap.set({ "n", "v" }, "<leader>rc", require("plugins.dadbod.query").copy_block_as_csv, vim.tbl_extend("force", opts, { desc = "Copy Results as CSV" }))
  vim.keymap.set({ "n", "v" }, "<leader>rj", require("plugins.dadbod.query").copy_block_as_json, vim.tbl_extend("force", opts, { desc = "Copy Results as JSON" }))
  vim.keymap.set("n", "<leader>rp", function() require("plugins.dadbod.query").explain_query(false) end, vim.tbl_extend("force", opts, { desc = "Explain Performance (Clean)" }))
  vim.keymap.set("n", "<leader>rv", function() require("plugins.dadbod.query").explain_query(true) end, vim.tbl_extend("force", opts, { desc = "Explain Performance (Verbose)" }))
  vim.keymap.set("n", "<leader>ro", handlers.open_last_result, vim.tbl_extend("force", opts, { desc = "Open Last Result for this SQL file" }))
  vim.keymap.set("n", "<leader>rt", handlers.show_table_detail, vim.tbl_extend("force", opts, { desc = "Show Table Detail (Hover)" }))
  vim.keymap.set("n", "K", handlers.show_table_detail, vim.tbl_extend("force", opts, { desc = "Show Table Detail (Hover)" }))
  vim.keymap.set("n", "<leader>rs", require("plugins.dadbod.db").switch_connection, vim.tbl_extend("force", opts, { desc = "Switch Database Environment" }))
  vim.keymap.set("n", "<leader>rf", function() require("plugins.dadbod.picker").browse_tables({ view_only = false }) end, vim.tbl_extend("force", opts, { desc = "Find & Insert DB Table" }))
  vim.keymap.set("n", "<leader>ri", require("plugins.dadbod.picker").inspect_tables, vim.tbl_extend("force", opts, { desc = "Inspect DB Schema & Tables (View Only)" }))
  vim.keymap.set("n", "<leader>rh", require("plugins.dadbod.history").switch_result_history, vim.tbl_extend("force", opts, { desc = "Query Result History" }))
  vim.keymap.set("n", "<leader>rx", require("plugins.dadbod.history").clear_all_results, vim.tbl_extend("force", opts, { desc = "Clear Query History" }))
end

return M
