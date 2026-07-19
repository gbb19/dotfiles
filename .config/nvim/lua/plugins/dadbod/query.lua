-- lua/plugins/dadbod/query.lua
-- SQL block parsing, execution, safety guardrails, and data exporting.

local M = {}

--- Flash highlight lines temporarily in buffer to indicate execution
local function flash_highlight(bufnr, start_line, end_line)
  local ns = vim.api.nvim_create_namespace("db_flash")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for line = start_line - 1, end_line - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "Visual", line, 0, -1)
  end
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end, 150)
end

--- Prompts for confirmation if executing a write action on a production database
local function confirm_prod_action(action_name, callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db or ""
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1] or ""
  end

  local is_prod = db_url:match("prod") or db_url:match("production")
  if not is_prod then
    callback()
    return
  end

  vim.ui.input({
    prompt = string.format("WARNING: Production DB! Confirm '%s' by typing 'yes': ", action_name),
  }, function(input)
    if input and input:lower() == "yes" then
      callback()
    else
      require("core.utils").notify("db_operation_cancelled")
    end
  end)
end

--- Extract the logical SQL block surrounding the cursor.
--- SQL blocks are delimited by semicolons or double newlines.
--- @return integer, integer, string[]  start_line, end_line, lines
function M.get_sql_block()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local function is_empty_or_comment(line)
    local trimmed = vim.trim(line)
    return trimmed == "" or vim.startswith(trimmed, "--") or vim.startswith(trimmed, "/*")
  end

  local function has_valid_semicolon(line)
    local trimmed = vim.trim(line)
    return vim.endswith(trimmed, ";")
  end

  -- Search backwards for block start boundary
  local start_line = cursor_row
  while start_line > 1 do
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, start_line - 2, start_line - 1, false)[1]
    if is_empty_or_comment(prev_line) or has_valid_semicolon(prev_line) then
      break
    end
    start_line = start_line - 1
  end

  -- Search forwards for block end boundary
  local end_line = cursor_row
  while end_line < total_lines do
    local curr_line = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1]
    if has_valid_semicolon(curr_line) then
      break
    end
    local next_line = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1]
    if is_empty_or_comment(next_line) then
      break
    end
    end_line = end_line + 1
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return start_line, end_line, lines
end

--- Execute the SQL block or active selection asynchronously in parallel
function M.run_sql_block()
  local bufnr = vim.api.nvim_get_current_buf()

  local status = vim.b[bufnr].db_connection_status
  if status == "connecting" then
    require("core.utils").notify("db_connecting")
    return
  end

  local db_url = vim.b[bufnr].db
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1]
  end
  if not db_url or db_url == "" then
    require("core.utils").notify(status == "failed" and "db_connection_blocked" or "db_no_connection")
    return
  end

  local start_line, end_line, lines = M.get_sql_block()
  if not lines or #lines == 0 then return end
  local query_text = table.concat(lines, "\n")

  confirm_prod_action("Execute SQL block", function()
    flash_highlight(bufnr, start_line, end_line)

    -- Extract query snippet for filename
    local query_snippet = "query"
    for _, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      if trimmed ~= "" and not vim.startswith(trimmed, "--") and not vim.startswith(trimmed, "/*") then
        query_snippet = trimmed:gsub("%s+", " "):sub(1, 30)
        break
      end
    end
    query_snippet = query_snippet:gsub("[^%w%s_-]", ""):gsub("%s+", "_")
    if query_snippet == "" then query_snippet = "query" end

    local sql_source_path = vim.api.nvim_buf_get_name(bufnr)
    local shared = require("plugins.dadbod.shared")
    local subdir = shared.get_subdir_for_sql(sql_source_path, bufnr)
      or ("/tmp/dadbodout_" .. vim.fn.getpid() .. "/query")
    vim.fn.mkdir(subdir, "p")

    -- Determine next result counter
    local files = vim.fn.glob(subdir .. "/Result_*.dbout", true, true)
    local max_counter = 0
    for _, f in ipairs(files) do
      local n = tonumber(vim.fn.fnamemodify(f, ":t"):match("^Result_(%d+)_"))
      if n and n > max_counter then max_counter = n end
    end
    local current_counter = max_counter + 1

    local new_filename = string.format("Result_%d_%s.dbout", current_counter, query_snippet)
    local new_path = subdir .. "/" .. new_filename

    -- Fidget progress spinner handle
    local db_service = vim.b[bufnr].db_service or ""
    local label = db_service ~= "" and db_service
      or (db_url:match("[?&]service=([^&#]+)") or db_url:match("^[^?#]*/([^/?#]+)") or "db")

    local handle = nil
    local ok, fidget_progress = pcall(require, "fidget.progress")
    if ok then
      handle = fidget_progress.handle.create({
        title      = string.format("DB [%s]", label),
        message    = string.format("Running query #%d...", current_counter),
        lsp_client = { name = "Dadbod" },
      })
    end

    local cmd = shared.build_cli_cmd(db_url)
    local start_time = vim.uv.hrtime()

    vim.system(cmd, { stdin = query_text, text = true }, vim.schedule_wrap(function(result)
      local elapsed = (vim.uv.hrtime() - start_time) / 1e9
      local runtime_str = string.format("%.3fs", elapsed)

      local stderr = result.stderr and vim.trim(result.stderr) or ""
      local stdout = result.stdout and vim.trim(result.stdout) or ""

      local has_error = result.code ~= 0
        or stderr:find("ERROR:") or stderr:find("Error:") or stderr:find("FATAL:")
        or stdout:find("ERROR:") or stdout:find("Error:") or stdout:find("FATAL:")

      -- Case 1: Query execution error (failed) -> Notify error toast, DO NOT open dbout window
      if has_error then
        local err_msg = stderr ~= "" and stderr or (stdout ~= "" and stdout or "Query execution failed.")
        require("core.utils").notify("db_query_failed", err_msg:sub(1, 300))
        if handle then
          handle.message = "Failed (" .. runtime_str .. ")"
          vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
        end
        return
      end

      -- Case 2: Query executed successfully but returned NO result rows -> Notify success toast, DO NOT open dbout window
      if stdout == "" or stdout:match("^%(0 rows?%)$") or stdout:match("^UPDATE %d+$") or stdout:match("^INSERT %d+") or stdout:match("^DELETE %d+$") then
        local detail = stdout ~= "" and (stdout .. " | Exec: " .. runtime_str) or ("Exec: " .. runtime_str)
        require("core.utils").notify("db_query_success_empty", detail)
        if handle then
          handle.message = "Done (" .. runtime_str .. ")"
          vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
        end
        return
      end

      -- Case 3: Query returned actual data -> Write to file and open in dbout window
      local f = io.open(new_path, "w")
      if f then
        f:write(result.stdout)
        f:close()
      end

      shared.show_result_in_window(new_path, subdir, sql_source_path)

      local target_buf = vim.fn.bufnr(new_path)
      if target_buf ~= -1 then
        vim.b[target_buf].db_runtime = runtime_str
        vim.b[target_buf].sql_source_path = sql_source_path
        vim.b[target_buf].original_lines = vim.split(result.stdout, "\n", { plain = true })
        pcall(function() require("lualine").refresh() end)
      end

      if handle then
        handle.message = "Done (" .. runtime_str .. ")"
        vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
      end
    end))
  end)
end

-- Warn about missing CLI tool once per session
local warned_executables = {}
local function ensure_executable(cmd, msg_key)
  if vim.fn.executable(cmd) ~= 1 then
    if not warned_executables[cmd] then
      require("core.utils").notify(msg_key)
      warned_executables[cmd] = true
    end
    return false
  end
  return true
end

--- Runs database CLI utility directly to capture and format raw export output asynchronously.
local function run_export_cmd_async(db_url, is_json, query, action_title, on_done)
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1]
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if not db_url or db_url == "" then
    require("core.utils").notify("db_no_connection")
    return
  end

  local shared = require("plugins.dadbod.shared")
  local adapter = shared.get_adapter(db_url) or "postgres"
  local cli_tool = adapter == "sqlite" and "sqlite3" or (adapter == "mysql" and "mysql" or "psql")

  if not ensure_executable(cli_tool, "db_" .. cli_tool .. "_missing") then
    return
  end

  local db_service = vim.b[bufnr].db_service or ""
  local label = db_service ~= "" and db_service
    or (db_url:match("[?&]service=([^&#]+)") or db_url:match("^[^?#]*/([^/?#]+)") or "db")

  local handle = nil
  local ok, fidget_progress = pcall(require, "fidget.progress")
  if ok then
    handle = fidget_progress.handle.create({
      title      = string.format("DB [%s]", label),
      message    = action_title or "Processing...",
      lsp_client = { name = "Dadbod" },
    })
  end

  local cmd
  if adapter == "postgres" then
    if is_json then
      local json_query = "SELECT json_agg(t) FROM (" .. query .. ") t;"
      cmd = { "psql", db_url, "-t", "-A", "-c", json_query }
    else
      cmd = { "psql", db_url, "--csv", "-c", query }
    end
  elseif adapter == "mysql" then
    if is_json then
      cmd = { "mysql", "--json", db_url, "-e", query }
    else
      cmd = { "mysql", "--batch", "--raw", db_url, "-e", query }
    end
  elseif adapter == "sqlite" then
    local path = db_url:gsub("^sqlite3?://", "")
    if is_json then
      cmd = { "sqlite3", "-json", path, query }
    else
      cmd = { "sqlite3", "-csv", "-header", path, query }
    end
  else
    cmd = { "psql", db_url, "--csv", "-c", query }
  end

  vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      if handle then
        handle.message = "Failed"
        vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
      end
      local err = result.stderr or ""
      require("core.utils").notify("db_query_failed", err:sub(1, 200))
      return
    end

    on_done(result.stdout, handle)
  end))
end

--- Copy SQL results directly to clipboard as CSV
function M.copy_block_as_csv()
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db

  local mode = vim.fn.mode()
  local is_visual = mode:match("[vV\16]") ~= nil
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)
  end

  local lines
  if is_visual then
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  else
    local _, _, block_lines = M.get_sql_block()
    lines = block_lines
  end

  local query = table.concat(lines, "\n")

  confirm_prod_action("Copy CSV results", function()
    run_export_cmd_async(db_url, false, query, "Exporting CSV...", function(output, handle)
      if output and output ~= "" then
        vim.fn.setreg("+", output)
        require("core.utils").notify("db_copied_csv")
        if handle then
          handle.message = "Copied CSV!"
          vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
        end
      else
        if handle then
          pcall(function() handle:finish() end)
        end
      end
    end)
  end)
end

--- Copy SQL results directly to clipboard as formatted JSON
function M.copy_block_as_json()
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db

  local mode = vim.fn.mode()
  local is_visual = mode:match("[vV\16]") ~= nil
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)
  end

  local lines
  if is_visual then
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  else
    local _, _, block_lines = M.get_sql_block()
    lines = block_lines
  end

  local query = table.concat(lines, "\n")

  confirm_prod_action("Copy JSON results", function()
    run_export_cmd_async(db_url, true, query, "Exporting JSON...", function(output, handle)
      if not output or output == "" then
        if handle then pcall(function() handle:finish() end) end
        return
      end
      output = vim.trim(output)

      if ensure_executable("jq", "db_jq_missing") then
        if handle then handle.message = "Formatting JSON..." end
        -- Format output using jq asynchronously
        vim.system({ "jq", "." }, { stdin = output, text = true }, vim.schedule_wrap(function(format_result)
          if format_result.code == 0 and format_result.stdout then
            output = format_result.stdout
          end
          vim.fn.setreg("+", output)
          require("core.utils").notify("db_copied_json")
          if handle then
            handle.message = "Copied JSON!"
            vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
          end
        end))
      else
        vim.fn.setreg("+", output)
        require("core.utils").notify("db_copied_json")
        if handle then
          handle.message = "Copied JSON!"
          vim.defer_fn(function() pcall(function() handle:finish() end) end, 1500)
        end
      end
    end)
  end)
end

--- Run EXPLAIN ANALYZE on active SQL block and present performance insights floating window
--- @param verbose boolean|nil Whether to include VERBOSE in explain options
function M.explain_query(verbose)
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1]
  end
  if not db_url or db_url == "" then
    require("core.utils").notify("db_no_connection")
    return
  end

  local start_line, end_line, lines = M.get_sql_block()
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

    -- Clean up raw psql ASCII decoration lines (QUERY PLAN, -------------, (N rows), etc.)
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

    -- Analyze EXPLAIN output for performance bottlenecks
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

    -- Construct report lines in clean original layout
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

    -- Display in dbout result window
    shared.show_result_in_window(new_path, subdir, sql_source_path)

    local target_buf = vim.fn.bufnr(new_path)
    if target_buf ~= -1 then
      vim.b[target_buf].db_runtime = string.format("%.3fs", elapsed)
      vim.b[target_buf].sql_source_path = sql_source_path
      vim.b[target_buf].original_lines = report_lines
      vim.bo[target_buf].filetype = "explain"
      pcall(function() require("lualine").refresh() end)

      -- Apply nowrap by default to preserve execution tree indentation hierarchy
      local target_wins = vim.fn.win_findbuf(target_buf)
      for _, w in ipairs(target_wins) do
        vim.wo[w].wrap = false
      end

      -- Bind 'gw' inside explain buffer to toggle line wrapping on demand
      vim.keymap.set("n", "gw", function()
        vim.wo.wrap = not vim.wo.wrap
        local key = vim.wo.wrap and "db_line_wrap_on" or "db_line_wrap_off"
        require("core.utils").notify(key)
      end, { buffer = target_buf, silent = true, desc = "Toggle EXPLAIN Line Wrap" })

      -- Define custom syntax highlights for tree nodes, metrics, labels, and warnings
      vim.api.nvim_buf_call(target_buf, function()
        vim.cmd([[syntax clear]])

        -- Nodes & Operations
        vim.cmd([[syntax match ExplainGood /\v(Index Scan|Index Only Scan|Bitmap Index Scan)/]])
        vim.cmd([[syntax match ExplainWarn /\v(Seq Scan|Sequential Scan|Full Table Scan)/]])
        vim.cmd([[syntax match ExplainNode /\v(Finalize\s+|Partial\s+)?(HashAggregate|Hash Join|Hash|Bitmap Heap Scan|BitmapAnd|BitmapOr|Custom Scan(\s+\([^)]+\))?|Nested Loop|Append|Sort|Gather\s*Merge|Gather|Materialize|Unique|Limit|WindowAgg|Group)/]])

        -- Details & Metrics Labels
        vim.cmd([[syntax match ExplainLabel /\v(Group Key:|Filter:|Recheck Cond:|Index Cond:|Output:|Rows Removed by Filter:|Heap Blocks:|Batches:|Memory Usage:|Grouping Policy:)/]])
        vim.cmd([[syntax match ExplainMeta /(cost=[^)]*)/]])
        vim.cmd([[syntax match ExplainMeta /(actual time=[^)]*)/]])
        vim.cmd([[syntax match ExplainBuffers /Buffers:[^\r\n]*/]])

        -- Section Headers
        vim.cmd([[syntax match ExplainTitle /^⚡.*/]])
        vim.cmd([[syntax match ExplainSection /^📊.*/]])
        vim.cmd([[syntax match ExplainSection /^📜.*/]])

        -- Highlight Links
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
