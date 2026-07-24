-- Pure SQL text parsing shared by Dadbod query execution and completion.

local M = {}

--- Return whether a line is empty or begins a SQL comment block.
--- @param line string
--- @return boolean
function M.is_empty_or_comment(line)
  local trimmed = vim.trim(line)
  return trimmed == "" or vim.startswith(trimmed, "--") or vim.startswith(trimmed, "/*")
end

--- Return whether a line ends with a semicolon after trimming whitespace.
--- @param line string
--- @return boolean
function M.has_valid_semicolon(line)
  local trimmed = vim.trim(line)
  return vim.endswith(trimmed, ";")
end

--- Find the logical SQL block surrounding a one-based cursor row.
--- @param total_lines integer
--- @param cursor_row integer
--- @param get_line fun(line: integer): string|nil
--- @return integer start_line
--- @return integer end_line
function M.find_block(total_lines, cursor_row, get_line)
  local start_line = cursor_row
  while start_line > 1 do
    local prev_line = get_line(start_line - 1)
    if not prev_line or M.is_empty_or_comment(prev_line) or M.has_valid_semicolon(prev_line) then
      break
    end
    start_line = start_line - 1
  end

  local end_line = cursor_row
  while end_line < total_lines do
    local curr_line = get_line(end_line)
    if curr_line and M.has_valid_semicolon(curr_line) then
      break
    end
    local next_line = get_line(end_line + 1)
    if not next_line or M.is_empty_or_comment(next_line) then
      break
    end
    end_line = end_line + 1
  end

  return start_line, end_line
end

--- Resolve a table alias within SQL lines.
--- @param lines string[]
--- @param alias string
--- @return string
function M.resolve_alias(lines, alias)
  local content = table.concat(lines, "\n")

  for tbl, al in content:gmatch("([%w_\"][%w_%.%-\"]*)%s+[Aa][Ss]%s+([%w_]+)") do
    if al == alias then return tbl end
  end

  for tbl, al in content:gmatch("[Ff][Rr][Oo][Mm]%s+([%w_\"][%w_%.%-\"]*)%s+([%w_]+)") do
    if al == alias then return tbl end
  end

  for tbl, al in content:gmatch("[Jj][Oo][Ii][Nn]%s+([%w_\"][%w_%.%-\"]*)%s+([%w_]+)") do
    if al == alias then return tbl end
  end

  return alias
end

--- Split "schema.table" into schema and table identifiers.
--- @param table_name string
--- @return string|nil, string|nil
function M.split_table_name(table_name)
  if not table_name then return nil, nil end

  local function strip_quotes(str)
    if not str then return nil end
    return str:gsub('^"', ''):gsub('"$', '')
  end

  if table_name:find(".", 1, true) then
    local parts = vim.split(table_name, ".", { plain = true })
    return strip_quotes(parts[1]), strip_quotes(parts[2])
  end
  return nil, strip_quotes(table_name)
end

return M
