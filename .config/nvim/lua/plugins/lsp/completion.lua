local M = {}

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

return M
