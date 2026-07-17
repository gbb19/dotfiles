-- lua/plugins/dadbod/keywords.lua
-- Custom blink.cmp source for standard SQL keywords.

local SqlKeywordSource = {}
SqlKeywordSource.__index = SqlKeywordSource

function SqlKeywordSource.new()
  return setmetatable({}, SqlKeywordSource)
end

local sql_keywords = {
  "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "LIMIT", "OFFSET",
  "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM",
  "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "FULL JOIN", "CROSS JOIN",
  "ON", "USING", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN", "LIKE", "ILIKE", "IS NULL", "IS NOT NULL",
  "AS", "DISTINCT", "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END",
  "CREATE TABLE", "DROP TABLE", "ALTER TABLE", "INDEX", "PRIMARY KEY", "FOREIGN KEY",
  "VARCHAR", "TEXT", "INTEGER", "BIGINT", "NUMERIC", "BOOLEAN", "TIMESTAMP", "UUID", "JSONB"
}

function SqlKeywordSource:get_completions(ctx, callback)
  -- If there is a dot in the current word prefix (e.g. table.col or schema.tbl),
  -- do not suggest keywords.
  local line_before = ctx.line:sub(1, ctx.cursor[2] + 1)
  if line_before:match("[%w_\"]+%.[%w_]*$") then
    callback(nil)
    return
  end

  local items = {}
  for _, kw in ipairs(sql_keywords) do
    table.insert(items, {
      label      = kw,
      kind       = vim.lsp.protocol.CompletionItemKind.Keyword,
      detail     = "SQL Keyword",
      insertText = kw,
      sortText   = "9_" .. kw, -- keep keywords ranked below tables and columns
    })
  end

  callback({
    is_incomplete_forward  = false,
    is_incomplete_backward = false,
    items = items,
  })
end

return SqlKeywordSource
