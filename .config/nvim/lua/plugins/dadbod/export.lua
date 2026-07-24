-- SQL result export to CSV and JSON.

local M = {}

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

--- Copy SQL results directly to clipboard as CSV.
--- @param get_sql_block fun(): integer, integer, string[]
--- @param confirm_prod_action fun(action_name: string, callback: function)
function M.copy_block_as_csv(get_sql_block, confirm_prod_action)
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
    local _, _, block_lines = get_sql_block()
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

--- Copy SQL results directly to clipboard as formatted JSON.
--- @param get_sql_block fun(): integer, integer, string[]
--- @param confirm_prod_action fun(action_name: string, callback: function)
function M.copy_block_as_json(get_sql_block, confirm_prod_action)
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
    local _, _, block_lines = get_sql_block()
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

return M
