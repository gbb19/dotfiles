local M = {}
local cached_context
local last_tick
local last_cursor

function M.detect_sql_context(bufnr, row, col, line)
  local line_before = line:sub(1, col)
  if line_before:match("[%w_%-\"]+%.[%w_]*$") then return "column" end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  lines[#lines] = line_before
  local text = table.concat(lines, " "):gsub("%-%-[^\n]*", ""):gsub("/%*.-%*/", ""):gsub("%s+", " ")
  local last_keyword
  for word in text:gmatch("[%w_]+") do
    local upper_word = word:upper()
    if upper_word == "FROM" or upper_word == "JOIN" or upper_word == "UPDATE" or upper_word == "INTO" or upper_word == "TABLE" then
      last_keyword = "table"
    elseif upper_word == "SELECT" or upper_word == "WHERE" or upper_word == "SET" or upper_word == "AND" or upper_word == "OR" or upper_word == "ON" or upper_word == "BY" then
      last_keyword = "column"
    end
  end
  return last_keyword or "keyword"
end

function M.get_sql_context_cached()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "sql" then return "keyword" end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local tick = vim.b[bufnr].changedtick
  if last_tick == tick and last_cursor and last_cursor[1] == cursor[1] and last_cursor[2] == cursor[2] then
    return cached_context
  end

  last_tick = tick
  last_cursor = cursor
  cached_context = M.detect_sql_context(
    bufnr,
    cursor[1],
    cursor[2],
    vim.api.nvim_get_current_line()
  )
  return cached_context
end

return M
