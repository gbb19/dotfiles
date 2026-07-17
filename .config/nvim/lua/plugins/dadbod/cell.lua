-- lua/plugins/dadbod/cell.lua
-- Inspecting truncated grid cells and managing cell-based text objects.

local M = {}

-- Local cache-warn helper for CLI commands
local warned_executables = {}
local function ensure_executable(cmd, msg_key)
  if vim.fn.executable(cmd) ~= 1 then
    if not warned_executables[cmd] then
      require("core.utils").notify(msg_key)
      warned_executables[cmd] = true
    end
    return false
  end
  return true
end

--- Inspect the full value of the cell under cursor in a rounded floating window
function M.show_cell_detail()
  local bufnr = vim.api.nvim_get_current_buf()
  local original_lines = vim.b[bufnr].original_lines
  if not original_lines then
    require("core.utils").notify("db_no_cached_data")
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2] -- 0-indexed byte column

  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line or line:match("^[-+%s]+$") or line:match("^%s*%(") then
    return
  end -- ignore divider and footer

  -- Find which column the cursor is currently in by counting '|' characters
  local col_idx = 1
  for i = 1, col do
    if string.sub(line, i, i) == "|" then
      col_idx = col_idx + 1
    end
  end

  -- Get the original un-truncated line
  local orig_line = original_lines[row]
  if not orig_line then
    return
  end

  -- Extract the cell value from the original line
  local cells = {}
  if orig_line:match("|") then
    for cell in string.gmatch(orig_line .. "|", "(.-)|") do
      table.insert(cells, vim.trim(cell))
    end
  else
    table.insert(cells, vim.trim(orig_line))
  end

  local cell_value = cells[col_idx]
  if not cell_value or cell_value == "" then
    require("core.utils").notify("db_empty_cell")
    return
  end

  -- If it's a JSON string, pretty-print it using jq
  local display_lines = {}
  local is_json = false
  if
    (cell_value:sub(1, 1) == "{" and cell_value:sub(-1, -1) == "}")
    or (cell_value:sub(1, 1) == "[" and cell_value:sub(-1, -1) == "]")
  then
    local ok = pcall(vim.json.decode, cell_value)
    if ok then
      is_json = true
      local formatted = nil
      if ensure_executable("jq", "db_jq_missing") then
        formatted = vim.fn.system("jq '.'", cell_value)
      end
      if formatted and vim.v.shell_error == 0 and formatted ~= "" then
        for l in string.gmatch(formatted, "[^\r\n]+") do
          table.insert(display_lines, l)
        end
      else
        table.insert(display_lines, cell_value)
      end
    else
      table.insert(display_lines, cell_value)
    end
  else
    -- Split normal text by newlines if any
    for l in string.gmatch(cell_value, "[^\r\n]+") do
      table.insert(display_lines, l)
    end
  end

  -- Calculate dimensions for the floating window
  local max_w = math.floor(vim.o.columns * 0.8)
  local max_h = math.floor(vim.o.lines * 0.8)
  local width = 0
  for _, l in ipairs(display_lines) do
    local w = vim.fn.strdisplaywidth(l)
    if w > width then
      width = w
    end
  end

  local title = " Cell Detail (y: copy, q: close) "
  local title_w = vim.fn.strdisplaywidth(title)
  width = math.max(25, title_w + 2, width)
  width = math.min(width, max_w)
  local height = math.max(1, math.min(#display_lines, max_h))

  local row_pos = math.floor((vim.o.lines - height) / 2)
  local col_pos = math.floor((vim.o.columns - width) / 2)

  local parent_win = vim.api.nvim_get_current_win()

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, display_lines)
  vim.bo[float_buf].bufhidden = "wipe"
  if is_json then
    vim.bo[float_buf].filetype = "json"
  end

  local win = vim.api.nvim_open_win(float_buf, true, {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  -- Keymaps for the cell detail window
  local map_opts = { buffer = float_buf, silent = true }
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(parent_win) then
      vim.api.nvim_set_current_win(parent_win)
    end
  end, map_opts)

  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", cell_value)
    require("core.utils").notify("db_copied_cell")
  end, map_opts)
end

--- Helper to select current cell visually (enables ic and ac text objects)
function M.select_cell(around)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local col = cursor[2]

  local left_pipe = 0
  local right_pipe = #line + 1

  for i = col, 1, -1 do
    if string.sub(line, i, i) == "|" then
      left_pipe = i
      break
    end
  end

  for i = col + 1, #line do
    if string.sub(line, i, i) == "|" then
      right_pipe = i
      break
    end
  end

  local start_col = left_pipe + 1
  local end_col = right_pipe - 1

  if not around then
    while start_col < end_col and string.sub(line, start_col, start_col):match("%s") do
      start_col = start_col + 1
    end
    while end_col > start_col and string.sub(line, end_col, end_col):match("%s") do
      end_col = end_col - 1
    end
  end

  start_col = start_col - 1
  end_col = end_col - 1

  if start_col <= end_col and start_col >= 0 then
    vim.api.nvim_win_set_cursor(0, { cursor[1], start_col })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { cursor[1], end_col })
  end
end

--- Helper to yank original full cell value directly to clipboard (respects truncation)
function M.yank_cell(around)
  local bufnr = vim.api.nvim_get_current_buf()
  local original_lines = vim.b[bufnr].original_lines
  if not original_lines then
    require("core.utils").notify("db_no_cached_data")
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  if not line or line:match("^[-+%s]+$") or line:match("^%s*%(") then
    return
  end

  local col_idx = 1
  for i = 1, col do
    if string.sub(line, i, i) == "|" then
      col_idx = col_idx + 1
    end
  end

  local orig_line = original_lines[row]
  if not orig_line then
    return
  end

  local cells = {}
  if orig_line:match("|") then
    for cell in string.gmatch(orig_line .. "|", "(.-)|") do
      table.insert(cells, vim.trim(cell))
    end
  else
    table.insert(cells, vim.trim(orig_line))
  end

  local cell_value = cells[col_idx]
  if not cell_value then
    return
  end

  local truncated_msg = cell_value
  if vim.fn.strdisplaywidth(truncated_msg) > 30 then
    truncated_msg = vim.fn.strcharpart(truncated_msg, 0, 27) .. "..."
  end

  -- Detect and pretty-print JSON using jq if applicable
  local is_formatted_json = false
  if
    (cell_value:sub(1, 1) == "{" and cell_value:sub(-1, -1) == "}")
    or (cell_value:sub(1, 1) == "[" and cell_value:sub(-1, -1) == "]")
  then
    local ok = pcall(vim.json.decode, cell_value)
    if ok then
      local formatted = nil
      if ensure_executable("jq", "db_jq_missing") then
        formatted = vim.fn.system("jq '.'", cell_value)
      end
      if formatted and vim.v.shell_error == 0 and formatted ~= "" then
        cell_value = formatted
        is_formatted_json = true
      end
    end
  end

  vim.fn.setreg("+", cell_value)
  vim.fn.setreg('"', cell_value)

  if is_formatted_json then
    require("core.utils").notify("db_yanked_json", truncated_msg)
  else
    require("core.utils").notify("db_yanked_cell", truncated_msg)
  end
end

--- Extract column values under cursor or visual selection and copy as SQL IN clause
--- e.g. status IN ('PENDING', 'APPROVED', 'REJECTED') or id IN (1, 2, 3)
function M.yank_in_clause()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "dbout" then return end

  -- Exit visual mode if currently in visual mode to update '< and '> marks
  local mode = vim.fn.mode()
  local is_visual = mode:match("[vV\16]") ~= nil
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local col = cursor[2]

  local start_row, end_row
  if is_visual then
    start_row = vim.fn.line("'<")
    end_row = vim.fn.line("'>")
  else
    start_row = cursor[1]
    end_row = cursor[1]
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines < 3 then return end

  -- Determine column index under cursor from current line
  local cur_line = lines[cursor[1]] or lines[1]
  local col_idx = 1
  for i = 1, col do
    if string.sub(cur_line, i, i) == "|" then
      col_idx = col_idx + 1
    end
  end

  -- Parse header row (line 1) to get column name
  local header_line = lines[1]
  local col_names = {}
  if header_line:match("|") then
    for header in string.gmatch(header_line .. "|", "(.-)|") do
      table.insert(col_names, vim.trim(header))
    end
  else
    table.insert(col_names, vim.trim(header_line))
  end
  local col_name = col_names[col_idx] or ""

  -- Get cached original un-truncated lines if available
  local original_lines = vim.b[bufnr].original_lines or lines

  local values = {}
  local seen = {}

  for row = start_row, end_row do
    local raw_line = original_lines[row] or lines[row]
    if raw_line and not raw_line:match("^[-+%s]+$") and not raw_line:match("^%s*%(") then
      local cells = {}
      if raw_line:match("|") then
        for cell in string.gmatch(raw_line .. "|", "(.-)|") do
          table.insert(cells, vim.trim(cell))
        end
      else
        table.insert(cells, vim.trim(raw_line))
      end

      local val = cells[col_idx]
      if val and val ~= "" and row > 1 then -- skip header row itself if selected
        if not seen[val] then
          seen[val] = true
          table.insert(values, val)
        end
      end
    end
  end

  if #values == 0 then
    require("core.utils").notify("db_empty_cell")
    return
  end

  -- Format values for SQL IN clause
  local formatted_items = {}
  for _, val in ipairs(values) do
    if val:upper() == "NULL" then
      table.insert(formatted_items, "NULL")
    elseif val:match("^%-?%d+%.?%d*$") or val:lower() == "true" or val:lower() == "false" then
      table.insert(formatted_items, val)
    else
      local escaped = val:gsub("'", "''")
      table.insert(formatted_items, "'" .. escaped .. "'")
    end
  end

  local in_clause
  if col_name ~= "" then
    in_clause = col_name .. " IN (" .. table.concat(formatted_items, ", ") .. ")"
  else
    in_clause = "IN (" .. table.concat(formatted_items, ", ") .. ")"
  end

  vim.fn.setreg("+", in_clause)
  vim.fn.setreg('"', in_clause)

  local truncated_display = in_clause
  if vim.fn.strdisplaywidth(truncated_display) > 50 then
    truncated_display = vim.fn.strcharpart(truncated_display, 0, 47) .. "..."
  end

  require("core.utils").notify("db_copied_in_clause", truncated_display)
end

--- Extract rows under cursor or visual selection and copy as SQL INSERT statements
--- e.g. INSERT INTO users (id, name, status) VALUES (101, 'Alice', 'ACTIVE');
function M.yank_insert_statements()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "dbout" then return end

  -- Exit visual mode if active to update '< and '> marks
  local mode = vim.fn.mode()
  local is_visual = mode:match("[vV\16]") ~= nil
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_row, end_row
  if is_visual then
    start_row = vim.fn.line("'<")
    end_row = vim.fn.line("'>")
  else
    start_row = cursor[1]
    end_row = cursor[1]
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines < 3 then return end

  -- Parse header row (line 1) to get column names
  local header_line = lines[1]
  local col_names = {}
  if header_line:match("|") then
    for header in string.gmatch(header_line .. "|", "(.-)|") do
      local trimmed = vim.trim(header)
      if trimmed ~= "" then
        table.insert(col_names, trimmed)
      end
    end
  else
    table.insert(col_names, vim.trim(header_line))
  end

  if #col_names == 0 then return end

  -- Try to deduce table name from sql_source_path or filename
  local table_name = "table_name"
  local sql_path = vim.b[bufnr].sql_source_path
  if sql_path and vim.fn.filereadable(sql_path) == 1 then
    local sql_lines = vim.fn.readfile(sql_path)
    local sql_content = table.concat(sql_lines, "\n")
    local from_tbl = sql_content:match("[Ff][Rr][Oo][Mm]%s+([%w_%.]+)")
    if from_tbl then
      local parts = vim.split(from_tbl, ".", { plain = true })
      table_name = parts[#parts]:gsub('^"', ''):gsub('"$', '')
    end
  end

  if table_name == "table_name" then
    local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
    local from_fn = fname:match("[Ff][Rr][Oo][Mm]_([%w_]+)") or fname:match("Result_%d+_(%w+)")
    if from_fn and from_fn:lower() ~= "query" and from_fn:lower() ~= "select" then
      table_name = from_fn
    end
  end

  -- Retrieve un-truncated original lines if available
  local original_lines = vim.b[bufnr].original_lines or lines

  local value_tuples = {}

  for row = start_row, end_row do
    local raw_line = original_lines[row] or lines[row]
    if raw_line and not raw_line:match("^[-+%s]+$") and not raw_line:match("^%s*%(") and row > 1 then
      local cells = {}
      if raw_line:match("|") then
        for cell in string.gmatch(raw_line .. "|", "(.-)|") do
          table.insert(cells, vim.trim(cell))
        end
      else
        table.insert(cells, vim.trim(raw_line))
      end

      if #cells > 0 then
        local formatted_cells = {}
        for i = 1, #col_names do
          local val = cells[i] or ""
          if val == "" or val:upper() == "NULL" then
            table.insert(formatted_cells, "NULL")
          elseif val:match("^%-?%d+%.?%d*$") or val:lower() == "true" or val:lower() == "false" then
            table.insert(formatted_cells, val)
          else
            local escaped = val:gsub("'", "''")
            table.insert(formatted_cells, "'" .. escaped .. "'")
          end
        end
        table.insert(value_tuples, "  (" .. table.concat(formatted_cells, ", ") .. ")")
      end
    end
  end

  if #value_tuples == 0 then
    require("core.utils").notify("db_empty_cell")
    return
  end

  local cols_str = table.concat(col_names, ", ")
  local insert_sql = string.format("INSERT INTO %s (%s) VALUES\n%s;", table_name, cols_str, table.concat(value_tuples, ",\n"))

  vim.fn.setreg("+", insert_sql)
  vim.fn.setreg('"', insert_sql)

  require("core.utils").notify("db_copied_insert_statement", string.format("%d row(s) into %s", #value_tuples, table_name))
end

--- Extract rows under cursor or visual selection in dbout buffer and copy as CSV
function M.yank_csv()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "dbout" then return end

  -- Exit visual mode if active to update '< and '> marks
  local mode = vim.fn.mode()
  local is_visual = mode:match("[vV\16]") ~= nil
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", false)
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_row, end_row
  if is_visual then
    start_row = vim.fn.line("'<")
    end_row = vim.fn.line("'>")
  else
    start_row = cursor[1]
    end_row = cursor[1]
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines < 3 then return end

  -- Parse header row (line 1) to get column names
  local header_line = lines[1]
  local col_names = {}
  if header_line:match("|") then
    for header in string.gmatch(header_line .. "|", "(.-)|") do
      local trimmed = vim.trim(header)
      if trimmed ~= "" then
        table.insert(col_names, trimmed)
      end
    end
  else
    table.insert(col_names, vim.trim(header_line))
  end

  if #col_names == 0 then return end

  local function format_csv_field(val)
    if not val then return "" end
    if val:match('[",\n\r]') then
      return '"' .. val:gsub('"', '""') .. '"'
    end
    return val
  end

  -- Header row as CSV
  local csv_lines = {}
  local formatted_headers = {}
  for _, col in ipairs(col_names) do
    table.insert(formatted_headers, format_csv_field(col))
  end
  table.insert(csv_lines, table.concat(formatted_headers, ","))

  -- Retrieve un-truncated original lines if available
  local original_lines = vim.b[bufnr].original_lines or lines

  local row_count = 0
  for row = start_row, end_row do
    local raw_line = original_lines[row] or lines[row]
    if raw_line and not raw_line:match("^[-+%s]+$") and not raw_line:match("^%s*%(") and row > 1 then
      local cells = {}
      if raw_line:match("|") then
        for cell in string.gmatch(raw_line .. "|", "(.-)|") do
          table.insert(cells, vim.trim(cell))
        end
      else
        table.insert(cells, vim.trim(raw_line))
      end

      if #cells > 0 then
        local formatted_row = {}
        for i = 1, #col_names do
          table.insert(formatted_row, format_csv_field(cells[i] or ""))
        end
        table.insert(csv_lines, table.concat(formatted_row, ","))
        row_count = row_count + 1
      end
    end
  end

  if row_count == 0 then
    require("core.utils").notify("db_empty_cell")
    return
  end

  local csv_content = table.concat(csv_lines, "\n")
  vim.fn.setreg("+", csv_content)
  vim.fn.setreg('"', csv_content)

  require("core.utils").notify("db_copied_csv")
end

return M
