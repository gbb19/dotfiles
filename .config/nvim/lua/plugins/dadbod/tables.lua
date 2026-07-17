-- lua/plugins/dadbod/tables.lua
-- Custom blink.cmp source for SQL table autocomplete.

local shared = require("plugins.dadbod.shared")

-- Cache: keyed by "db_url" -> { tables, ts }
local _cache = {}
local CACHE_TTL = 300 -- seconds

local SqlTableSource = {}
SqlTableSource.__index = SqlTableSource

function SqlTableSource.new()
  return setmetatable({}, SqlTableSource)
end

function SqlTableSource:get_trigger_characters()
  return { "." }
end

function SqlTableSource:get_completions(ctx, callback)
  local bufnr  = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db or vim.g.db
  if not db_url or db_url == "" then
    callback(nil)
    return
  end

  local adapter = shared.get_adapter(db_url)
  if not adapter then
    callback(nil)
    return
  end

  -- Detect "schema." or "schema.partial" in the line up to the cursor.
  -- Supports both quoted and unquoted schema names (e.g. warehousing. or "warehousing".)
  local line_before = ctx.line:sub(1, ctx.cursor[2])
  local raw_prefix = line_before:match("([%w_\"]+)%.[%w_]*$")
  local schema_prefix = raw_prefix and raw_prefix:gsub('^"', ''):gsub('"$', '') or nil

  -- Check cache for this db_url
  local cache_key = db_url
  local cached = _cache[cache_key]

  local function process_tables(tables)
    if not tables or #tables == 0 then
      callback(nil)
      return
    end

    local items = {}
    if schema_prefix then
      -- User typed "schema.", return only tables under this schema (case-insensitive)
      for _, t in ipairs(tables) do
        if t.schema and t.schema:lower() == schema_prefix:lower() then
          local q_name = shared.quote_identifier(t.name, adapter)
          table.insert(items, {
            label      = q_name,
            kind       = vim.lsp.protocol.CompletionItemKind.Class,
            detail     = t.schema,
            insertText = q_name,
            sortText   = q_name,
          })
        end
      end
    else
      -- User typed without schema, return schema names AND tables (qualified if not public/main)
      local schemas = {}
      for _, t in ipairs(tables) do
        if t.schema and t.schema ~= "" and t.schema ~= "main" then
          schemas[t.schema] = true
        end

        local q_name = shared.quote_identifier(t.name, adapter)
        if not t.schema or t.schema == "" or t.schema == "public" or t.schema == "main" then
          -- Public/default tables are suggested directly
          table.insert(items, {
            label      = q_name,
            kind       = vim.lsp.protocol.CompletionItemKind.Class,
            detail     = t.schema and (t.schema .. " table") or "table",
            insertText = q_name,
            sortText   = "2_" .. q_name,
          })
        else
          -- Non-public/custom schema tables are suggested as schema-qualified names
          local q_schema = shared.quote_identifier(t.schema, adapter)
          local full_name = q_schema .. "." .. q_name
          table.insert(items, {
            label      = full_name,
            kind       = vim.lsp.protocol.CompletionItemKind.Class,
            detail     = t.schema .. " table",
            insertText = full_name,
            sortText   = "2_" .. full_name,
          })
        end
      end

      -- Add schemas as suggestions
      for s in pairs(schemas) do
        local q_schema = shared.quote_identifier(s, adapter)
        table.insert(items, {
          label      = q_schema,
          kind       = vim.lsp.protocol.CompletionItemKind.Module,
          detail     = "schema",
          insertText = q_schema,
          sortText   = "1_" .. q_schema, -- rank schemas highest
        })
      end
    end

    callback({
      is_incomplete_forward  = false,
      is_incomplete_backward = false,
      items = items,
    })
  end

  if cached and (os.time() - cached.ts) < CACHE_TTL then
    process_tables(cached.tables)
    return
  end

  -- Fetch tables asynchronously via shared utility
  shared.fetch_tables_async(db_url, bufnr, function(tables)
    if not tables then
      callback(nil)
      return
    end

    _cache[cache_key] = { tables = tables, ts = os.time() }
    process_tables(tables)
  end)
end

-- Utility: clear the cache
function SqlTableSource.clear_cache()
  _cache = {}
end

return SqlTableSource
