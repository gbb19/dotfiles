-- lua/plugins/dadbod/adapters/postgres.lua
-- PostgreSQL adapter for column and table metadata fetching.

local M = {}

M.name = "postgres"
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
  local schema, tbl = split_table_name(table_name)
  local schema_clause = schema
    and string.format("AND c.table_schema = '%s'", schema) or ""

  local query = string.format([[
SELECT
    c.column_name,
    CASE
        WHEN c.data_type = 'character varying' THEN 'varchar(' || c.character_maximum_length || ')'
        WHEN c.data_type = 'numeric'           THEN 'numeric(' || c.numeric_precision || ',' || c.numeric_scale || ')'
        ELSE c.data_type
    END AS type,
    c.is_nullable,
    coalesce(pg_catalog.col_description(pg_c.oid, c.ordinal_position), '') AS description
FROM information_schema.columns c
JOIN pg_catalog.pg_class     pg_c ON pg_c.relname  = c.table_name
JOIN pg_catalog.pg_namespace pg_n ON pg_n.oid       = pg_c.relnamespace
                                  AND pg_n.nspname   = c.table_schema
WHERE c.table_name = '%s' %s
ORDER BY c.ordinal_position;
  ]], tbl, schema_clause)

  local cmd = { "psql", db_url, "--csv", "-c", query }

  local function parse(stdout)
    local rows, first = {}, true
    for line in stdout:gmatch("[^\r\n]+") do
      if first then first = false  -- skip header row
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
  local query = [[
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN (
    'pg_catalog', 'information_schema', 'pgagent',
    '_timescaledb_internal', '_timescaledb_cache',
    '_timescaledb_config', '_timescaledb_catalog',
    'timescaledb_experimental', 'timescaledb_information'
)
AND table_name NOT LIKE '_timescaledb_%'
AND table_name NOT LIKE '%_columnstore%'
AND table_name NOT LIKE '%_compressed%'
ORDER BY table_schema, table_name;
]]
  local cmd = { "psql", db_url, "--csv", "-c", query }

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
