local M = {}

-- Standard notification levels
local levels = vim.log.levels

-- Pre-defined messages to ensure consistent terminology and severities across the configuration
M.messages = {
  imports_organized       = { "Organized imports successfully", levels.INFO },
  imports_added           = { "Added missing imports successfully", levels.INFO },
  file_renamed            = { "File renamed and imports updated successfully", levels.INFO },
  no_source_def           = { "No source definition found", levels.WARN },
  error_source_def        = { "Error retrieving source definition", levels.ERROR },
  error_file_rename       = { "Error renaming file imports", levels.ERROR },
  error_disk_rename       = { "Error renaming file on disk", levels.ERROR },
  buffer_no_name          = { "Buffer has no name", levels.WARN },
  file_already_exists     = { "File already exists", levels.ERROR },
  buffer_renamed          = { "Buffer renamed to", levels.INFO },
  language_load_failed    = { "Failed to load language module", levels.ERROR },
  language_invalid_module = { "Language module must return a table", levels.WARN },
  mason_installing        = { "Installing Mason package", levels.INFO },
  mason_installed         = { "Installed Mason package", levels.INFO },
  mason_install_failed    = { "Failed to install Mason package", levels.ERROR },
  diagnostic_missing      = { "No diagnostics found on this line", levels.INFO },
  diagnostic_copied       = { "Copied diagnostic to clipboard", levels.INFO },
  diffview_action_failed  = { "Diffview action failed", levels.ERROR },
  diffview_cache_cleared  = { "Base branch cache cleared for this branch", levels.INFO },
  diffview_open_diff      = { "Diffing against", levels.INFO },
  diffview_open_history   = { "File history against", levels.INFO },
  diffview_reviewed       = { "Marked as reviewed", levels.INFO },
  diffview_unreviewed     = { "Removed reviewed mark", levels.INFO },
  git_uncommitted         = { "Line has uncommitted changes", levels.WARN },
  git_not_repo            = { "Not in a git repository", levels.ERROR },
  git_blame_failed        = { "Failed to run git blame for this line", levels.ERROR },
  git_open_merge          = { "Opening feature merge commit", levels.INFO },
  git_open_commit         = { "Opening line commit (no merge commit found)", levels.INFO },
  pack_lock_read_failed   = { "Could not read lockfile", levels.ERROR },
  pack_lock_parse_failed  = { "Failed to parse lockfile JSON", levels.ERROR },
  pack_clean_success      = { "Successfully cleaned unused plugins", levels.INFO },
  pack_clean_failed       = { "Failed to clean plugins", levels.ERROR },
  pack_clean_no_unused    = { "All plugins are clean. No unused plugins found.", levels.INFO },
  pack_clean_cancelled    = { "Clean operation cancelled", levels.WARN },
  lsp_install_no_servers  = { "No LSP servers configured in language modules", levels.INFO },
  lsp_install_all_already = { "All LSP servers are already installed", levels.INFO },
  lsp_install_starting    = { "Installing LSP servers", levels.INFO },
  dap_install_starting    = { "Installing DAP packages", levels.INFO },
  dap_no_breakpoints      = { "No breakpoints set", levels.INFO },
  -- Database/Dadbod messages
  db_no_connection        = { "No database connection bound to this buffer", levels.WARN },
  db_query_failed         = { "Database query failed", levels.ERROR },
  db_copied_csv           = { "Copied query results as CSV (with headers) to clipboard", levels.INFO },
  db_copied_json          = { "Copied query results as formatted JSON to clipboard", levels.INFO },
  db_bound                = { "Bound database", levels.INFO },
  db_no_cached_data       = { "No original query data cached for this buffer", levels.WARN },
  db_no_table_under_cursor= { "No table or alias found under the cursor", levels.WARN },
  db_table_not_found      = { "Table not found or no columns", levels.WARN },
  db_cache_cleared        = { "SQL column cache cleared", levels.INFO },
  db_no_configs           = { "No database connection profiles found in .db file", levels.WARN },
  db_psql_missing         = { "psql command is not installed on the system", levels.ERROR },
  db_mysql_missing        = { "mysql command is not installed on the system", levels.WARN },
  db_sqlite_missing       = { "sqlite3 command is not installed on the system", levels.WARN },
  db_jq_missing           = { "jq utility is not installed, JSON formatting skipped", levels.WARN },
  db_no_tables            = { "No tables found in this database", levels.WARN },
  db_fixed_width_enabled  = { "Enabled fixed column width", levels.INFO },
  db_fixed_width_disabled = { "Disabled fixed column width (restored original display)", levels.INFO },
  db_connection_failed    = { "Connection failed", levels.WARN },
  db_query_running        = { "A query is already running. Wait for it to finish before running another.", levels.WARN },
  db_connecting           = { "Connecting to database, please wait...", levels.WARN },
  db_connection_blocked   = { "Connection failed — use <leader>rs to switch profile", levels.WARN },
  db_empty_cell           = { "Empty cell", levels.INFO },
  db_copied_cell          = { "Copied full cell value to clipboard", levels.INFO },
  db_yanked_cell          = { "Yanked full cell", levels.INFO },
  db_yanked_json          = { "Yanked cell as formatted JSON", levels.INFO },
  db_executable_missing   = { "Executable not found for DB connection test", levels.WARN },
  db_operation_cancelled  = { "Operation cancelled", levels.WARN },
  db_deleted_result       = { "Deleted query result", levels.INFO },
  db_no_results_in_history= { "No query results found in history", levels.INFO },
  db_no_results_to_clear  = { "No query results found to clear", levels.INFO },
  db_cleared_all_results  = { "Successfully cleared all query results from history", levels.INFO },
  db_copied_in_clause     = { "Copied SQL IN condition to clipboard", levels.INFO },
  db_copied_insert_statement = { "Copied SQL INSERT statement to clipboard", levels.INFO },
  db_query_success_empty  = { "Query executed successfully (no rows returned)", levels.INFO },
  db_line_wrap_on         = { "Line wrap: ON", levels.INFO },
  db_line_wrap_off        = { "Line wrap: OFF", levels.INFO },
  load_env_success        = { "Environment variables loaded from", levels.INFO },
  load_env_not_found      = { "File not found", levels.ERROR },
}

--- Send a consistent user notification using pre-defined message keys
---@param key string Key from M.messages
---@param custom_err string|nil Optional detail text to append or use as body
---@param opts table|nil Optional overrides: { title, timeout }
function M.notify(key, custom_err, opts)
  local msg_data = M.messages[key]
  if not msg_data then
    -- Fallback for ad-hoc notifications if the key is not pre-defined
    vim.notify(key, levels.INFO)
    return
  end

  local text = msg_data[1]
  local level = msg_data[2]
  opts = opts or {}

  -- If snacks.notifier is available and a title is provided, use it for rich display
  local title = opts.title
  local timeout = opts.timeout
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notifier and (title or custom_err) then
    local level_str = ({
      [levels.DEBUG] = "debug",
      [levels.INFO]  = "info",
      [levels.WARN]  = "warn",
      [levels.ERROR] = "error",
    })[level] or "info"

    -- Word-wrap long lines so the popup fits without horizontal scrolling
    local max_width = 60
    local body = custom_err or text
    local wrapped_lines = {}
    for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
      if #line <= max_width then
        table.insert(wrapped_lines, line)
      else
        -- Break long line at word boundaries
        local remaining = line
        while #remaining > max_width do
          local cut = remaining:sub(1, max_width):match("^(.-)%s*$") or remaining:sub(1, max_width)
          local space = remaining:sub(1, max_width):find("%s[^%s]*$")
          if space and space > max_width * 0.5 then
            cut = remaining:sub(1, space - 1)
            remaining = remaining:sub(space + 1)
          else
            cut = remaining:sub(1, max_width)
            remaining = remaining:sub(max_width + 1)
          end
          table.insert(wrapped_lines, cut)
        end
        if #remaining > 0 then
          table.insert(wrapped_lines, remaining)
        end
      end
    end

    snacks.notifier.notify(table.concat(wrapped_lines, "\n"), level_str, {
      title   = title or text,
      timeout = timeout or 5000,
    })
    return
  end

  if custom_err then
    text = text .. ": " .. tostring(custom_err)
  end
  vim.notify(text, level)
end

--- Run a command or function with a visual loading notification and timeout safeguard
---@param opts table {title: string, message: string, run: string|function, event: string|nil, pattern: string|nil, timeout: number|nil}
function M.with_loading(opts)
  local snacks = require("snacks")
  local resolved = false
  local notif_id = snacks.notifier.notify(opts.message or "Executing background task...", "info", {
    title = opts.title or "System",
    icon = "⏳",
    keep = function() return not resolved end,
  })

  local timer = nil
  local group = nil

  local function resolve(success, msg)
    if resolved then return end
    resolved = true
    if timer then pcall(function() timer:close() end) end
    if group then pcall(vim.api.nvim_del_augroup_by_id, group) end

    if success then
      snacks.notifier.notify(msg or "Finished successfully!", "success", {
        id = notif_id,
        title = opts.title or "System",
        icon = "✔",
      })
    else
      snacks.notifier.notify(msg or "Operation failed or timed out", "warn", {
        id = notif_id,
        title = opts.title or "System",
        icon = "⚠️",
      })
    end
  end

  -- 1. Setup timeout fallback (default to 15 seconds)
  local timeout_ms = opts.timeout or 15000
  timer = vim.defer_fn(function()
    resolve(false, "Request timed out")
  end, timeout_ms)

  -- 2. Setup completion event listener if specified
  if opts.event then
    group = vim.api.nvim_create_augroup("LoadingResolve_" .. notif_id, { clear = true })
    vim.api.nvim_create_autocmd(opts.event, {
      pattern = opts.pattern,
      group = group,
      callback = function()
        resolve(true)
      end,
      once = true,
    })
  end

  -- 3. Execute the operation
  local status, err = pcall(function()
    if type(opts.run) == "string" then
      vim.cmd(opts.run)
    elseif type(opts.run) == "function" then
      opts.run(resolve)
    end
  end)

  if not status then
    resolve(false, tostring(err))
  elseif not opts.event and type(opts.run) ~= "function" then
    -- If it's a synchronous command and no event was provided, resolve immediately
    resolve(true)
  end
end

--- Generic function to rename the current buffer's file and path.
--- Special handling is provided for dbout query result buffers.
function M.rename_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_path = vim.api.nvim_buf_get_name(bufnr)
  if current_path == "" then
    M.notify("buffer_no_name")
    return
  end

  local current_filename = vim.fn.fnamemodify(current_path, ":t")
  local current_display = current_filename
  local is_dbout = (vim.bo[bufnr].filetype == "dbout") or (current_filename:match("%.dbout$") ~= nil)

  if is_dbout then
    current_display = current_filename:gsub("%.dbout$", ""):gsub("^Result_%d+_", ""):gsub("_", " ")
  end

  vim.ui.input({
    prompt = is_dbout and "Enter new result name: " or "Rename file/buffer to: ",
    default = current_display,
  }, function(input)
    if not input or vim.trim(input) == "" then return end

    local dir = vim.fn.fnamemodify(current_path, ":h")
    local ext = vim.fn.fnamemodify(current_path, ":e")
    
    local new_filename
    if is_dbout then
      local clean_name = input:gsub("[^%w%s_-]", ""):gsub("%s+", "_")
      local counter = current_filename:match("^Result_(%d+)_")
      if counter then
        new_filename = string.format("Result_%s_%s.%s", counter, clean_name, ext)
      else
        new_filename = string.format("Result_%s.%s", clean_name, ext)
      end
    else
      local clean_name = input:gsub("[^%w%s._-]", "")
      new_filename = clean_name
      if ext ~= "" and not new_filename:match("%." .. ext .. "$") then
        new_filename = new_filename .. "." .. ext
      end
    end
    
    local new_path = dir .. "/" .. new_filename

    if new_path == current_path then return end

    if vim.fn.filereadable(new_path) == 1 then
      M.notify("file_already_exists", new_filename)
      return
    end

    local has_file = (vim.fn.filereadable(current_path) == 1)
    if has_file then
      local success, err = os.rename(current_path, new_path)
      if not success then
        M.notify("error_disk_rename", tostring(err))
        return
      end
    end

    -- Temporarily disable autocommands to prevent layout/reset issues
    local save_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    vim.api.nvim_buf_set_name(bufnr, new_path)
    vim.o.eventignore = save_eventignore

    vim.bo[bufnr].modified = false
    vim.bo[bufnr].buflisted = not is_dbout

    if is_dbout then
      local db = vim.b[bufnr].db or {}
      if type(db) == "table" then
        db.output = new_path
        vim.b[bufnr].db = db
      end
    else
      if not has_file then
        vim.cmd("write")
      else
        vim.cmd("edit!")
      end
    end

    M.notify("buffer_renamed", new_filename)
  end)
end

return M
