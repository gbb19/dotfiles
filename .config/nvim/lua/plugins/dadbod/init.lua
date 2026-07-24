-- lua/plugins/dadbod/init.lua
-- Entry point for Neovim's dadbod configuration.
-- Configures autocommands, auto-connections, and routes buffer-local keymaps.

-- Add plugins using vim.pack
vim.pack.add({
  "https://github.com/tpope/vim-dadbod",
})

-- Suppress dadbod's built-in 'DB: Running query...' / 'DB: Query finished' echo messages
-- so we can replace them with Fidget spinner progress instead.
vim.g.db_ui_disable_info_notifications = 1

local M = {}
local state = require("plugins.dadbod.state")

-- Create custom setup autocommand group
local group = vim.api.nvim_create_augroup("DadbodCustomSetup", { clear = true })

-- Helper to retrieve identifier under the cursor (including dots)
local function get_identifier_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = line:sub(1, col):match("([%w_%.]*)$") or ""
  local after = line:sub(col + 1):match("^([%w_%.]*)") or ""
  return before .. after
end

-- Resolve the word under cursor to its actual database table name (resolving aliases if any)
local function resolve_word_to_table(word)
  if not word or word == "" then return nil end

  local bufnr = vim.api.nvim_get_current_buf()
  local parts = {}
  for part in string.gmatch(word, "[^%.]+") do
    table.insert(parts, part)
  end

  local shared = require("plugins.dadbod.shared")

  if #parts == 1 then
    return shared.resolve_alias_in_buf(bufnr, parts[1])
  elseif #parts == 2 then
    local resolved = shared.resolve_alias_in_buf(bufnr, parts[1])
    if resolved ~= parts[1] then
      return resolved
    else
      return word
    end
  elseif #parts >= 3 then
    return parts[1] .. "." .. parts[2]
  end
  return word
end

-- Interactively show table schema info (columns and types) on hover
function M.show_table_detail()
  local bufnr = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db
  if not db_url or db_url == "" or (type(db_url) == "table" and not next(db_url)) then
    require("core.utils").notify("db_no_connection")
    return
  end

  local full_identifier = get_identifier_under_cursor()
  if full_identifier == "" then
    require("core.utils").notify("db_no_table_under_cursor")
    return
  end

  local resolved = resolve_word_to_table(full_identifier)

  -- Check if table detail floating window is already open
  local parent_buf = vim.api.nvim_get_current_buf()
  local existing_win = vim.b[parent_buf].table_detail_win
  if existing_win and vim.api.nvim_win_is_valid(existing_win) then
    vim.api.nvim_win_close(existing_win, true)
    vim.b[parent_buf].table_detail_win = nil
    return
  end

  -- Fetch columns asynchronously and show float window
  require("plugins.dadbod.shared").fetch_columns_async(db_url, resolved, parent_buf, function(rows)
    if not rows or #rows == 0 then
      require("core.utils").notify("db_table_not_found", resolved)
      return
    end

    local display_lines = require("plugins.dadbod.shared").rows_to_display_lines(rows)
    local width = 0
    for _, l in ipairs(display_lines) do
      width = math.max(width, vim.fn.strdisplaywidth(l))
    end

    local title = " Schema: " .. resolved .. " "
    local title_w = vim.fn.strdisplaywidth(title)
    width = math.max(25, title_w + 2, width)

    local max_w = math.floor(vim.o.columns * 0.8)
    width = math.min(width, max_w)
    local height = math.min(#display_lines, math.floor(vim.o.lines * 0.8))

    -- Calculate layout relative to cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    local screen_row = cursor[1] - vim.fn.line("w0")
    local row_pos = 1
    if screen_row > height + 2 then
      row_pos = -(height + 2)
    end
    local col_pos = 0

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, display_lines)
    vim.bo[float_buf].bufhidden  = "wipe"
    vim.bo[float_buf].buftype    = "nofile"
    vim.bo[float_buf].modifiable = false

    -- Open without stealing focus (true hover)
    local win = vim.api.nvim_open_win(float_buf, false, {
      relative   = "cursor",
      row        = row_pos,
      col        = col_pos,
      width      = width,
      height     = height,
      style      = "minimal",
      border     = "rounded",
      title      = title,
      title_pos  = "center",
    })

    vim.b[parent_buf].table_detail_win = win

    -- Auto-close when cursor moves or buffer changes
    local group_id = vim.api.nvim_create_augroup("TableDetailHover_" .. win, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
      group    = group_id,
      buffer   = parent_buf,
      once     = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        vim.b[parent_buf].table_detail_win = nil
        pcall(vim.api.nvim_del_augroup_by_id, group_id)
      end,
    })
  end)
end

-- Upward folder-based connection file auto-loading (.db connection file)
local function auto_bind_connection(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return
  end

  -- Search upwards from the SQL file's directory for a '.db' file
  local db_file = vim.fs.find(".db", {
    upward = true,
    path = vim.fs.dirname(filepath),
  })[1]

  if db_file then
    local profiles, ordered_keys = require("plugins.dadbod.db").parse_db_file(db_file)
    if #ordered_keys > 0 then
      -- Default to the first profile in the file
      local default_key = ordered_keys[1]
      local connection_url = profiles[default_key]
      if connection_url and connection_url ~= "" then
        local db_service = require("plugins.dadbod.shared").get_service_name(connection_url, default_key)
        vim.b[bufnr].db_profile = default_key
        vim.b[bufnr].db_service = db_service
        vim.b[bufnr].db_file_path = db_file

        vim.b[bufnr].db_connection_status = "connecting"
        pcall(function() require("lualine").refresh() end)

        require("plugins.dadbod.db").test_connection_async(connection_url, bufnr, default_key, { is_auto = true })
      end
    end
  end
end

-- Registry: maps sql_source_path → last opened/visited dbout file path.
-- Keeps track of what specific result buffer the user viewed last for this SQL file.
local _last_result_by_sql = state.last_result_by_sql

--- Updates or invalidates the cached last dbout file path for a SQL buffer
function M.update_last_result(sql_path, result_path)
  state.update_last_result(sql_path, result_path)
end

local function get_subdir_for_sql(sql_path, bufnr)
  return require("plugins.dadbod.results").get_subdir_for_sql(sql_path, bufnr)
end

--- Returns the path of the newest Result_*.dbout in `subdir`, or nil if empty.
local function get_latest_result(subdir)
  return require("plugins.dadbod.results").get_latest_result(subdir)
end

local function show_result_in_window(result_path, subdir, sql_source_path)
  return require("plugins.dadbod.shared").show_result_in_window(result_path, subdir, sql_source_path)
end

--- Open (or switch to) the latest result for the current SQL buffer.
--- Useful after switching from another SQL file and wanting to see previous output.
function M.open_last_result()
  local sql_path = vim.api.nvim_buf_get_name(0)
  local subdir = get_subdir_for_sql(sql_path, 0)
  if not subdir then
    require("core.utils").notify("db_no_results_in_history")
    return
  end
  local latest = _last_result_by_sql[sql_path] or get_latest_result(subdir)
  if not latest then
    require("core.utils").notify("db_no_results_in_history")
    return
  end
  show_result_in_window(latest, subdir, sql_path)
end

vim.api.nvim_create_user_command("DbInspectTables", function()
  require("plugins.dadbod.picker").inspect_tables()
end, { desc = "Inspect DB Schema & Tables (View Only)" })

local function setup_sql_buffer(args)
  require("plugins.dadbod.buffers").setup_sql(args, {
    auto_bind = auto_bind_connection,
    open_last_result = M.open_last_result,
    show_table_detail = M.show_table_detail,
  })
end

require("plugins.dadbod.autocmds").setup({
  group = group,
  setup_sql = setup_sql_buffer,
})

local function is_dbout_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local ft = vim.bo[buf].filetype
  if ft == "dbout" or ft == "explain" then return true end
  local name = vim.api.nvim_buf_get_name(buf)
  if name:match("%.dbout$") or name:match("/Result_%d+_") or name:find("dadbodout", 1, true) then
    return true
  end
  return false
end

local function is_normal_editor_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config and win_config.relative and win_config.relative ~= "" then
    return false
  end
  if is_dbout_win(win) then return false end
  return true
end

-- Auto-close dbout/explain windows when quitting or closing the last normal window, preventing orphaned dbout windows
vim.api.nvim_create_autocmd("QuitPre", {
  group = group,
  callback = function()
    local wins = vim.api.nvim_list_wins()
    local normal_count = 0
    local dbout_wins = {}
    for _, win in ipairs(wins) do
      if is_dbout_win(win) then
        table.insert(dbout_wins, win)
      elseif is_normal_editor_win(win) then
        normal_count = normal_count + 1
      end
    end

    if normal_count <= 1 then
      for _, w in ipairs(dbout_wins) do
        pcall(function() vim.wo[w].winfixbuf = false end)
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end,
})

-- Track explicit window closure by user (:q or :close on dbout window)
vim.api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(args)
    local shared = require("plugins.dadbod.shared")
    if shared.is_deleting_result then return end

    local win = tonumber(args.match)
    if win and is_dbout_win(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local sql_src = vim.b[buf].sql_source_path
      if sql_src and sql_src ~= "" then
        local dbout_count = 0
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if w ~= win and is_dbout_win(w) then
            dbout_count = dbout_count + 1
          end
        end
        if dbout_count == 0 then
          shared.set_user_closed(sql_src, true)
        end
      end
    end

    -- Cleanup orphaned dbout windows if no normal editor windows remain
    vim.schedule(function()
      local wins = vim.api.nvim_list_wins()
      local normal_count = 0
      local dbout_wins = {}
      for _, w in ipairs(wins) do
        if is_dbout_win(w) then
          table.insert(dbout_wins, w)
        elseif is_normal_editor_win(w) then
          normal_count = normal_count + 1
        end
      end
      if normal_count == 0 and #dbout_wins > 0 then
        for _, w in ipairs(dbout_wins) do
          pcall(function() vim.wo[w].winfixbuf = false end)
          pcall(vim.api.nvim_win_close, w, true)
        end
        local remaining = vim.api.nvim_list_wins()
        if #remaining > 0 then
          local only_dbout = true
          for _, w in ipairs(remaining) do
            if not is_dbout_win(w) then
              only_dbout = false
              break
            end
          end
          if only_dbout then
            pcall(vim.cmd, "quit")
          end
        end
      end
    end)
  end,
})

-- Track last opened result buffer per SQL file to support viewing history switch
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.dbout",
  group = group,
  callback = function(args)
    local bufnr = args.buf
    local sql_path = vim.b[bufnr].sql_source_path
    if not sql_path or sql_path == "" then
      sql_path = require("plugins.dadbod.shared").find_sql_path_for_dbout(vim.api.nvim_buf_get_name(bufnr))
      if sql_path then
        vim.b[bufnr].sql_source_path = sql_path
      end
    end
    if sql_path and sql_path ~= "" then
      _last_result_by_sql[sql_path] = vim.api.nvim_buf_get_name(bufnr)
    end
  end,
})

-- Force Neovim to always route *.dbout files to the "dbout" filetype.
vim.filetype.add({
  pattern = {
    [".*%.dbout"] = "dbout",
  },
})

-- Export public API functions for backwards compatibility if needed
M.run_sql_block = function() require("plugins.dadbod.query").run_sql_block() end
M.copy_block_as_csv = function() require("plugins.dadbod.query").copy_block_as_csv() end
M.copy_block_as_json = function() require("plugins.dadbod.query").copy_block_as_json() end
M.switch_connection = function() require("plugins.dadbod.db").switch_connection() end
M.browse_tables = function() require("plugins.dadbod.picker").browse_tables() end
M.inspect_tables = function() require("plugins.dadbod.picker").inspect_tables() end
M.switch_result_history = function() require("plugins.dadbod.history").switch_result_history() end
M.clear_all_results = function() require("plugins.dadbod.history").clear_all_results() end

-- Cleanup: delete the temporary query results directory when Neovim exits
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    local base_dir = "/tmp/dadbodout_" .. vim.fn.getpid()
    vim.fn.delete(base_dir, "rf")
  end,
})

-- Handle immediate load case if the buffer is already SQL or dbout
if vim.bo.filetype == "sql" then
  setup_sql_buffer()
elseif vim.bo.filetype == "dbout" then
  require("plugins.dadbod.buffers").setup_dbout()
end

return M
