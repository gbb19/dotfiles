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

-- Local setup for the dbout result buffers
local function setup_dbout_buffer(args)
  local bufnr = args and args.buf or vim.api.nvim_get_current_buf()
  require("plugins.dadbod.format").truncate_dbout_buffer(bufnr)

  -- Ensure nowrap is set on the results window
  vim.cmd("setlocal nowrap")

  -- Resize the vertical split window to occupy exactly half the screen width (only if window exists)
  -- and lock the window with winfixbuf so other files won't open inside this result window.
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

  -- Keymap 'gz' and 'K' to inspect full cell value in floating window
  vim.keymap.set("n", "gz", require("plugins.dadbod.cell").show_cell_detail, vim.tbl_extend("force", opts, { desc = "Inspect full cell value" }))
  vim.keymap.set("n", "K", require("plugins.dadbod.cell").show_cell_detail, vim.tbl_extend("force", opts, { desc = "Inspect full cell value (Hover)" }))

  -- Keymap 'gW' to toggle fixed column width truncation
  vim.keymap.set("n", "gW", function() require("plugins.dadbod.format").toggle_dbout_column_width(bufnr) end, vim.tbl_extend("force", opts, { desc = "Toggle fixed column width" }))

  -- Next/Prev Column Jump
  vim.keymap.set("n", "<Tab>", function() require("plugins.dadbod.format").jump_column("next") end, vim.tbl_extend("force", opts, { desc = "Next Column" }))
  vim.keymap.set("n", "<S-Tab>", function() require("plugins.dadbod.format").jump_column("prev") end, vim.tbl_extend("force", opts, { desc = "Previous Column" }))

  -- Go to Header
  vim.keymap.set("n", "gh", "1G", vim.tbl_extend("force", opts, { desc = "Jump to Header" }))

  -- Cell Text Objects (ic for inner cell, ac for around cell)
  vim.keymap.set({ "o", "x" }, "ic", function() require("plugins.dadbod.cell").select_cell(false) end, vim.tbl_extend("force", opts, { desc = "inner cell" }))
  vim.keymap.set({ "o", "x" }, "ac", function() require("plugins.dadbod.cell").select_cell(true) end, vim.tbl_extend("force", opts, { desc = "around cell" }))

  -- Yank Original full value directly from normal mode
  vim.keymap.set("n", "yic", function() require("plugins.dadbod.cell").yank_cell(false) end, vim.tbl_extend("force", opts, { desc = "Yank full inner cell" }))
  vim.keymap.set("n", "yac", function() require("plugins.dadbod.cell").yank_cell(true) end, vim.tbl_extend("force", opts, { desc = "Yank full around cell" }))

  -- Yank column values as SQL IN condition (e.g. status IN ('A', 'B'))
  vim.keymap.set({ "n", "x" }, "yin", require("plugins.dadbod.cell").yank_in_clause, vim.tbl_extend("force", opts, { desc = "Yank Column as SQL IN Condition" }))
  vim.keymap.set({ "n", "x" }, "<leader>yi", require("plugins.dadbod.cell").yank_in_clause, vim.tbl_extend("force", opts, { desc = "Yank Column as SQL IN Condition" }))

  -- Yank rows as SQL INSERT Statement (e.g. INSERT INTO table (a, b) VALUES (1, 'x'))
  vim.keymap.set({ "n", "x" }, "yis", require("plugins.dadbod.cell").yank_insert_statements, vim.tbl_extend("force", opts, { desc = "Yank Rows as SQL INSERT Statement" }))
  vim.keymap.set({ "n", "x" }, "<leader>ys", require("plugins.dadbod.cell").yank_insert_statements, vim.tbl_extend("force", opts, { desc = "Yank Rows as SQL INSERT Statement" }))

  -- Yank rows as CSV (e.g. col1,col2\nval1,val2)
  vim.keymap.set({ "n", "x" }, "<leader>yc", require("plugins.dadbod.cell").yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))
  vim.keymap.set({ "n", "x" }, "<leader>rc", require("plugins.dadbod.cell").yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))
  vim.keymap.set("x", "yic", require("plugins.dadbod.cell").yank_csv, vim.tbl_extend("force", opts, { desc = "Yank Rows as CSV" }))

  -- Delete current query result and wipe buffer (<leader>rq)
  vim.keymap.set("n", "<leader>rq", require("plugins.dadbod.history").delete_current_result, vim.tbl_extend("force", opts, { desc = "Delete Result Buffer & File" }))



  -- Switch to next/prev result buffer in history (overriding [b / ]b inside dbout buffers)
  vim.keymap.set("n", "[b", function()
    local current_path = vim.api.nvim_buf_get_name(0)
    local result_files = require("plugins.dadbod.history").get_result_files(current_path)
    if #result_files == 0 then return end
    
    local current_idx = nil
    for idx, item in ipairs(result_files) do
      if item.path == current_path then
        current_idx = idx
        break
      end
    end
    
    if not current_idx then return end
    local prev_idx = current_idx - 1
    if prev_idx == 0 then prev_idx = #result_files end
    
    local target = result_files[prev_idx]
    local target_buf = vim.fn.bufnr(target.path)
    if target_buf == -1 then
      target_buf = vim.fn.bufadd(target.path)
      vim.fn.bufload(target_buf)
    end

    -- Propagate sql_source_path to the buffer being switched to
    local cur_buf = vim.api.nvim_get_current_buf()
    local cur_sql = vim.b[cur_buf].sql_source_path
    if cur_sql then
      vim.b[target_buf].sql_source_path = cur_sql
    end
    
    require("plugins.dadbod.shared").set_win_buf_safely(0, target_buf)
    
    require("plugins.dadbod.history").show_history_popup(result_files, target.path)
  end, vim.tbl_extend("force", opts, { desc = "Previous Result Buffer" }))

  vim.keymap.set("n", "]b", function()
    local current_path = vim.api.nvim_buf_get_name(0)
    local result_files = require("plugins.dadbod.history").get_result_files(current_path)
    if #result_files == 0 then return end
    
    local current_idx = nil
    for idx, item in ipairs(result_files) do
      if item.path == current_path then
        current_idx = idx
        break
      end
    end
    
    if not current_idx then return end
    local next_idx = current_idx + 1
    if next_idx > #result_files then next_idx = 1 end
    
    local target = result_files[next_idx]
    local target_buf = vim.fn.bufnr(target.path)
    if target_buf == -1 then
      target_buf = vim.fn.bufadd(target.path)
      vim.fn.bufload(target_buf)
    end

    -- Propagate sql_source_path to the buffer being switched to
    local cur_buf = vim.api.nvim_get_current_buf()
    local cur_sql = vim.b[cur_buf].sql_source_path
    if cur_sql then
      vim.b[target_buf].sql_source_path = cur_sql
    end
    
    require("plugins.dadbod.shared").set_win_buf_safely(0, target_buf)
    
    require("plugins.dadbod.history").show_history_popup(result_files, target.path)
  end, vim.tbl_extend("force", opts, { desc = "Next Result Buffer" }))

  vim.keymap.set("n", "<leader>rh", require("plugins.dadbod.history").switch_result_history, vim.tbl_extend("force", opts, { desc = "Query Result History" }))
  vim.keymap.set("n", "<leader>rx", require("plugins.dadbod.history").clear_all_results, vim.tbl_extend("force", opts, { desc = "Clear Query History" }))
end

-- Autocommands for DB output & explain files: enforce winfixbuf so picker/bufferline cannot replace this window
vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufEnter", "BufWinEnter" }, {
  pattern = { "dbout", "*.dbout", "explain" },
  group = group,
  callback = setup_dbout_buffer,
})

-- Track active Fidget handles per output file path
local _query_handles = {}

-- Registry: maps output file_path → SQL source bufnr captured at DBExecutePre time.
-- Needed because db_input on the dbout buffer is a dadbod temp file, not the real SQL path.
local _sql_source_by_output = {}

-- Registry: maps sql_source_path → last opened/visited dbout file path.
-- Keeps track of what specific result buffer the user viewed last for this SQL file.
local _last_result_by_sql = {}

--- Updates or invalidates the cached last dbout file path for a SQL buffer
function M.update_last_result(sql_path, result_path)
  if sql_path and sql_path ~= "" then
    if result_path and result_path ~= "" and vim.fn.filereadable(result_path) == 1 then
      _last_result_by_sql[sql_path] = result_path
    else
      _last_result_by_sql[sql_path] = nil
    end
  end
end

local function get_subdir_for_sql(sql_path, bufnr)
  return require("plugins.dadbod.shared").get_subdir_for_sql(sql_path, bufnr)
end

--- Returns the path of the newest Result_*.dbout in `subdir`, or nil if empty.
local function get_latest_result(subdir)
  if not subdir or subdir == "" then return nil end
  local files = vim.fn.glob(subdir .. "/Result_*.dbout", true, true)
  local best_counter, best_path = -1, nil
  for _, f in ipairs(files) do
    if vim.fn.filereadable(f) == 1 then
      local n = tonumber(vim.fn.fnamemodify(f, ":t"):match("^Result_(%d+)_"))
      if n and n > best_counter then best_counter, best_path = n, f end
    end
  end
  return best_path
end

local function show_result_in_window(result_path, subdir, sql_source_path)
  return require("plugins.dadbod.shared").show_result_in_window(result_path, subdir, sql_source_path)
end

-- Intercept DBExecutePre: show Fidget spinner when a query starts
vim.api.nvim_create_autocmd("User", {
  pattern = "*dbout/DBExecutePre",
  group = group,
  callback = function(args)
    local file_path = args.match:match("^(.*)/DBExecutePre$")
    if not file_path then return end

    -- Capture the SQL source buffer NOW, before dadbod switches focus to the result window.
    -- vim.api.nvim_get_current_buf() is still the .sql buffer at this point.
    _sql_source_by_output[file_path] = vim.api.nvim_get_current_buf()

    local ok, fidget_progress = pcall(require, "fidget.progress")
    if not ok then return end

    -- Close any lingering handle for this file (e.g. re-run 'R')
    if _query_handles[file_path] then
      pcall(function() _query_handles[file_path]:finish() end)
    end

    -- Derive label from the connection URL, works across all supported DB types:
    --   postgresql://?service=vendii-local  →  vendii-local   (service param)
    --   mysql://user@host/mydb?charset=utf8 →  mydb           (path before ?)
    --   sqlite:///home/user/app.db          →  app.db         (last path segment)
    local db_url = vim.b.db or ""
    local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
    local label = url_str:match("[?&]service=([^&#]+)")  -- service= anywhere in query string
      or url_str:match("^[^?#]*/([^/?#]+)")              -- last path segment before ? or #
      or "db"

    _query_handles[file_path] = fidget_progress.handle.create({
      title      = string.format("DB [%s]", label),
      message    = "Running...",
      lsp_client = { name = "Dadbod" },
    })
  end,
})

local query_run_count = 0

-- Autocommand to rename DB output buffers to avoid overwriting them
vim.api.nvim_create_autocmd("User", {
  pattern = "*dbout/DBExecutePost",
  group = group,
  callback = function(args)
    local file_path = args.match:match("^(.*)/DBExecutePost$")
    if not file_path then return end

    local bufnr = vim.fn.bufnr(file_path)
    if bufnr == -1 then return end

    -- Avoid renaming again if this result buffer was already renamed (e.g. on rerun 'R')
    local filename = vim.fn.fnamemodify(file_path, ":t")
    if filename:match("^Result_%d+_") then
      return
    end

    -- Extract SQL Query Snippet for filename prefix
    local query_snippet = "query"
    local db_input = vim.b[bufnr].db_input
    if db_input and vim.fn.filereadable(db_input) == 1 then
      local lines = vim.fn.readfile(db_input, "", 5)
      for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "--") and not vim.startswith(trimmed, "/*") then
          query_snippet = trimmed:gsub("%s+", " "):sub(1, 30)
          break
        end
      end
    end

    -- Clean query snippet for safe filename
    query_snippet = query_snippet:gsub("[^%w%s_-]", ""):gsub("%s+", "_")
    query_run_count = query_run_count + 1

    local dir = vim.fn.fnamemodify(file_path, ":h")
    local ext = vim.fn.fnamemodify(file_path, ":e")

    -- Resolve the real SQL source buffer from the registry captured in DBExecutePre.
    -- b:db_input on the dbout buffer is a dadbod-internal TEMP FILE, not the .sql source path,
    -- so vim.fs.find(".db") and vim.fn.bufnr() from it would always fail.
    local sql_source_bufnr = _sql_source_by_output[file_path]
    _sql_source_by_output[file_path] = nil  -- consume and free

    -- Resolve real SQL source path for subdir key computation
    local sql_source_path = (sql_source_bufnr and sql_source_bufnr ~= -1)
      and vim.api.nvim_buf_get_name(sql_source_bufnr)
      or ""

    -- Get the stable subdirectory path for this SQL query result
    local subdir = get_subdir_for_sql(sql_source_path, sql_source_bufnr)
    if not subdir then
      -- Fallback to temporary folder
      subdir = dir .. "/query"
    end
    vim.fn.mkdir(subdir, "p")

    -- Find the highest existing result counter in the directory to avoid collisions across sessions
    local files = vim.fn.glob(subdir .. "/Result_*.dbout", true, true)
    local max_counter = 0
    for _, f in ipairs(files) do
      local n = tonumber(vim.fn.fnamemodify(f, ":t"):match("^Result_(%d+)_"))
      if n and n > max_counter then
        max_counter = n
      end
    end
    local current_counter = max_counter + 1

    local new_filename = string.format("Result_%d_%s.%s", current_counter, query_snippet, ext)
    local new_path = subdir .. "/" .. new_filename

    -- Temporarily disable autocommands to prevent infinite loop or layout/resize issues
    local save_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"

    -- Rename the physical file on disk (fallback to copy+unlink for cross-filesystem moves)
    local move_ok, move_err = os.rename(file_path, new_path)
    if not move_ok then
      local uv = vim.uv or vim.loop
      local copy_ok, copy_err = uv.fs_copyfile(file_path, new_path)
      if copy_ok then
        uv.fs_unlink(file_path)
      else
        require("core.utils").notify("error_disk_rename", tostring(copy_err))
      end
    end

    -- If a buffer with the target name already exists in Neovim, wipe it out
    -- to prevent Vim:E95: Buffer with this name already exists.
    local existing_buf = vim.fn.bufnr(new_path)
    if existing_buf ~= -1 and existing_buf ~= bufnr then
      pcall(vim.cmd, "bwipeout! " .. existing_buf)
    end

    -- Rename the buffer in Neovim
    vim.api.nvim_buf_set_name(bufnr, new_path)

    vim.o.eventignore = save_eventignore

    -- Set buffer as not modified so switching buffers is allowed without warning E37
    vim.bo[bufnr].modified = false

    -- Prevent Neovim from deleting the buffer when hidden, but keep it unlisted (clean history)
    vim.bo[bufnr].bufhidden = ""
    vim.bo[bufnr].buflisted = false

    -- Bind sql_source_path to this result buffer so history navigator can track it
    if sql_source_path ~= "" then
      vim.b[bufnr].sql_source_path = sql_source_path
      _last_result_by_sql[sql_source_path] = new_path
    end

    -- Store active output folder path for global query history lookup
    -- Point history tracker at the subdir so [b/]b sees only results from this SQL file
    require("plugins.dadbod.history").last_dbout_dir = subdir

    local db = vim.b[bufnr].db or {}
    if type(db) == "table" then
      db.output = new_path
      vim.b[bufnr].db = db
    end

    -- Save query execution time to buffer variable and refresh winbar
    local db_info = vim.b[bufnr].db or {}
    local runtime = type(db_info) == "table" and db_info.runtime
    if runtime then
      vim.b[bufnr].db_runtime = string.format("%.3fs", runtime)
      pcall(function() require("lualine").refresh() end)
    end

    -- Close Fidget spinner for this query (keyed by original temp path)
    if _query_handles[file_path] then
      local handle = _query_handles[file_path]
      _query_handles[file_path] = nil
      local msg = runtime and string.format("Done in %.3fs", runtime) or "Done"
      handle.message = msg
      vim.defer_fn(function()
        pcall(function() handle:finish() end)
      end, 1500)
    end
  end,
})

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

local function setup_sql_buffer(args)
  local bufnr = args and args.buf or vim.api.nvim_get_current_buf()
  vim.bo[bufnr].omnifunc = ""
  auto_bind_connection(bufnr)

  -- Keymaps for DB operations (Buffer local)
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "<leader>rr", require("plugins.dadbod.query").run_sql_block, vim.tbl_extend("force", opts, { desc = "Run SQL Block" }))
  vim.keymap.set("v", "<leader>rr", function()
    -- Exit visual mode to save '< and '> marks
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)

    -- Same guard as run_sql_block: block if profile was set but failed/connecting
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
  vim.keymap.set("n", "<leader>ro", M.open_last_result, vim.tbl_extend("force", opts, { desc = "Open Last Result for this SQL file" }))
  vim.keymap.set("n", "<leader>rt", M.show_table_detail, vim.tbl_extend("force", opts, { desc = "Show Table Detail (Hover)" }))
  vim.keymap.set("n", "K", M.show_table_detail, vim.tbl_extend("force", opts, { desc = "Show Table Detail (Hover)" }))
  vim.keymap.set("n", "<leader>rs", require("plugins.dadbod.db").switch_connection, vim.tbl_extend("force", opts, { desc = "Switch Database Environment" }))
  vim.keymap.set("n", "<leader>rf", require("plugins.dadbod.picker").inspect_tables, vim.tbl_extend("force", opts, { desc = "Inspect DB Schema & Tables (View Only)" }))
  vim.keymap.set("n", "<leader>ri", require("plugins.dadbod.picker").inspect_tables, vim.tbl_extend("force", opts, { desc = "Inspect DB Schema & Tables (View Only)" }))
  vim.keymap.set("n", "<leader>rh", require("plugins.dadbod.history").switch_result_history, vim.tbl_extend("force", opts, { desc = "Query Result History" }))
  vim.keymap.set("n", "<leader>rx", require("plugins.dadbod.history").clear_all_results, vim.tbl_extend("force", opts, { desc = "Clear Query History" }))
end

vim.api.nvim_create_user_command("DbInspectTables", function()
  require("plugins.dadbod.picker").inspect_tables()
end, { desc = "Inspect DB Schema & Tables (View Only)" })

-- Set up autocommands for SQL files (Folder binding & Omnifunc fallback)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "sql",
  group = group,
  callback = setup_sql_buffer,
})

-- Auto-preview: when entering a SQL buffer, auto-show its latest result in the dbout window if available.
-- If the buffer has no results, automatically close the dbout window so it never displays leftover results from other files.
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.sql",
  group = group,
  callback = function(args)
    local sql_bufnr = args.buf
    local sql_path = vim.api.nvim_buf_get_name(sql_bufnr)
    if not sql_path or sql_path == "" then return end

    local subdir = get_subdir_for_sql(sql_path, sql_bufnr)
    if not subdir then return end

    -- Find any visible dbout/explain window
    local dbout_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if ft == "dbout" or ft == "explain" then
        dbout_win = win
        break
      end
    end

    local cached_file = _last_result_by_sql[sql_path]
    if cached_file and vim.fn.filereadable(cached_file) ~= 1 then
      _last_result_by_sql[sql_path] = nil
      cached_file = nil
    end

    local latest = cached_file or get_latest_result(subdir)
    local has_valid_result = latest and vim.fn.filereadable(latest) == 1

    local shared = require("plugins.dadbod.shared")

    if has_valid_result then
      if not dbout_win then
        if not shared.is_user_closed(sql_path) then
          vim.schedule(function()
            local cur_buf = vim.api.nvim_get_current_buf()
            local cur_path = vim.api.nvim_buf_get_name(cur_buf)
            if cur_path == sql_path then
              local exists = false
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
                if ft == "dbout" or ft == "explain" then
                  exists = true
                  break
                end
              end
              if not exists then
                show_result_in_window(latest, subdir, sql_path)
              end
            end
          end)
        end
      else
        local current = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dbout_win))
        if current ~= latest then
          local current_filename = vim.fn.fnamemodify(current, ":t")
          if current_filename:match("^Result_%d+_") then
            local target_buf = vim.fn.bufnr(latest)
            if target_buf == -1 then
              target_buf = vim.fn.bufadd(latest)
              vim.fn.bufload(target_buf)
            end
            if sql_path and sql_path ~= "" then
              vim.b[target_buf].sql_source_path = sql_path
            end
            shared.set_win_buf_safely(dbout_win, target_buf)
            require("plugins.dadbod.history").last_dbout_dir = subdir
          end
        end
      end
    elseif not has_valid_result and dbout_win then
      -- Buffer has no results: close dbout window if open so it never displays leftover results from other files
      pcall(vim.api.nvim_win_close, dbout_win, true)
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
    if win and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      if ft == "dbout" or ft == "explain" then
        local sql_src = vim.b[buf].sql_source_path
        if sql_src and sql_src ~= "" then
          local dbout_count = 0
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if w ~= win then
              local w_ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
              if w_ft == "dbout" or w_ft == "explain" then
                dbout_count = dbout_count + 1
              end
            end
          end
          if dbout_count == 0 then
            shared.set_user_closed(sql_src, true)
          end
        end
      end
    end
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
  setup_dbout_buffer()
end

return M
