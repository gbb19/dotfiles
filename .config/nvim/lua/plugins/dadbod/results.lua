-- Result path resolution and on-disk result discovery.

local M = {}
local state = require("plugins.dadbod.state")

--- Get the stable, absolute query result subdirectory for an SQL file.
--- @param sql_path string
--- @param bufnr integer|nil
--- @return string|nil
function M.get_subdir_for_sql(sql_path, bufnr)
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
  return safe_service
    and (base_dir .. "/" .. safe_service .. "/" .. safe_sql_key)
    or (base_dir .. "/" .. safe_sql_key)
end

--- Return the newest numbered result in a directory.
--- @param subdir string|nil
--- @return string|nil
function M.get_latest_result(subdir)
  if not subdir or subdir == "" then return nil end
  local files = vim.fn.glob(subdir .. "/Result_*.dbout", true, true)
  local best_counter, best_path = -1, nil
  for _, file in ipairs(files) do
    if vim.fn.filereadable(file) == 1 then
      local counter = tonumber(vim.fn.fnamemodify(file, ":t"):match("^Result_(%d+)_"))
      if counter and counter > best_counter then
        best_counter, best_path = counter, file
      end
    end
  end
  return best_path
end

--- Find the SQL source whose result directory contains a dbout path.
--- @param dbout_path string
--- @return string|nil
function M.find_sql_path_for_dbout(dbout_path)
  if not dbout_path or dbout_path == "" then return nil end
  local dbout_dir = vim.fn.fnamemodify(dbout_path, ":h")

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "sql" then
      local sql_path = vim.api.nvim_buf_get_name(bufnr)
      if sql_path and sql_path ~= "" and M.get_subdir_for_sql(sql_path, bufnr) == dbout_dir then
        return sql_path
      end
    end
  end
  return nil
end

--- Safely set a buffer in a window while preserving winfixbuf behavior.
--- @param win integer
--- @param target_buf integer
--- @return boolean
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
    local filetype = vim.bo[target_buf].filetype
    if filetype == "dbout" or filetype == "explain" or was_fixed then
      vim.wo[win].winfixbuf = true
    end
  end
  return ok
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

--- Open a result in a reusable dbout window while preserving editor focus.
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
    local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if filetype == "dbout" or filetype == "explain" then
      M.set_win_buf_safely(win, target_buf)
      if vim.api.nvim_win_is_valid(orig_win) then
        vim.api.nvim_set_current_win(orig_win)
      end
      return
    end
  end

  vim.cmd("vertical split")
  M.set_win_buf_safely(vim.api.nvim_get_current_win(), target_buf)

  if vim.api.nvim_win_is_valid(orig_win) then
    vim.api.nvim_set_current_win(orig_win)
  end
end

return M
