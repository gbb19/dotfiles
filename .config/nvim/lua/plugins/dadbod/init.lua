-- lua/plugins/dadbod/init.lua
-- Entry point for Neovim's dadbod configuration.
-- Configures autocommands, auto-connections, and routes buffer-local keymaps.

-- Add plugins using vim.pack
vim.pack.add({
  "https://github.com/tpope/vim-dadbod",
})

-- Suppress dadbod's built-in 'DB: Running query...' / 'DB: Query finished' echo messages
-- so we can replace them with Fidget spinner progress instead.
vim.g.db_ui_disable_info_notifications = 1

local M = {}
local state = require("plugins.dadbod.state")

-- Create custom setup autocommand group
local group = vim.api.nvim_create_augroup("DadbodCustomSetup", { clear = true })

-- Helper to retrieve identifier under the cursor (including dots)
local function get_identifier_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = line:sub(1, col):match("([%w_%.]*)$") or ""
  local after = line:sub(col + 1):match("^([%w_%.]*)") or ""
  return before .. after
end

-- Resolve the word under cursor to its actual database table name (resolving aliases if any)
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
    if resolved ~= parts[1] then
      return resolved
    else
      return word
    end
  elseif #parts >= 3 then
    return parts[1] .. "." .. parts[2]
  end
  return word
end

-- Interactively show table schema info (columns and types) on hover
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

  -- Check if table detail floating window is already open
  local parent_buf = vim.api.nvim_get_current_buf()
  local existing_win = vim.b[parent_buf].table_detail_win
  if existing_win and vim.api.nvim_win_is_valid(existing_win) then
    vim.api.nvim_win_close(existing_win, true)
    vim.b[parent_buf].table_detail_win = nil
    return
  end

  -- Fetch columns asynchronously and show float window
  require("plugins.dadbod.shared").fetch_columns_async(db_url, resolved, parent_buf, function(rows)
    if not rows or #rows == 0 then
      require("core.utils").notify("db_table_not_found", resolved)
      return
    end

    local display_lines = require("plugins.dadbod.shared").rows_to_display_lines(rows)
    local width = 0
    for _, l in ipairs(display_lines) do
      width = math.max(width, vim.fn.strdisplaywidth(l))
    end

    local title = " Schema: " .. resolved .. " "
    local title_w = vim.fn.strdisplaywidth(title)
    width = math.max(25, title_w + 2, width)

    local max_w = math.floor(vim.o.columns * 0.8)
    width = math.min(width, max_w)
    local height = math.min(#display_lines, math.floor(vim.o.lines * 0.8))

    -- Calculate layout relative to cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    local screen_row = cursor[1] - vim.fn.line("w0")
    local row_pos = 1
    if screen_row > height + 2 then
      row_pos = -(height + 2)
    end
    local col_pos = 0

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, display_lines)
    vim.bo[float_buf].bufhidden  = "wipe"
    vim.bo[float_buf].buftype    = "nofile"
    vim.bo[float_buf].modifiable = false

    -- Open without stealing focus (true hover)
    local win = vim.api.nvim_open_win(float_buf, false, {
      relative   = "cursor",
      row        = row_pos,
      col        = col_pos,
      width      = width,
      height     = height,
      style      = "minimal",
      border     = "rounded",
      title      = title,
      title_pos  = "center",
    })

    vim.b[parent_buf].table_detail_win = win

    -- Auto-close when cursor moves or buffer changes
    local group_id = vim.api.nvim_create_augroup("TableDetailHover_" .. win, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
      group    = group_id,
      buffer   = parent_buf,
      once     = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        vim.b[parent_buf].table_detail_win = nil
        pcall(vim.api.nvim_del_augroup_by_id, group_id)
      end,
    })
  end)
end

--- Updates or invalidates the cached last dbout file path for a SQL buffer
function M.update_last_result(sql_path, result_path)
  state.update_last_result(sql_path, result_path)
end

function M.open_last_result()
  return require("plugins.dadbod.results").open_last()
end

vim.api.nvim_create_user_command("DbInspectTables", function()
  require("plugins.dadbod.picker").inspect_tables()
end, { desc = "Inspect DB Schema & Tables (View Only)" })

local function setup_sql_buffer(args)
  require("plugins.dadbod.buffers").setup_sql(args, {
    auto_bind = require("plugins.dadbod.db").auto_bind,
    open_last_result = M.open_last_result,
    show_table_detail = M.show_table_detail,
  })
end

require("plugins.dadbod.autocmds").setup({
  group = group,
  setup_sql = setup_sql_buffer,
})

-- Force Neovim to always route *.dbout files to the "dbout" filetype.
vim.filetype.add({
  pattern = {
    [".*%.dbout"] = "dbout",
  },
})

-- Export public API functions for backwards compatibility if needed
M.run_sql_block = function() require("plugins.dadbod.query").run_sql_block() end
M.copy_block_as_csv = function() require("plugins.dadbod.query").copy_block_as_csv() end
M.copy_block_as_json = function() require("plugins.dadbod.query").copy_block_as_json() end
M.switch_connection = function() require("plugins.dadbod.db").switch_connection() end
M.browse_tables = function() require("plugins.dadbod.picker").browse_tables() end
M.inspect_tables = function() require("plugins.dadbod.picker").inspect_tables() end
M.switch_result_history = function() require("plugins.dadbod.history").switch_result_history() end
M.clear_all_results = function() require("plugins.dadbod.history").clear_all_results() end

-- Handle immediate load case if the buffer is already SQL or dbout
if vim.bo.filetype == "sql" then
  setup_sql_buffer()
elseif vim.bo.filetype == "dbout" then
  require("plugins.dadbod.buffers").setup_dbout()
end

return M
