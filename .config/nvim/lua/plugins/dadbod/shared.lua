-- lua/plugins/dadbod/shared.lua
-- Shared utilities for columns.lua (completion) and init.lua (autocmds).
-- Centralises: adapter detection, URL parsing, alias resolution,
-- completion-item conversion, and active background job tracking.

local M = {}
local state = require("plugins.dadbod.state")
local sql = require("plugins.dadbod.sql")

-- Registry of active metadata-fetching jobs keyed by bufnr.
-- Allows us to kill them on :q! or buffer close so Neovim never hangs.
local _active_jobs = {} -- bufnr -> table of jobs (SystemObj)

local function kill_jobs_for_buf(bufnr)
  local jobs = _active_jobs[bufnr]
  if jobs then
    for _, job in ipairs(jobs) do
      pcall(function() job:kill(9) end)
    end
    _active_jobs[bufnr] = nil
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for bufnr in pairs(_active_jobs) do
      kill_jobs_for_buf(bufnr)
    end
  end,
})

vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    kill_jobs_for_buf(args.buf)
  end,
})

-- ---------------------------------------------------------------------------
-- Adapter Registry
-- ---------------------------------------------------------------------------

local adapters = {
  postgres = require("plugins.dadbod.adapters.postgres"),
  mysql    = require("plugins.dadbod.adapters.mysql"),
  sqlite   = require("plugins.dadbod.adapters.sqlite"),
}

--- Detect the database adapter from the db_url scheme.
--- @param db_url string
--- @return string|nil  "postgres" | "mysql" | "sqlite" | nil
function M.get_adapter(db_url)
  local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  local scheme = (url_str:match("^([%w%+%-]+)://") or ""):lower()
  if scheme == "postgresql" or scheme == "postgres" then return "postgres"
  elseif scheme == "mysql"  or scheme == "mariadb"  then return "mysql"
  elseif scheme == "sqlite" or scheme == "sqlite3"  then return "sqlite"
  end
  return nil
end

--- Extract the primary service or database name from a DB connection URL, defaulting to profile_name.
--- @param db_url string|table
--- @param profile_name? string
--- @return string
function M.get_service_name(db_url, profile_name)
  if not db_url or db_url == "" then
    return (profile_name and profile_name ~= "" and profile_name:lower() ~= "default") and profile_name or "DB"
  end

  local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)

  -- 1. Check for explicit service= parameter in URL query string (e.g. postgresql://?service=user-service-dev)
  local service = url_str:match("[?&]service=([^&#]+)")
  if service and service ~= "" then
    return service
  end

  -- 2. Extract database name from URL path (e.g. postgresql://user:pass@host:5432/user_db)
  local dbname = url_str:match("^[^?#]*/([^/?#]+)")
  if dbname and dbname ~= "" and dbname ~= "postgres" and dbname ~= "mysql" then
    return dbname
  end

  -- 3. Fallback to profile_name if available and not generic "default"
  if profile_name and profile_name ~= "" and profile_name:lower() ~= "default" then
    return profile_name
  end

  return (dbname and dbname ~= "") and dbname or "DB"
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Split "schema.table" into (schema, table).  Returns (nil, table) if no dot.
--- @param table_name string
--- @return string|nil, string
function M.split_table_name(table_name)
  return sql.split_table_name(table_name)
end

--- Scan the buffer and resolve an alias to its full table name.
--- e.g. "sp" -> "warehousing.spare_part_inventory_aggregate"
--- @param bufnr integer
--- @param alias string
--- @return string  full table name (or alias as-is if not found)
function M.resolve_alias_in_buf(bufnr, alias)
  -- 1. Get the current cursor position in the active window (if it is displaying this buffer)
  local cursor_row = 1
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
    cursor_row = vim.api.nvim_win_get_cursor(win)[1]
  end

  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local start_line, end_line = sql.find_block(total_lines, cursor_row, function(line)
    return vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
  end)
  local block_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return sql.resolve_alias(block_lines, alias)
end

-- Helper to warn if an executable is missing (once per session per tool)
local warned_executables = {}
local function ensure_executable(cmd_name)
  if vim.fn.executable(cmd_name) ~= 1 then
    if not warned_executables[cmd_name] then
      local msg_key = "db_" .. cmd_name .. "_missing"
      if cmd_name == "sqlite3" then
        msg_key = "db_sqlite_missing"
      end
      require("core.utils").notify(msg_key)
      warned_executables[cmd_name] = true
    end
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Quoting helper
-- ---------------------------------------------------------------------------

local reserved_keywords = {
  ["select"] = true, ["table"] = true, ["group"] = true, ["order"] = true,
  ["user"] = true, ["date"] = true, ["time"] = true, ["index"] = true,
  ["from"] = true, ["where"] = true, ["join"] = true, ["left"] = true,
  ["right"] = true, ["inner"] = true, ["outer"] = true, ["on"] = true,
  ["default"] = true, ["key"] = true, ["value"] = true,
}

--- Wraps an SQL identifier (column/table/schema name) in the database-specific quote character
--- if it is a reserved keyword, has uppercase letters, or has special characters.
--- @param name string
--- @param adapter string|nil
--- @return string
function M.quote_identifier(name, adapter)
  if not name or name == "" then return name end

  local a = adapters[adapter]
  local q = a and a.quote_char or '"'

  -- If it's already quoted, don't double quote
  if name:sub(1, 1) == q and name:sub(-1, -1) == q then
    return name
  end

  if reserved_keywords[name:lower()] or not name:match("^[a-z0-9_]+$") then
    return q .. name .. q
  end
  return name
end

-- ---------------------------------------------------------------------------
-- Async metadata fetchers
-- ---------------------------------------------------------------------------

--- Fetch columns for a table asynchronously and call on_done(rows | nil).
--- @param db_url string
--- @param table_name string
--- @param bufnr integer|nil
--- @param on_done function
function M.fetch_columns_async(db_url, table_name, bufnr, on_done)
  db_url = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  if type(bufnr) == "function" then
    on_done = bufnr
    bufnr = vim.api.nvim_get_current_buf()
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local adapter_name = M.get_adapter(db_url)
  local adapter = adapters[adapter_name]
  if not adapter then
    on_done(nil)
    return
  end

  local cmd, parse_fn = adapter.build_column_cmd(db_url, table_name)
  if not cmd or #cmd == 0 then
    on_done(nil)
    return
  end

  if not ensure_executable(cmd[1]) then
    on_done(nil)
    return
  end

  local job
  job = vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    -- Remove this job from active jobs
    if _active_jobs[bufnr] then
      for i, j in ipairs(_active_jobs[bufnr]) do
        if j == job then
          table.remove(_active_jobs[bufnr], i)
          break
        end
      end
      if #_active_jobs[bufnr] == 0 then
        _active_jobs[bufnr] = nil
      end
    end

    if result.code ~= 0 or not result.stdout or result.stdout == "" then
      on_done(nil)
      return
    end
    on_done(parse_fn(result.stdout))
  end))

  if not _active_jobs[bufnr] then
    _active_jobs[bufnr] = {}
  end
  table.insert(_active_jobs[bufnr], job)
end

--- Fetch all database tables asynchronously.
--- @param db_url string
--- @param bufnr integer|nil
--- @param on_done function
function M.fetch_tables_async(db_url, bufnr, on_done)
  db_url = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  if type(bufnr) == "function" then
    on_done = bufnr
    bufnr = vim.api.nvim_get_current_buf()
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local adapter_name = M.get_adapter(db_url)
  local adapter = adapters[adapter_name]
  if not adapter then
    on_done(nil)
    return
  end

  local cmd, parse_fn = adapter.build_tables_cmd(db_url)
  if not cmd or #cmd == 0 then
    on_done(nil)
    return
  end

  if not ensure_executable(cmd[1]) then
    on_done(nil)
    return
  end

  local job
  job = vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    -- Remove this job from active jobs
    if _active_jobs[bufnr] then
      for i, j in ipairs(_active_jobs[bufnr]) do
        if j == job then
          table.remove(_active_jobs[bufnr], i)
          break
        end
      end
      if #_active_jobs[bufnr] == 0 then
        _active_jobs[bufnr] = nil
      end
    end

    if result.code ~= 0 or not result.stdout or result.stdout == "" then
      on_done(nil)
      return
    end
    on_done(parse_fn(result.stdout))
  end))

  if not _active_jobs[bufnr] then
    _active_jobs[bufnr] = {}
  end
  table.insert(_active_jobs[bufnr], job)
end

-- ---------------------------------------------------------------------------
-- Hover & Autocomplete formatters
-- ---------------------------------------------------------------------------

--- Format a list of column rows into display lines for the hover window.
--- @param rows table[]  list of { col, detail, desc }
--- @return string[]
function M.rows_to_display_lines(rows)
  if not rows or #rows == 0 then return {} end

  -- Pre-process rows to strip "nullable" and calculate actual widths
  local w_col, w_type, w_null = 6, 4, 4 -- visual width of "column", "type", "null"
  local processed = {}
  for _, r in ipairs(rows) do
    local typ = r.detail:gsub("%s*|%s*nullable", "")
    local nullable = (r.detail:match("nullable") and "YES" or "NO")
    w_col  = math.max(w_col,  vim.fn.strdisplaywidth(r.col))
    w_type = math.max(w_type, vim.fn.strdisplaywidth(typ))
    w_null = math.max(w_null, vim.fn.strdisplaywidth(nullable))
    table.insert(processed, {
      col = r.col,
      typ = typ,
      nullable = nullable,
      desc = r.desc
    })
  end

  local lines = {}
  -- Build the line manually using spaces for padding based on visual display width
  local function pad(s, width)
    local sw = vim.fn.strdisplaywidth(s)
    if sw >= width then return s end
    return s .. string.rep(" ", width - sw)
  end

  table.insert(lines, pad("column", w_col) .. "  " .. pad("type", w_type) .. "  " .. pad("null", w_null))
  table.insert(lines, string.rep("─", w_col) .. "  " .. string.rep("─", w_type) .. "  " .. string.rep("─", w_null))

  for _, r in ipairs(processed) do
    local line = pad(r.col, w_col) .. "  " .. pad(r.typ, w_type) .. "  " .. pad(r.nullable, w_null)
    if r.desc and r.desc ~= "" then
      line = line .. "  -- " .. r.desc
    end
    table.insert(lines, line)
  end
  return lines
end

--- Convert rows to blink.cmp CompletionItem list.
--- @param rows table[]
--- @param adapter string|nil
--- @return table[]
function M.rows_to_completion_items(rows, adapter)
  local items = {}
  for _, r in ipairs(rows) do
    local q_col = M.quote_identifier(r.col, adapter)
    table.insert(items, {
      label         = q_col,
      kind          = vim.lsp.protocol.CompletionItemKind.Field,
      detail        = r.detail,
      documentation = (r.desc and r.desc ~= "")
        and { kind = "plaintext", value = r.desc } or nil,
      insertText    = q_col,
      sortText      = q_col,
    })
  end
  return items
end

--- Safely set a buffer into a window even if winfixbuf is enabled on that window
--- @param win integer
--- @param target_buf integer
--- @return boolean ok
function M.set_win_buf_safely(win, target_buf)
  if not win or win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  if not vim.api.nvim_win_is_valid(win) then return false end

  local was_fixed = vim.wo[win].winfixbuf
  if was_fixed then
    vim.wo[win].winfixbuf = false
  end

  local ok = pcall(vim.api.nvim_win_set_buf, win, target_buf)

  if vim.api.nvim_win_is_valid(win) then
    local ft = vim.bo[target_buf].filetype
    if ft == "dbout" or ft == "explain" or was_fixed then
      vim.wo[win].winfixbuf = true
    end
  end

  return ok
end

--- Get the stable, absolute query result subdirectory path for a given SQL file.
--- @param sql_path string
--- @param bufnr integer|nil
--- @return string|nil
function M.get_subdir_for_sql(sql_path, bufnr)
  return require("plugins.dadbod.results").get_subdir_for_sql(sql_path, bufnr)
end

M.user_closed_by_sql = state.user_closed_by_sql

function M.is_user_closed(sql_path)
  if not sql_path or sql_path == "" then return false end
  return M.user_closed_by_sql[sql_path] == true
end

function M.set_user_closed(sql_path, closed)
  if not sql_path or sql_path == "" then return end
  if closed then
    M.user_closed_by_sql[sql_path] = true
  else
    M.user_closed_by_sql[sql_path] = nil
  end
end

--- Open `result_path` in a dbout window, reusing an existing one when possible.
--- Preserves original active window focus so the user's cursor remains in their SQL editor.
function M.show_result_in_window(result_path, subdir, sql_source_path)
  local target_buf = vim.fn.bufnr(result_path)
  local sql_src = sql_source_path
  if not sql_src and target_buf ~= -1 then
    sql_src = vim.b[target_buf].sql_source_path
  end
  if sql_src and sql_src ~= "" then
    M.set_user_closed(sql_src, false)
  end

  local orig_win = vim.api.nvim_get_current_win()
  state.last_dbout_dir = subdir

  if target_buf == -1 then
    target_buf = vim.fn.bufadd(result_path)
    vim.fn.bufload(target_buf)
  end

  if sql_src and sql_src ~= "" then
    vim.b[target_buf].sql_source_path = sql_src
  end

  local wins = vim.fn.win_findbuf(target_buf)
  if #wins > 0 then
    if vim.api.nvim_win_is_valid(orig_win) then
      vim.api.nvim_set_current_win(orig_win)
    end
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft == "dbout" or ft == "explain" then
      M.set_win_buf_safely(win, target_buf)
      if vim.api.nvim_win_is_valid(orig_win) then
        vim.api.nvim_set_current_win(orig_win)
      end
      return
    end
  end

  vim.cmd("vertical split")
  local new_win = vim.api.nvim_get_current_win()
  M.set_win_buf_safely(new_win, target_buf)

  if vim.api.nvim_win_is_valid(orig_win) then
    vim.api.nvim_set_current_win(orig_win)
  end
end


--- Build CLI command for executing query based on database adapter with strict error stop flags.
function M.build_cli_cmd(db_url)
  db_url = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  local adapter = M.get_adapter(db_url)
  if adapter == "postgres" then
    return { "psql", "-v", "ON_ERROR_STOP=1", db_url }
  elseif adapter == "mysql" then
    return { "mysql", "--abort-on-error", "--table", db_url }
  elseif adapter == "sqlite" then
    local path = db_url:gsub("^sqlite3?://", "")
    return { "sqlite3", "-bail", "-header", "-column", path }
  elseif adapter == "duckdb" then
    local path = db_url:gsub("^duckdb://", "")
    return { "duckdb", "-bail", path }
  elseif adapter == "mssql" or adapter == "sqlserver" then
    return { "sqlcmd", "-b", db_url }
  else
    return { "psql", "-v", "ON_ERROR_STOP=1", db_url }
  end
end

--- Try to find the matching SQL source path for a given dbout buffer path by matching their result directories
function M.find_sql_path_for_dbout(dbout_path)
  return require("plugins.dadbod.results").find_sql_path_for_dbout(dbout_path)
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "is_deleting_result" then
      return state.is_deleting_result
    end
  end,
  __newindex = function(_, key, value)
    if key == "is_deleting_result" then
      state.is_deleting_result = value
    else
      rawset(M, key, value)
    end
  end,
})
