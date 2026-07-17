local M = {}

--- Resolve formatter for a given filetype and buffer
--- @param filetype string The filetype of the buffer (e.g. "typescript", "lua")
--- @param default_formatter table|function The fallback formatter definition
--- @return table
function M.get_formatter(filetype, default_formatter)
  -- 1. Check filetype-specific formatter overrides in project config
  if vim.g.project_formatters and type(vim.g.project_formatters) == "table" then
    local fmt = vim.g.project_formatters[filetype]
    if fmt then
      if type(fmt) == "table" then
        return fmt
      else
        return { fmt }
      end
    end
  end

  -- 2. Check global project formatter override
  if vim.g.project_formatter and type(vim.g.project_formatter) == "string" then
    return { vim.g.project_formatter }
  end

  -- 3. Fallback to default
  if type(default_formatter) == "function" then
    return default_formatter()
  else
    return default_formatter
  end
end

--- Resolve linters for a given filetype
--- @param filetype string The filetype of the buffer (e.g. "typescript", "lua")
--- @param default_linters table The fallback linters definition
--- @return table
function M.get_linters(filetype, default_linters)
  -- 1. Check filetype-specific linter overrides in project config
  if vim.g.project_linters and type(vim.g.project_linters) == "table" then
    local lnts = vim.g.project_linters[filetype]
    if lnts then
      if type(lnts) == "table" then
        return lnts
      else
        return { lnts }
      end
    end
  end

  -- 2. Check global project linter override
  if vim.g.project_linter and type(vim.g.project_linter) == "string" then
    return { vim.g.project_linter }
  end

  -- 3. Fallback to default
  return default_linters or {}
end

--- Check if an LSP server is explicitly enabled in the project config list
--- @param server_name string LSP server name (e.g. "eslint", "oxlint")
--- @return boolean
function M.is_lsp_explicitly_enabled(server_name)
  local project_servers = vim.g.project_lsp_servers
  if project_servers and type(project_servers) == "table" then
    return vim.tbl_contains(project_servers, server_name)
  end
  return false
end

--- Check if an LSP server should be active (defaults to true if no project list is defined)
--- @param server_name string LSP server name
--- @return boolean
function M.should_enable_lsp(server_name)
  local project_servers = vim.g.project_lsp_servers
  if project_servers and type(project_servers) == "table" then
    return vim.tbl_contains(project_servers, server_name)
  end
  return true
end

--- Resolve skipFiles for DAP
--- @param default_skip_files table Fallback skipFiles list
--- @return table
function M.get_dap_skip_files(default_skip_files)
  local skip_files = {}
  if default_skip_files then
    vim.list_extend(skip_files, default_skip_files)
  end
  if vim.g.project_dap_skip_files and type(vim.g.project_dap_skip_files) == "table" then
    for _, file in ipairs(vim.g.project_dap_skip_files) do
      if not vim.tbl_contains(skip_files, file) then
        table.insert(skip_files, file)
      end
    end
  end
  return skip_files
end

--- Resolve smartStep for DAP
--- @param default_smart_step boolean Fallback smartStep value
--- @return boolean
function M.get_dap_smart_step(default_smart_step)
  if vim.g.project_dap_smart_step ~= nil then
    return vim.g.project_dap_smart_step
  end
  return default_smart_step
end

return M
