-- SQL table schema hover UI.

local M = {}

local function get_identifier_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local column = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = line:sub(1, column):match("([%w_%.]*)$") or ""
  local after = line:sub(column + 1):match("^([%w_%.]*)") or ""
  return before .. after
end

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
    return resolved ~= parts[1] and resolved or word
  elseif #parts >= 3 then
    return parts[1] .. "." .. parts[2]
  end
  return word
end

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

  local parent_buf = vim.api.nvim_get_current_buf()
  local existing_win = vim.b[parent_buf].table_detail_win
  if existing_win and vim.api.nvim_win_is_valid(existing_win) then
    vim.api.nvim_win_close(existing_win, true)
    vim.b[parent_buf].table_detail_win = nil
    return
  end

  local shared = require("plugins.dadbod.shared")
  shared.fetch_columns_async(db_url, resolved, parent_buf, function(rows)
    if not rows or #rows == 0 then
      require("core.utils").notify("db_table_not_found", resolved)
      return
    end

    local display_lines = shared.rows_to_display_lines(rows)
    local width = 0
    for _, line in ipairs(display_lines) do
      width = math.max(width, vim.fn.strdisplaywidth(line))
    end

    local title = " Schema: " .. resolved .. " "
    width = math.max(25, vim.fn.strdisplaywidth(title) + 2, width)
    width = math.min(width, math.floor(vim.o.columns * 0.8))
    local height = math.min(#display_lines, math.floor(vim.o.lines * 0.8))

    local cursor = vim.api.nvim_win_get_cursor(0)
    local screen_row = cursor[1] - vim.fn.line("w0")
    local row_pos = screen_row > height + 2 and -(height + 2) or 1

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, display_lines)
    vim.bo[float_buf].bufhidden = "wipe"
    vim.bo[float_buf].buftype = "nofile"
    vim.bo[float_buf].modifiable = false

    local win = vim.api.nvim_open_win(float_buf, false, {
      relative = "cursor",
      row = row_pos,
      col = 0,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = title,
      title_pos = "center",
    })
    vim.b[parent_buf].table_detail_win = win

    local group_id = vim.api.nvim_create_augroup("TableDetailHover_" .. win, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
      group = group_id,
      buffer = parent_buf,
      once = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        vim.b[parent_buf].table_detail_win = nil
        pcall(vim.api.nvim_del_augroup_by_id, group_id)
      end,
    })
  end)
end

return M
