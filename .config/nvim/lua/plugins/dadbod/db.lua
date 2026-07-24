-- lua/plugins/dadbod/db.lua
-- Connection and environment profile management for vim-dadbod.

local M = {}

local shared = require("plugins.dadbod.shared")
local jobs = require("plugins.dadbod.jobs")

-- Track last failed notification timestamp per profile name to prevent notification spam on session restore
local _last_failed_notify = {}

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- Stop postgres-language-server daemon if installed to prevent orphaned background processes
    if vim.fn.executable("postgres-language-server") == 1 then
      pcall(vim.fn.system, { "postgres-language-server", "stop" })
    end
  end,
})

--- Parse user connection profiles from a local .db file.
--- @param db_file_path string
--- @return table<string, string>  profiles map
--- @return string[]  ordered keys
function M.parse_db_file(db_file_path)
  local profiles = {}
  local ordered_keys = {}
  local f = io.open(db_file_path, "r")
  if not f then
    return profiles, ordered_keys
  end

  for line in f:lines() do
    line = vim.trim(line)
    if line ~= "" and not line:match("^#") and not line:match("^;") then
      -- Profile key must be a valid identifier (alphanumeric, underscore, hyphen)
      local key, val = line:match("^([%w_%-]+)%s*=%s*(.+)$")
      if key and val then
        profiles[key] = val
        table.insert(ordered_keys, key)
      else
        -- If it doesn't match the profile pattern, treat it as a raw connection string (only if no profiles loaded yet)
        if #ordered_keys == 0 then
          profiles["default"] = line
          table.insert(ordered_keys, "default")
        end
        break
      end
    end
  end
  f:close()
  return profiles, ordered_keys
end

--- Interactively switch the active database environment profile.
function M.switch_connection()
  local bufnr = vim.api.nvim_get_current_buf()
  local db_file_path = vim.b[bufnr].db_file_path
  if not db_file_path or vim.fn.filereadable(db_file_path) ~= 1 then
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath ~= "" then
      db_file_path = vim.fs.find(".db", {
        upward = true,
        path = vim.fs.dirname(filepath),
      })[1]
    end
  end

  if not db_file_path or vim.fn.filereadable(db_file_path) ~= 1 then
    db_file_path = vim.fn.getcwd() .. "/.db"
  end

  local profiles, ordered_keys = M.parse_db_file(db_file_path)

  if #ordered_keys == 0 then
    require("core.utils").notify("db_no_configs")
    return
  end

  vim.ui.select(ordered_keys, {
    prompt = "Select Database Environment:",
    format_item = function(key)
      local url = profiles[key]
      local db_name = url:match("service=([^&]+)") or url:match("([^/]+)$") or key
      return string.format("%s (%s)", key, db_name)
    end,
  }, function(choice)
    if not choice then return end
    local db_url = profiles[choice]

    -- Bind display profile and path immediately
    vim.b[bufnr].db_profile = choice
    vim.b[bufnr].db_file_path = db_file_path
    -- Extract and bind db_service immediately
    local db_service = shared.get_service_name(db_url, choice)
    vim.b[bufnr].db_service = db_service

    -- Clear buffer-local connection immediately so no query can slip through
    -- using the old connection while the new test is still in flight.
    vim.b[bufnr].db = nil
    vim.w.db = nil
    vim.t.db = nil

    -- Set status to connecting and reload statusline
    vim.b[bufnr].db_connection_status = "connecting"
    pcall(function()
      require("lualine").refresh()
    end)

    -- Trigger autocmd to notify dadbod and completion systems
    vim.api.nvim_exec_autocmds("User", { pattern = "DBConnectionChanged" })

    -- Clear autocomplete column and table caches for the new connection schema
    pcall(function()
      require("plugins.dadbod.columns").clear_cache()
      require("plugins.dadbod.tables").clear_cache()
    end)

    -- Reset throttle for this connection profile on explicit user action
    local notify_key = db_service .. ":" .. (db_url ~= "" and db_url or choice)
    _last_failed_notify[notify_key] = nil

    -- Run test connection asynchronously
    M.test_connection_async(db_url, bufnr, choice, { is_auto = false })
  end)
end

--- Asynchronously test database connection.
--- If it succeeds, sets b:db and omnifunc to enable autocomplete.
--- If it fails, clears b:db and omnifunc to prevent autocomplete errors.
--- @param db_url string
--- @param bufnr integer
--- @param profile_name string
--- @param opts? { is_auto?: boolean }
function M.test_connection_async(db_url, bufnr, profile_name, opts)
  opts = opts or {}
  local is_auto = opts.is_auto or false
  local adapter = shared.get_adapter(db_url)

  if not adapter then
    vim.b[bufnr].db_connection_status = "failed"
    pcall(function() require("lualine").refresh() end)
    return
  end

  -- Kill any existing connection test for this buffer before starting a new one
  jobs.kill_for_buf(bufnr, "connection")

  local cmd
  local env = nil
  if adapter == "postgres" then
    -- Pass connect_timeout both via env AND as a psql option (-o) so it works
    -- even when connection params come from a pg_service.conf entry (remote hosts).
    cmd = { "psql", db_url, "-o", "/dev/null", "-t", "-c", "SELECT 1;",
            "--set=connect_timeout=3" }
    env = { PGCONNECT_TIMEOUT = "3" }
  elseif adapter == "mysql" then
    local p = shared.parse_url(db_url)
    cmd = { "mysql" }
    if p.user     then vim.list_extend(cmd, { "-u", p.user }) end
    if p.password then
      table.insert(cmd, "-p" .. p.password)
      env = { MYSQL_PWD = p.password }
    end
    if p.host     then vim.list_extend(cmd, { "-h", p.host }) end
    if p.port     then vim.list_extend(cmd, { "-P", p.port }) end
    if p.database then table.insert(cmd, p.database) end
    vim.list_extend(cmd, { "--connect-timeout=3", "--batch", "--silent", "-e", "SELECT 1;" })
  elseif adapter == "sqlite" then
    local path = db_url:match("sqlite:///(.+)") or db_url:match("sqlite://(.+)")
    cmd = { "sqlite3", path, "SELECT 1;" }
  end

  if not cmd then
    vim.b[bufnr].db_connection_status = "failed"
    pcall(function() require("lualine").refresh() end)
    return
  end

  -- Check if executable is installed
  if vim.fn.executable(cmd[1]) ~= 1 then
    vim.b[bufnr].db_connection_status = "failed"
    pcall(function() require("lualine").refresh() end)
    require("core.utils").notify("db_executable_missing", cmd[1])
    return
  end

  local job
  job = vim.system(cmd, { text = true, env = env }, vim.schedule_wrap(function(result)
    jobs.untrack(bufnr, job, "connection")
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    if result.code == 0 then
      vim.b[bufnr].db_connection_status = "connected"
      vim.b[bufnr].db = db_url
      vim.bo[bufnr].omnifunc = ""

      -- Dynamically launch postgres_lsp for this postgres buffer
      if adapter == "postgres" then
        pcall(function()
          local db_file = vim.b[bufnr].db_file_path or vim.fn.getcwd()
          local blink_ok, blink = pcall(require, "blink.cmp")
          local capabilities = blink_ok and blink.get_lsp_capabilities() or vim.lsp.protocol.make_client_capabilities()
          vim.lsp.start({
            name = "postgres_lsp",
            cmd = { "postgres-language-server", "lsp-proxy" },
            root_dir = vim.fs.dirname(db_file),
            capabilities = capabilities,
          }, { bufnr = bufnr })
        end)
      end

      -- b:db and omnifunc are now set — completion will fetch on first trigger.
    else
      vim.b[bufnr].db_connection_status = "failed"
      vim.b[bufnr].db = nil
      vim.bo[bufnr].omnifunc = ""

      -- Derive service name universally
      local service_name = shared.get_service_name(db_url, profile_name)
      local notify_key = service_name .. ":" .. (db_url ~= "" and db_url or (vim.b[bufnr].db_file_path or ""))

      local now = os.time()
      local last_time = _last_failed_notify[notify_key] or 0

      local should_notify = false
      if not is_auto then
        should_notify = true
      elseif now - last_time > 15 then
        should_notify = true
      end

      if should_notify then
        _last_failed_notify[notify_key] = now
        local err = vim.trim(result.stderr or "")
        require("core.utils").notify("db_connection_failed", err, {
          title   = string.format("[%s] Connection failed", service_name),
          timeout = 8000,
        })
      end
    end

    -- Refresh statusline to show updated connection status
    pcall(function() require("lualine").refresh() end)
  end))

  jobs.track(bufnr, job, "connection")
end

return M
