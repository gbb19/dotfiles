-- Dadbod SQL/dbout lifecycle autocommand registration.

local M = {}
local state = require("plugins.dadbod.state")

local function handle_execute_pre(args)
  local file_path = args.match:match("^(.*)/DBExecutePre$")
  if not file_path then return end

  state.sql_source_by_output[file_path] = vim.api.nvim_get_current_buf()

  local ok, fidget_progress = pcall(require, "fidget.progress")
  if not ok then return end

  if state.query_handles[file_path] then
    pcall(function() state.query_handles[file_path]:finish() end)
  end

  local db_url = vim.b.db or ""
  local url_str = type(db_url) == "table" and (db_url.url or db_url[1] or "") or tostring(db_url)
  local label = url_str:match("[?&]service=([^&#]+)")
    or url_str:match("^[^?#]*/([^/?#]+)")
    or "db"

  state.query_handles[file_path] = fidget_progress.handle.create({
    title = string.format("DB [%s]", label),
    message = "Running...",
    lsp_client = { name = "Dadbod" },
  })
end

local function find_result_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if filetype == "dbout" or filetype == "explain" then
      return win
    end
  end
end

local function handle_sql_buf_enter(args)
  local sql_bufnr = args.buf
  local sql_path = vim.api.nvim_buf_get_name(sql_bufnr)
  if not sql_path or sql_path == "" then return end

  local results = require("plugins.dadbod.results")
  local subdir = results.get_subdir_for_sql(sql_path, sql_bufnr)
  if not subdir then return end

  local dbout_win = find_result_window()
  local cached_file = state.last_result_by_sql[sql_path]
  if cached_file and vim.fn.filereadable(cached_file) ~= 1 then
    state.last_result_by_sql[sql_path] = nil
    cached_file = nil
  end

  local latest = cached_file or results.get_latest_result(subdir)
  local has_valid_result = latest and vim.fn.filereadable(latest) == 1

  if has_valid_result then
    if not dbout_win then
      if not results.is_user_closed(sql_path) then
        vim.schedule(function()
          local current_buf = vim.api.nvim_get_current_buf()
          local current_path = vim.api.nvim_buf_get_name(current_buf)
          if current_path == sql_path and not find_result_window() then
            results.show_result_in_window(latest, subdir, sql_path)
          end
        end)
      end
    else
      local current = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dbout_win))
      if current ~= latest then
        local current_filename = vim.fn.fnamemodify(current, ":t")
        if current_filename:match("^Result_%d+_") then
          local target_buf = vim.fn.bufnr(latest)
          if target_buf == -1 then
            target_buf = vim.fn.bufadd(latest)
            vim.fn.bufload(target_buf)
          end
          if sql_path ~= "" then
            vim.b[target_buf].sql_source_path = sql_path
          end
          results.set_win_buf_safely(dbout_win, target_buf)
          state.last_dbout_dir = subdir
        end
      end
    end
  elseif dbout_win then
    pcall(vim.api.nvim_win_close, dbout_win, true)
  end
end

local function is_dbout_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local bufnr = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  local filetype = vim.bo[bufnr].filetype
  if filetype == "dbout" or filetype == "explain" then return true end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name:match("%.dbout$") ~= nil
    or name:match("/Result_%d+_") ~= nil
    or name:find("dadbodout", 1, true) ~= nil
end

local function is_normal_editor_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local config = vim.api.nvim_win_get_config(win)
  if config and config.relative and config.relative ~= "" then return false end
  return not is_dbout_win(win)
end

local function collect_windows()
  local normal_count = 0
  local dbout_wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_dbout_win(win) then
      table.insert(dbout_wins, win)
    elseif is_normal_editor_win(win) then
      normal_count = normal_count + 1
    end
  end
  return normal_count, dbout_wins
end

local function close_dbout_windows(dbout_wins)
  for _, win in ipairs(dbout_wins) do
    pcall(function() vim.wo[win].winfixbuf = false end)
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function handle_quit_pre()
  local normal_count, dbout_wins = collect_windows()
  if normal_count <= 1 then close_dbout_windows(dbout_wins) end
end

local function handle_win_closed(args)
  if state.is_deleting_result then return end

  local win = tonumber(args.match)
  if win and is_dbout_win(win) then
    local bufnr = vim.api.nvim_win_get_buf(win)
    local sql_source = vim.b[bufnr].sql_source_path
    if sql_source and sql_source ~= "" then
      local dbout_count = 0
      for _, other in ipairs(vim.api.nvim_list_wins()) do
        if other ~= win and is_dbout_win(other) then dbout_count = dbout_count + 1 end
      end
      if dbout_count == 0 then
        require("plugins.dadbod.results").set_user_closed(sql_source, true)
      end
    end
  end

  vim.schedule(function()
    local normal_count, dbout_wins = collect_windows()
    if normal_count == 0 and #dbout_wins > 0 then
      close_dbout_windows(dbout_wins)
      local remaining = vim.api.nvim_list_wins()
      if #remaining > 0 then
        local only_dbout = true
        for _, remaining_win in ipairs(remaining) do
          if not is_dbout_win(remaining_win) then
            only_dbout = false
            break
          end
        end
        if only_dbout then pcall(vim.cmd, "quit") end
      end
    end
  end)
end

local function handle_dbout_buf_enter(args)
  local bufnr = args.buf
  local results = require("plugins.dadbod.results")
  local sql_path = vim.b[bufnr].sql_source_path
  if not sql_path or sql_path == "" then
    sql_path = results.find_sql_path_for_dbout(vim.api.nvim_buf_get_name(bufnr))
    if sql_path then vim.b[bufnr].sql_source_path = sql_path end
  end
  if sql_path and sql_path ~= "" then
    state.last_result_by_sql[sql_path] = vim.api.nvim_buf_get_name(bufnr)
  end
end

--- Register buffer setup and query execution lifecycle events.
--- @param opts { group: integer, setup_sql: function }
function M.setup(opts)
  vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufEnter", "BufWinEnter" }, {
    pattern = { "dbout", "*.dbout", "explain" },
    group = opts.group,
    callback = require("plugins.dadbod.buffers").setup_dbout,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "*dbout/DBExecutePre",
    group = opts.group,
    callback = handle_execute_pre,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "*dbout/DBExecutePost",
    group = opts.group,
    callback = require("plugins.dadbod.results").handle_execute_post,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    group = opts.group,
    callback = opts.setup_sql,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*.sql",
    group = opts.group,
    callback = handle_sql_buf_enter,
  })

  vim.api.nvim_create_autocmd("QuitPre", {
    group = opts.group,
    callback = handle_quit_pre,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = opts.group,
    callback = handle_win_closed,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "*.dbout",
    group = opts.group,
    callback = handle_dbout_buf_enter,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = opts.group,
    callback = function()
      vim.fn.delete("/tmp/dadbodout_" .. vim.fn.getpid(), "rf")
    end,
  })
end

return M
