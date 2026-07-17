-- lua/plugins/dadbod/history.lua
-- Disk-based query result history manager, status index popups, and cleanup.

local M = {}

M.last_dbout_dir = nil

--- Get the stable query result subdirectory path for a given SQL file (internal helper)
local function get_subdir_for_sql(sql_path, bufnr)
  if not sql_path or sql_path == "" then return nil end

  local sql_key
  local db_file = vim.fs.find(".db", {
    upward = true,
    path = vim.fs.dirname(sql_path),
  })[1]
  if db_file then
    local db_dir = vim.fn.fnamemodify(db_file, ":h")
    if vim.startswith(sql_path, db_dir .. "/") then
      local rel = sql_path:sub(#db_dir + 2)
      sql_key = rel:gsub("%.sql$", ""):gsub("[/\\]", "_")
    end
  end
  sql_key = sql_key or vim.fn.fnamemodify(sql_path, ":t:r")

  local target_buf = bufnr or vim.fn.bufnr(sql_path)
  local db_service = ""
  if target_buf and target_buf > 0 and vim.api.nvim_buf_is_valid(target_buf) then
    db_service = vim.b[target_buf].db_service or ""
  elseif target_buf == 0 then
    db_service = vim.b.db_service or ""
  end

  local safe_service = db_service ~= "" and db_service:gsub("[^%w%-_]", "_") or nil
  local safe_sql_key = sql_key:gsub("[^%w%-_]", "_")

  local base_dir = "/tmp/dadbodout_" .. vim.fn.getpid()
  local subdir = safe_service
    and (base_dir .. "/" .. safe_service .. "/" .. safe_sql_key)
    or  (base_dir .. "/" .. safe_sql_key)
  return subdir
end

--- Helper to retrieve the list of Result_*.dbout files on disk in chronological order
--- @param current_path string|nil
--- @return table[]  list of { path, filename, counter }
function M.get_result_files(current_path)
  local dir
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  if ft == "dbout" and current_path and current_path ~= "" then
    dir = vim.fn.fnamemodify(current_path, ":h")
  elseif ft == "sql" then
    local sql_path = vim.api.nvim_buf_get_name(bufnr)
    dir = get_subdir_for_sql(sql_path, bufnr)
  else
    dir = M.last_dbout_dir
  end

  if not dir or dir == "" then
    return {}
  end

  local files = vim.fn.glob(dir .. "/Result_*.dbout", true, true)
  local result_files = {}
  for _, file in ipairs(files) do
    local filename = vim.fn.fnamemodify(file, ":t")
    local counter = tonumber(filename:match("^Result_(%d+)_"))
    if counter then
      table.insert(result_files, { path = file, filename = filename, counter = counter })
    end
  end
  table.sort(result_files, function(a, b) return a.counter < b.counter end)
  return result_files
end

local history_win = nil
local history_buf = nil

--- Show an elegant rounded float popup listing all history items and highlighting the current one
--- @param result_files table[]
--- @param current_path string
function M.show_history_popup(result_files, current_path)
  if #result_files == 0 then return end

  -- Close existing popup window if open
  if history_win and vim.api.nvim_win_is_valid(history_win) then
    vim.api.nvim_win_close(history_win, true)
  end

  -- Create history scratch buffer if needed
  if not history_buf or not vim.api.nvim_buf_is_valid(history_buf) then
    history_buf = vim.api.nvim_create_buf(false, true)
  end

  local lines = {}
  local current_idx = 1
  for idx, item in ipairs(result_files) do
    local display_name = item.filename:gsub("%.dbout$", ""):gsub("^Result_%d+_", ""):gsub("_", " ")
    if item.path == current_path then
      current_idx = idx
      table.insert(lines, string.format("➔ [%d] %s", item.counter, display_name))
    else
      table.insert(lines, string.format("  [%d] %s", item.counter, display_name))
    end
  end

  vim.api.nvim_buf_set_lines(history_buf, 0, -1, false, lines)

  -- Calculate dimensions
  local max_len = 30
  for _, line in ipairs(lines) do
    max_len = math.max(max_len, #line)
  end
  local width = max_len + 4
  local height = #lines

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  local row = editor_height - height - 4 -- above statusline
  local col = editor_width - width - 4   -- bottom-right

  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Query History ",
    title_pos = "center",
  }

  history_win = vim.api.nvim_open_win(history_buf, false, opts)

  local ns_id = vim.api.nvim_create_namespace("dbout_history_popup")
  vim.api.nvim_buf_clear_namespace(history_buf, ns_id, 0, -1)
  vim.api.nvim_buf_add_highlight(history_buf, ns_id, "CursorLine", current_idx - 1, 0, -1)

  -- Auto-close timer (2.5 seconds)
  local timer = vim.loop.new_timer()
  timer:start(2500, 0, vim.schedule_wrap(function()
    if history_win and vim.api.nvim_win_is_valid(history_win) then
      vim.api.nvim_win_close(history_win, true)
    end
    if not timer:is_closing() then
      timer:close()
    end
  end))
end

--- Delete the current result file on disk, close its buffer, and switch to next/prev
function M.delete_current_result()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "dbout" then
    vim.cmd("close")
    return
  end

  local current_path = vim.api.nvim_buf_get_name(bufnr)
  local result_files = M.get_result_files(current_path)

  local current_idx = nil
  for idx, item in ipairs(result_files) do
    if item.path == current_path then
      current_idx = idx
      break
    end
  end

  local target_buf = nil
  local sql_path = vim.b[bufnr].sql_source_path
  if current_idx and #result_files > 1 then
    local target_item = result_files[current_idx + 1] or result_files[current_idx - 1]
    if target_item then
      local tb = vim.fn.bufnr(target_item.path)
      if tb == -1 then
        target_buf = vim.fn.bufadd(target_item.path)
      else
        target_buf = tb
      end
      if sql_path then
        vim.b[target_buf].sql_source_path = sql_path
      end
    end
  end

  local shared = require("plugins.dadbod.shared")
  shared.is_deleting_result = true

  -- Delete physical file on disk if path exists
  if current_path and current_path ~= "" then
    pcall(os.remove, current_path)
  end

  -- Update cache in init.lua so deleted files are invalidated
  if sql_path then
    local new_last = (target_buf and vim.api.nvim_buf_is_valid(target_buf)) and vim.api.nvim_buf_get_name(target_buf) or nil
    require("plugins.dadbod.init").update_last_result(sql_path, new_last)
    if not new_last then
      shared.set_user_closed(sql_path, true)
    end
  end

  -- Switch buffer or close window if no remaining results for this SQL buffer
  local win = vim.api.nvim_get_current_win()
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    shared.set_win_buf_safely(win, target_buf)
  else
    pcall(vim.cmd, "close")
  end

  -- Wipe out buffer
  pcall(vim.cmd, "bwipeout! " .. bufnr)
  shared.is_deleting_result = false
  require("core.utils").notify("db_deleted_result")
end

--- Interactively choose and switch to a query result from disk history
function M.switch_result_history()
  local current_path = vim.api.nvim_buf_get_name(0)
  local result_files = M.get_result_files(current_path)

  if #result_files == 0 then
    require("core.utils").notify("db_no_results_in_history")
    return
  end

  local items = {}
  local choice_to_path = {}
  for _, item in ipairs(result_files) do
    local display_name = item.filename:gsub("%.dbout$", ""):gsub("^Result_%d+_", ""):gsub("_", " ")
    local menu_item = string.format("[%d] %s", item.counter, display_name)
    table.insert(items, menu_item)
    choice_to_path[menu_item] = item.path
  end

  vim.ui.select(items, {
    prompt = "Select Query Result:",
  }, function(choice)
    if not choice then return end
    local target_path = choice_to_path[choice]
    if target_path then
      local cur_buf = vim.api.nvim_get_current_buf()
      local cur_sql_path = vim.b[cur_buf].sql_source_path
      if vim.bo[cur_buf].filetype == "sql" then
        cur_sql_path = vim.api.nvim_buf_get_name(cur_buf)
      end

      local target_buf = vim.fn.bufnr(target_path)
      if target_buf == -1 then
        target_buf = vim.fn.bufadd(target_path)
      end

      if cur_sql_path then
        vim.b[target_buf].sql_source_path = cur_sql_path
      end

      -- First, check if target_buf is already open in any window
      local target_wins = vim.fn.win_findbuf(target_buf)
      if #target_wins > 0 then
        vim.api.nvim_set_current_win(target_wins[1])
        return
      end

      -- If not, find if there is ANY window currently displaying a dbout buffer
      local dbout_win = nil
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "dbout" then
          dbout_win = win
          break
        end
      end

      if dbout_win then
        require("plugins.dadbod.shared").set_win_buf_safely(dbout_win, target_buf)
        vim.api.nvim_set_current_win(dbout_win)
      else
        vim.cmd("vertical split")
        local new_win = vim.api.nvim_get_current_win()
        require("plugins.dadbod.shared").set_win_buf_safely(new_win, target_buf)
      end
    end
  end)
end

--- Clear all result files in history from disk and wipeout all associated Neovim buffers
function M.clear_all_results()
  local current_path = vim.api.nvim_buf_get_name(0)
  local result_files = M.get_result_files(current_path)

  if #result_files == 0 then
    require("core.utils").notify("db_no_results_to_clear")
    return
  end

  vim.ui.select({ "Yes, clear all history", "No, cancel" }, {
    prompt = string.format("Are you sure you want to delete all %d query results?", #result_files),
  }, function(choice)
    if choice ~= "Yes, clear all history" then return end

    -- Close any open dbout windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "dbout" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end

    -- Delete physical files and wipe out Neovim buffers
    local count = 0
    for _, item in ipairs(result_files) do
      os.remove(item.path)
      count = count + 1

      local bufnr = vim.fn.bufnr(item.path)
      if bufnr ~= -1 then
        vim.cmd("bwipeout! " .. bufnr)
      end
    end

    require("core.utils").notify("db_cleared_all_results", string.format("(%d results)", count))
  end)
end

return M
