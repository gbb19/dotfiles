-- EXPLAIN/ANALYZE execution and result presentation.

local M = {}

--- Run EXPLAIN ANALYZE on the active SQL block.
--- @param verbose boolean|nil
--- @param get_sql_block fun(): integer, integer, string[]
--- @param flash_highlight fun(bufnr: integer, start_line: integer, end_line: integer)
function M.run(verbose, get_sql_block, flash_highlight)
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1]
  end
  if not db_url or db_url == "" then
    require("core.utils").notify("db_no_connection")
    return
  end

  local start_line, end_line, lines = get_sql_block()
  if not lines or #lines == 0 then return end
  local query_text = table.concat(lines, "\n")

  flash_highlight(bufnr, start_line, end_line)

  local shared = require("plugins.dadbod.shared")
  local adapter = shared.get_adapter(db_url) or "postgres"

  local explain_sql
  if adapter == "postgres" then
    explain_sql = verbose and ("EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS) " .. query_text)
      or ("EXPLAIN (ANALYZE, COSTS, BUFFERS) " .. query_text)
  elseif adapter == "mysql" then
    explain_sql = "EXPLAIN ANALYZE " .. query_text
  elseif adapter == "sqlite" then
    explain_sql = "EXPLAIN QUERY PLAN " .. query_text
  else
    explain_sql = "EXPLAIN ANALYZE " .. query_text
  end

  local db_service = vim.b[bufnr].db_service or ""
  local label = db_service ~= "" and db_service
    or (db_url:match("[?&]service=([^&#]+)") or db_url:match("^[^?#]*/([^/?#]+)") or "db")

  local handle = nil
  local ok, fidget_progress = pcall(require, "fidget.progress")
  if ok then
    handle = fidget_progress.handle.create({
      title      = string.format("DB [%s]", label),
      message    = verbose and "Analyzing performance (EXPLAIN VERBOSE)..." or "Analyzing performance (EXPLAIN)...",
      lsp_client = { name = "Dadbod" },
    })
  end

  local cmd = shared.build_cli_cmd(db_url)
  local start_time = vim.uv.hrtime()

  vim.system(cmd, { stdin = explain_sql, text = true }, vim.schedule_wrap(function(result)
    local elapsed = (vim.uv.hrtime() - start_time) / 1e9
    local runtime_str = string.format("%.3fs", elapsed)

    if result.code ~= 0 then
      local err_msg = (result.stderr and result.stderr ~= "") and result.stderr or "EXPLAIN analysis failed."
      require("core.utils").notify("db_query_failed", err_msg:sub(1, 300))
      if handle then
        handle.message = "Failed (" .. runtime_str .. ")"
        vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
      end
      return
    end

    if handle then
      handle.message = string.format("Analyzed in %.3fs", elapsed)
      vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
    end

    local raw_output = (result.stdout and result.stdout ~= "") and result.stdout or "No explain output"
    local output_lines = vim.split(raw_output, "\n", { plain = true })

    local clean_tree_lines = {}
    for _, l in ipairs(output_lines) do
      local trimmed = vim.trim(l)
      if trimmed ~= "QUERY PLAN"
        and not trimmed:match("^[-+%s]+$")
        and not trimmed:match("^%(%d+%s+rows?%)$")
        and trimmed ~= ""
      then
        table.insert(clean_tree_lines, l)
      end
    end

    local seq_scans = {}
    local index_scans = {}
    local exec_time = nil
    local plan_time = nil

    for _, line in ipairs(clean_tree_lines) do
      local seq_raw = line:match("[Ss]eq%s+[Ss]can%s+on%s+([%w_%.%\"]+)")
        or line:match("[Ff]ull%s+[Tt]able%s+[Ss]can%s+on%s+([%w_%.%\"]+)")
        or line:match("[Ss]CAN%s+[Tt]ABLE%s+([%w_%.%\"]+)")
      if seq_raw then
        local seq_tbl = seq_raw:gsub('^"', ''):gsub('"$', ''):gsub("%.$", "")
        if seq_tbl ~= "" then
          table.insert(seq_scans, seq_tbl)
        end
      end

      local idx_raw = line:match("[Ii]ndex%s+[Ss]can%s+using%s+([%w_%.%\"]+)")
        or line:match("[Ii]ndex%s+[Ss]can%s+on%s+([%w_%.%\"]+)")
        or line:match("[Ss]EARCH%s+[Tt]ABLE.*USING%s+INDEX%s+([%w_%.%\"]+)")
      if idx_raw then
        local idx_name = idx_raw:gsub('^"', ''):gsub('"$', ''):gsub("%.$", "")
        if idx_name ~= "" then
          table.insert(index_scans, idx_name)
        end
      end

      local etime = line:match("[Ee]xecution%s+[Tt]ime:%s*([%d%.]+%s*ms)")
      if etime then exec_time = etime end
      local ptime = line:match("[Pp]lanning%s+[Tt]ime:%s*([%d%.]+%s*ms)")
      if ptime then plan_time = ptime end
    end

    local report_lines = {}
    local header_title = verbose and "⚡ QUERY PERFORMANCE ANALYZER REPORT (VERBOSE)" or "⚡ QUERY PERFORMANCE ANALYZER REPORT"
    table.insert(report_lines, header_title)
    table.insert(report_lines, string.rep("═", 65))

    if exec_time or plan_time then
      local time_str = "Exec: "
      if exec_time then time_str = time_str .. " Execution Time: " .. exec_time end
      if plan_time then time_str = time_str .. " | Planning Time: " .. plan_time end
      table.insert(report_lines, time_str)
      table.insert(report_lines, "")
    end

    table.insert(report_lines, "📊 PERFORMANCE SUMMARY & BOTTLENECK ANALYSIS:")
    if #seq_scans > 0 then
      for _, tbl in ipairs(seq_scans) do
        table.insert(report_lines, string.format("  ⚠️  Sequential Scan (Full Table Scan) detected on: %s", tbl))
        table.insert(report_lines, string.format("      ↳ Tip: Adding an index on query filter columns for '%s' can speed up execution.", tbl))
      end
    else
      table.insert(report_lines, "  ✅  No Sequential Scans detected (Query is well-indexed).")
    end

    if #index_scans > 0 then
      for _, idx in ipairs(index_scans) do
        table.insert(report_lines, string.format("  ✅  Index Scan active: %s", idx))
      end
    end

    table.insert(report_lines, "")
    table.insert(report_lines, "📜 DETAILED EXPLAIN EXECUTION TREE:")
    table.insert(report_lines, string.rep("─", 65))
    for _, l in ipairs(clean_tree_lines) do
      table.insert(report_lines, l)
    end

    local sql_source_path = vim.api.nvim_buf_get_name(bufnr)
    local subdir = shared.get_subdir_for_sql(sql_source_path, bufnr)
      or ("/tmp/dadbodout_" .. vim.fn.getpid() .. "/query")
    vim.fn.mkdir(subdir, "p")

    local files = vim.fn.glob(subdir .. "/Result_*.dbout", true, true)
    local max_counter = 0
    for _, f in ipairs(files) do
      local n = tonumber(vim.fn.fnamemodify(f, ":t"):match("^Result_(%d+)_"))
      if n and n > max_counter then max_counter = n end
    end
    local current_counter = max_counter + 1

    local tag = verbose and "EXPLAIN_VERBOSE" or "EXPLAIN"
    local new_filename = string.format("Result_%d_%s.dbout", current_counter, tag)
    local new_path = subdir .. "/" .. new_filename

    local report_text = table.concat(report_lines, "\n")
    local f = io.open(new_path, "w")
    if f then
      f:write(report_text)
      f:close()
    end

    shared.show_result_in_window(new_path, subdir, sql_source_path)

    local target_buf = vim.fn.bufnr(new_path)
    if target_buf ~= -1 then
      vim.b[target_buf].db_runtime = string.format("%.3fs", elapsed)
      vim.b[target_buf].sql_source_path = sql_source_path
      vim.b[target_buf].original_lines = report_lines
      vim.bo[target_buf].filetype = "explain"
      pcall(function() require("lualine").refresh() end)

      local target_wins = vim.fn.win_findbuf(target_buf)
      for _, w in ipairs(target_wins) do
        vim.wo[w].wrap = false
      end

      vim.keymap.set("n", "gw", function()
        vim.wo.wrap = not vim.wo.wrap
        local key = vim.wo.wrap and "db_line_wrap_on" or "db_line_wrap_off"
        require("core.utils").notify(key)
      end, { buffer = target_buf, silent = true, desc = "Toggle EXPLAIN Line Wrap" })

      vim.api.nvim_buf_call(target_buf, function()
        vim.cmd([[syntax clear]])
        vim.cmd([[syntax match ExplainGood /\v(Index Scan|Index Only Scan|Bitmap Index Scan)/]])
        vim.cmd([[syntax match ExplainWarn /\v(Seq Scan|Sequential Scan|Full Table Scan)/]])
        vim.cmd([[syntax match ExplainNode /\v(Finalize\s+|Partial\s+)?(HashAggregate|Hash Join|Hash|Bitmap Heap Scan|BitmapAnd|BitmapOr|Custom Scan(\s+\([^)]+\))?|Nested Loop|Append|Sort|Gather\s*Merge|Gather|Materialize|Unique|Limit|WindowAgg|Group)/]])
        vim.cmd([[syntax match ExplainLabel /\v(Group Key:|Filter:|Recheck Cond:|Index Cond:|Output:|Rows Removed by Filter:|Heap Blocks:|Batches:|Memory Usage:|Grouping Policy:)/]])
        vim.cmd([[syntax match ExplainMeta /(cost=[^)]*)/]])
        vim.cmd([[syntax match ExplainMeta /(actual time=[^)]*)/]])
        vim.cmd([[syntax match ExplainBuffers /Buffers:[^\r\n]*/]])
        vim.cmd([[syntax match ExplainTitle /^⚡.*/]])
        vim.cmd([[syntax match ExplainSection /^📊.*/]])
        vim.cmd([[syntax match ExplainSection /^📜.*/]])
        vim.cmd([[highlight default link ExplainGood DiagnosticOk]])
        vim.cmd([[highlight default link ExplainWarn DiagnosticWarn]])
        vim.cmd([[highlight default link ExplainNode Function]])
        vim.cmd([[highlight default link ExplainLabel Statement]])
        vim.cmd([[highlight default link ExplainMeta Comment]])
        vim.cmd([[highlight default link ExplainBuffers DiagnosticInfo]])
        vim.cmd([[highlight default link ExplainTitle Title]])
        vim.cmd([[highlight default link ExplainSection Statement]])
      end)
    end
  end))
end

return M
