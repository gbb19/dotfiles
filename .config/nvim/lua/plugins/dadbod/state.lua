local M = {}

---@type table<string, any>
M.query_handles = {}

---@type table<string, integer>
M.sql_source_by_output = {}

---@type table<string, string>
M.last_result_by_sql = {}

---@type string|nil
M.last_dbout_dir = nil

---@type table<string, boolean>
M.user_closed_by_sql = {}

M.is_deleting_result = false

---Update or invalidate the cached last result for an SQL source file.
---@param sql_path string|nil
---@param result_path string|nil
function M.update_last_result(sql_path, result_path)
  if not sql_path or sql_path == "" then
    return
  end
  if result_path and result_path ~= "" and vim.fn.filereadable(result_path) == 1 then
    M.last_result_by_sql[sql_path] = result_path
  else
    M.last_result_by_sql[sql_path] = nil
  end
end

return M
