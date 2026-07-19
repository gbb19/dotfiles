-- lua/plugins/dadbod/columns.lua
-- Custom blink.cmp source for SQL column autocomplete.
--
-- Rationale:
-- vim-dadbod-completion cannot resolve schema-qualified table aliases
-- nor properly lazy-load columns for large databases.
-- This source bypasses the plugin entirely using dadbod/shared utilities.
--
-- Supported databases: PostgreSQL, MySQL / MariaDB, SQLite  (via shared)

local shared = require("plugins.dadbod.shared")

-- Cache: keyed by "db_url|table_name" -> { items, timestamp }
local _cache = {}
local CACHE_TTL = 300 -- seconds

-- ---------------------------------------------------------------------------
-- blink.cmp source implementation
-- ---------------------------------------------------------------------------

local SqlColumnSource = {}
SqlColumnSource.__index = SqlColumnSource

function SqlColumnSource.new()
  return setmetatable({}, SqlColumnSource)
end

-- Note: enabled() is intentionally omitted.
-- SQL-filetype scoping is handled by per_filetype in lsp.lua to avoid
-- timing races where vim.bo.filetype may not be set at InsertEnter.

function SqlColumnSource:get_trigger_characters()
  return { "." }
end

function SqlColumnSource:get_completions(ctx, callback)
  local bufnr  = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db or vim.g.db
  if type(db_url) == "table" then
    db_url = db_url.url or db_url[1]
  end
  if not db_url or db_url == "" then
    callback(nil)
    return
  end

  -- Only proceed if we know the adapter
  if not shared.get_adapter(db_url) then
    callback(nil)
    return
  end

  -- Detect "alias." or "alias.partial" in the line up to the cursor.
  -- ctx.cursor[2] is 0-indexed column index, so sub(1, col) gets all characters before the cursor.
  local line_before = ctx.line:sub(1, ctx.cursor[2])
  local raw_alias = line_before:match("([%w_\"]+)%.[%w_]*$")
  if not raw_alias then
    callback(nil)
    return
  end
  local alias = raw_alias:gsub('^"', ''):gsub('"$', '')

  -- Resolve alias -> full table name (e.g. "sp" -> "warehousing.spare_part_inventory_aggregate")
  local table_name = shared.resolve_alias_in_buf(bufnr, alias)

  -- Check cache (keyed per db_url+table to prevent cross-database collisions)
  local cache_key = db_url .. "|" .. table_name
  local cached = _cache[cache_key]
  if cached and (os.time() - cached.ts) < CACHE_TTL then
    callback({
      is_incomplete_forward  = false,
      is_incomplete_backward = false,
      items = cached.items,
    })
    return
  end

  -- Get database adapter for quoting settings
  local adapter = shared.get_adapter(db_url)

  -- Fetch columns asynchronously via the shared utility
  shared.fetch_columns_async(db_url, table_name, bufnr, function(rows)
    if not rows or #rows == 0 then
      callback(nil)
      return
    end

    local items = shared.rows_to_completion_items(rows, adapter)
    _cache[cache_key] = { items = items, ts = os.time() }

    callback({
      is_incomplete_forward  = false,
      is_incomplete_backward = false,
      items = items,
    })
  end)
end

-- Utility: clear the column cache (e.g. after schema migrations)
function SqlColumnSource.clear_cache()
  _cache = {}
  require("core.utils").notify("db_cache_cleared")
end

-- blink.cmp expects the module itself to be the source class (calls source.new())
return SqlColumnSource
