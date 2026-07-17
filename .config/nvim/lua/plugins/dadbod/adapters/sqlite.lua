-- lua/plugins/dadbod/adapters/sqlite.lua
-- SQLite adapter for column and table metadata fetching.

local M = {}

M.name = "sqlite"
M.quote_char = '"'

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
  local path = db_url:match("sqlite:///(.+)") or db_url:match("sqlite://(.+)")
  local _, tbl = split_table_name(table_name)

  local query = string.format(
    "SELECT name, type, CASE \"notnull\" WHEN 1 THEN 'NO' ELSE 'YES' END, '' "
    .. "FROM pragma_table_info('%s');", tbl
  )

  local cmd = { "sqlite3", path, "-csv", "-header", query }

  local function parse(stdout)
    local rows, first = {}, true
    for line in stdout:gmatch("[^\r\n]+") do
      if first then first = false
      else
        local col, typ, nullable, desc =
          line:match("^([^,]*),([^,]*),([^,]*),?(.*)")
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
  local path = db_url:match("sqlite:///(.+)") or db_url:match("sqlite://(.+)")
  local query = "SELECT 'main' AS table_schema, name AS table_name "
    .. "FROM sqlite_master "
    .. "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
    .. "ORDER BY name;"

  local cmd = { "sqlite3", path, "-csv", "-header", query }

  local function parse(stdout)
    local tables, first = {}, true
    for line in stdout:gmatch("[^\r\n]+") do
      if first then first = false
      else
        local schema, name = line:match("^([^,]*),?(.*)")
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
