-- Result path resolution and on-disk result discovery.

local M = {}

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

return M
