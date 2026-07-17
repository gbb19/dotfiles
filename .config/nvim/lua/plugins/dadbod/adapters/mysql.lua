-- lua/plugins/dadbod/adapters/mysql.lua
-- MySQL / MariaDB adapter for column and table metadata fetching.

local M = {}

M.name = "mysql"
M.quote_char = '`'

-- Helper to parse database URL
local function parse_url(db_url)
  local user, pass, host, port, database =
    db_url:match("://([^:@]+):([^@]*)@([^:/?]+):?(%d*)/([^?]*)")
  if not user then
    user, host, port, database =
      db_url:match("://([^@]+)@([^:/?]+):?(%d*)/([^?]*)")
  end
  return {
    user     = user,
    password = (pass and pass ~= "") and pass or nil,
    host     = (host and host ~= "") and host or nil,
    port     = (port and port ~= "") and port or nil,
    database = (database and database ~= "") and database or nil,
  }
end

local function split_table_name(table_name)
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

function M.build_column_cmd(db_url, table_name)
  local schema, tbl = split_table_name(table_name)
  local p = parse_url(db_url)

  local schema_clause = schema
    and string.format("AND TABLE_SCHEMA = '%s'", schema)
    or (p.database and string.format("AND TABLE_SCHEMA = '%s'", p.database) or "")

  local query = string.format(
    "SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_COMMENT "
    .. "FROM INFORMATION_SCHEMA.COLUMNS "
    .. "WHERE TABLE_NAME = '%s' %s ORDER BY ORDINAL_POSITION;",
    tbl, schema_clause
  )

  local cmd = { "mysql" }
  if p.user     then vim.list_extend(cmd, { "-u", p.user }) end
  if p.password then table.insert(cmd, "-p" .. p.password) end
  if p.host     then vim.list_extend(cmd, { "-h", p.host }) end
  if p.port     then vim.list_extend(cmd, { "-P", p.port }) end
  if p.database then table.insert(cmd, p.database) end
  vim.list_extend(cmd, { "--batch", "--silent", "-e", query })

  local function parse(stdout)
    local rows, first = {}, true
    for line in stdout:gmatch("[^\r\n]+") do
      if first then first = false
      else
        local col, typ, nullable, desc =
          line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)")
        if col and col ~= "" then
          local detail = typ or ""
          if nullable == "YES" then detail = detail .. " | nullable" end
          table.insert(rows, { col = col, detail = detail, desc = desc or "" })
        end
      end
    end
    return rows
  end

  return cmd, parse
end

function M.build_tables_cmd(db_url)
  local p = parse_url(db_url)
  local query = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
    .. "WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') "
    .. "ORDER BY TABLE_SCHEMA, TABLE_NAME;"

  local cmd = { "mysql" }
  if p.user     then vim.list_extend(cmd, { "-u", p.user }) end
  if p.password then table.insert(cmd, "-p" .. p.password) end
  if p.host     then vim.list_extend(cmd, { "-h", p.host }) end
  if p.port     then vim.list_extend(cmd, { "-P", p.port }) end
  if p.database then table.insert(cmd, p.database) end
  vim.list_extend(cmd, { "--batch", "--silent", "-e", query })

  local function parse(stdout)
    local tables, first = {}, true
    for line in stdout:gmatch("[^\r\n]+") do
      if first then first = false
      else
        local schema, name = line:match("^([^\t]*)\t?(.*)")
        if name and name ~= "" then
          table.insert(tables, { schema = schema, name = name })
        end
      end
    end
    return tables
  end

  return cmd, parse
end

return M
