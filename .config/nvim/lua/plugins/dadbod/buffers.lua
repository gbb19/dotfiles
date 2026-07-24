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

local function map_result_history(bufnr, direction)
  local current_path = vim.api.nvim_buf_get_name(0)
  local history = require("plugins.dadbod.history")
  local result_files = history.get_result_files(current_path)
  if #result_files == 0 then return end

  local current_idx
  for index, item in ipairs(result_files) do
    if item.path == current_path then
      current_idx = index
      break
    end
  end
  if not current_idx then return end

  local target_idx = current_idx + direction
  if target_idx == 0 then target_idx = #result_files end
  if target_idx > #result_files then target_idx = 1 end

  local target = result_files[target_idx]
  local target_buf = vim.fn.bufnr(target.path)
  if target_buf == -1 then
    target_buf = vim.fn.bufadd(target.path)
    vim.fn.bufload(target_buf)
  end

  local current_sql = vim.b[bufnr].sql_source_path
  if current_sql then
    vim.b[target_buf].sql_source_path = current_sql
  end

  require("plugins.dadbod.results").set_win_buf_safely(0, target_buf)
  history.show_history_popup(result_files, target.path)
end

--- Configure a dbout result buffer and its local mappings.
--- @param args table
function M.setup_dbout(args)
  local bufnr = args and args.buf or vim.api.nvim_get_current_buf()
  require("plugins.dadbod.format").truncate_dbout_buffer(bufnr)
  vim.cmd("setlocal nowrap")

  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    local half_width = math.floor(vim.o.columns * 0.5)
    pcall(vim.api.nvim_win_set_width, wins[1], half_width)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winfixbuf = true
      end
    end
  end

  local opts = { buffer = bufnr, silent = true }
  local cell = require("plugins.dadbod.cell")
  local history = require("plugins.dadbod.history")

  vim.keymap.set("n", "gz", cell.show_cell_detail, vim.tbl_extend("force", opts, { desc = "Inspect full cell value" }))
  vim.keymap.set("n", "K", cell.show_cell_detail, vim.tbl_extend("force", opts, { desc = "Inspect full cell value (Hover)" }))
  vim.keymap.set("n", "gW", function() require("plugins.dadbod.format").toggle_dbout_column_width(bufnr) end, vim.tbl_extend("force", opts, { desc = "Toggle fixed column width" }))
  vim.keymap.set("n", "<Tab>", function() require("plugins.dadbod.format").jump_column("next") end, vim.tbl_extend("force", opts, { desc = "Next Column" }))
  vim.keymap.set("n", "<S-Tab>", function() require("plugins.dadbod.format").jump_column("prev") end, vim.tbl_extend("force", opts, { desc = "Previous Column" }))
  vim.keymap.set("n", "gh", "1G", vim.tbl_extend("force", opts, { desc = "Jump to Header" }))
  vim.keymap.set({ "o", "x" }, "ic", function() cell.select_cell(false) end, vim.tbl_extend("force", opts, { desc = "inner cell" }))
  vim.keymap.set({ "o", "x" }, "ac", function() cell.select_cell(true) end, vim.tbl_extend("force", opts, { desc = "around cell" }))
  vim.keymap.set("n", "yic", function() cell.yank_cell(false) end, vim.tbl_extend("force", opts, { desc = "Yank full inner cell" }))
  vim.keymap.set("n", "yac", function() cell.yank_cell(true) end, vim.tbl_extend("force", opts, { desc = "Yank full around cell" }))
  vim.keymap.set({ "n", "x" }, "yin", cell.yank_in_clause, vim.tbl_extend("force", opts, { desc = "Yank Column as SQL IN Condition" }))
  vim.keymap.set({ "n", "x" }, "<leader>yi", cell.yank_in_clause, vim.tbl_extend("force", opts, { desc = "Yank Column as SQL IN Condition" }))
  vim.keymap.set({ "n", "x" }, "yis", cell.yank_insert_statements, vim.tbl_extend("force", opts, { desc = "Yank Rows as SQL INSERT Statement" }))
  vim.keymap.set({ "n", "x" }, "<leader>ys", cell.yank_insert_statements, vim.tbl_extend("force", opts, { desc = "Yank Rows as SQL INSERT Statement" }))
  vim.keymap.set({ "n", "x" }, "<leader>yc", cell.yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))
  vim.keymap.set({ "n", "x" }, "<leader>rc", cell.yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))
  vim.keymap.set("x", "yic", cell.yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))
  vim.keymap.set("n", "<leader>rq", history.delete_current_result, vim.tbl_extend("force", opts, { desc = "Delete Result Buffer & File" }))
  vim.keymap.set("n", "[b", function() map_result_history(bufnr, -1) end, vim.tbl_extend("force", opts, { desc = "Previous Result Buffer" }))
  vim.keymap.set("n", "]b", function() map_result_history(bufnr, 1) end, vim.tbl_extend("force", opts, { desc = "Next Result Buffer" }))
  vim.keymap.set("n", "<leader>rh", history.switch_result_history, vim.tbl_extend("force", opts, { desc = "Query Result History" }))
  vim.keymap.set("n", "<leader>rx", history.clear_all_results, vim.tbl_extend("force", opts, { desc = "Clear Query History" }))
end

return M
