-- lua/plugins/dadbod/format.lua
-- Grid table formatting, column width truncation, and fast navigation jumps.

local M = {}

--- Get the visual display width of a string in terminal columns
local function display_width(str)
  return vim.fn.strdisplaywidth(str)
end

--- Truncate a string to a maximum display width, appending "..." if truncated
local function truncate_by_width(str, max_width)
  if display_width(str) <= max_width then
    return str
  end
  local target_w = max_width - 3
  if target_w <= 0 then
    return "..."
  end
  local len = vim.fn.strchars(str)
  local low = 0
  local high = len
  local best_idx = 0
  while low <= high do
    local mid = math.floor((low + high) / 2)
    local sub = vim.fn.strcharpart(str, 0, mid)
    if display_width(sub) <= target_w then
      best_idx = mid
      low = mid + 1
    else
      high = mid - 1
    end
  end
  return vim.fn.strcharpart(str, 0, best_idx) .. "..."
end

--- Truncate each column in the SQL results buffer to a fixed max width (e.g. 40 chars)
--- and cache the original un-truncated lines in a buffer-local variable.
--- @param bufnr integer
function M.truncate_dbout_buffer(bufnr)
  if vim.b[bufnr].dbout_truncated then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines < 2 then
    return
  end

  -- Check if this is a tabular database output (has divider line with - and + or |)
  local divider = lines[2]
  if not divider:match("^[-+%s]+$") then
    return
  end

  -- Cache the original untruncated lines in buffer local variable
  vim.b[bufnr].original_lines = lines

  local max_col_width = 40 -- Max visible column width

  local table_rows = {}
  local col_count = 0
  local has_split = false

  for idx, line in ipairs(lines) do
    if idx ~= 2 then
      local cols = {}
      if line:match("|") then
        has_split = true
        for col in string.gmatch(line .. "|", "(.-)|") do
          table.insert(cols, col)
        end
      else
        table.insert(cols, line)
      end

      if idx == 1 then
        col_count = #cols
      end

      -- Trim and truncate each cell
      for i = 1, #cols do
        local trimmed = vim.trim(cols[i])
        cols[i] = truncate_by_width(trimmed, max_col_width)
      end
      table.insert(table_rows, { idx = idx, cols = cols, is_table = true })
    else
      table.insert(table_rows, { idx = idx, is_divider = true })
    end
  end

  -- Calculate the max width for each column after truncation
  local col_widths = {}
  for i = 1, col_count do
    col_widths[i] = 0
  end

  for _, row in ipairs(table_rows) do
    if row.is_table then
      for i = 1, col_count do
        local cell = row.cols[i] or ""
        local cell_w = display_width(cell)
        if cell_w > col_widths[i] then
          col_widths[i] = cell_w
        end
      end
    end
  end

  -- Rebuild the lines
  local new_lines = {}
  for idx = 1, #lines do
    local row = table_rows[idx]
    if row.is_divider then
      if has_split then
        local parts = {}
        for i = 1, col_count do
          table.insert(parts, string.rep("-", col_widths[i] + 2))
        end
        table.insert(new_lines, table.concat(parts, "+"))
      else
        table.insert(new_lines, string.rep("-", col_widths[1] or 20))
      end
    elseif row.is_table then
      local original_line = lines[idx] or ""
      if original_line:match("^%s*%(") or original_line == "" then
        table.insert(new_lines, original_line)
      else
        local parts = {}
        for i = 1, col_count do
          local cell = row.cols[i] or ""
          local padding = col_widths[i] - display_width(cell)
          table.insert(parts, " " .. cell .. string.rep(" ", padding) .. " ")
        end
        if has_split then
          table.insert(new_lines, table.concat(parts, "|"))
        else
          table.insert(new_lines, parts[1] or "")
        end
      end
    end
  end

  -- Replace buffer lines safely by temporarily enabling modifiable
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  vim.bo[bufnr].modifiable = was_modifiable
  vim.bo[bufnr].modified = false
  vim.b[bufnr].dbout_truncated = true
end

--- Toggle between fixed-width column truncation and full original width
--- @param bufnr integer|nil
function M.toggle_dbout_column_width(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local truncated = vim.b[bufnr].dbout_truncated
  if truncated then
    local original_lines = vim.b[bufnr].original_lines
    if not original_lines then
      require("core.utils").notify("db_no_cached_data")
      return
    end
    local was_modifiable = vim.bo[bufnr].modifiable
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_lines)
    vim.bo[bufnr].modifiable = was_modifiable
    vim.bo[bufnr].modified = false
    vim.b[bufnr].dbout_truncated = false
    require("core.utils").notify("db_fixed_width_disabled")
  else
    M.truncate_dbout_buffer(bufnr)
    if vim.b[bufnr].dbout_truncated then
      require("core.utils").notify("db_fixed_width_enabled")
    end
  end
end

--- Jump column left or right
--- @param direction "next" | "prev"
function M.jump_column(direction)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]
  local line = vim.api.nvim_get_current_line()

  -- Find all pipe positions, prepending -2 to represent start of first column
  local pipes = { -2 }
  for i = 1, #line do
    if string.sub(line, i, i) == "|" then
      table.insert(pipes, i - 1)
    end
  end

  if #pipes <= 1 then
    return
  end

  local target_col = nil
  if direction == "next" then
    for _, pipe_col in ipairs(pipes) do
      if pipe_col > col then
        target_col = pipe_col + 2
        break
      end
    end
  else -- prev
    for i = #pipes, 1, -1 do
      local pipe_col = pipes[i]
      if pipe_col < col - 2 then
        target_col = pipe_col + 2
        break
      end
    end
  end

  if target_col then
    target_col = math.min(target_col, #line)
    vim.api.nvim_win_set_cursor(0, { row, target_col })
  end
end

return M
