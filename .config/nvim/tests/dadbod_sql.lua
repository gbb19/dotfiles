local query = require("plugins.dadbod.query")
local shared = require("plugins.dadbod.shared")

local failures = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then
    failures[#failures + 1] = message
  end
end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)

local function set_sql(lines, cursor_row)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { cursor_row, 0 })
end

local function check_block(lines, cursor_row, expected_start, expected_end, expected_lines, label)
  set_sql(lines, cursor_row)
  local start_line, end_line, block_lines = query.get_sql_block()
  check(start_line == expected_start, label .. " start line changed")
  check(end_line == expected_end, label .. " end line changed")
  check(vim.deep_equal(block_lines, expected_lines), label .. " contents changed")
end

check_block({
  "SELECT first_value",
  "FROM first_table;",
  "SELECT second_value",
  "FROM second_table;",
}, 3, 3, 4, {
  "SELECT second_value",
  "FROM second_table;",
}, "semicolon boundary")

check_block({
  "SELECT ignored;",
  "",
  "SELECT active_value",
  "FROM active_table",
  "-- next statement",
  "SELECT ignored_again;",
}, 4, 3, 4, {
  "SELECT active_value",
  "FROM active_table",
}, "blank and comment boundary")

check_block({
  "/* block heading",
  "SELECT active_value",
  "FROM active_table;",
}, 2, 2, 3, {
  "SELECT active_value",
  "FROM active_table;",
}, "block comment boundary")

check_block({
  "SELECT ';' AS literal_value",
  "FROM active_table;",
}, 1, 1, 2, {
  "SELECT ';' AS literal_value",
  "FROM active_table;",
}, "non-trailing semicolon")

set_sql({
  "SELECT old_alias.id",
  "FROM archive.old_table AS old_alias;",
  "",
  "SELECT u.id, o.id",
  'FROM "sales"."users" AS u',
  "JOIN sales.orders o ON o.user_id = u.id;",
}, 4)
check(shared.resolve_alias_in_buf(bufnr, "u") == '"sales"."users"', "AS alias resolution changed")
check(shared.resolve_alias_in_buf(bufnr, "o") == "sales.orders", "JOIN alias resolution changed")
check(shared.resolve_alias_in_buf(bufnr, "old_alias") == "old_alias", "alias block isolation changed")
check(shared.resolve_alias_in_buf(bufnr, "missing") == "missing", "unresolved alias fallback changed")

set_sql({
  "SELECT p.id",
  "FROM public.people p;",
}, 1)
check(shared.resolve_alias_in_buf(bufnr, "p") == "public.people", "implicit FROM alias resolution changed")

local schema, table_name = shared.split_table_name('"sales"."Order"')
check(schema == "sales", "quoted schema parsing changed")
check(table_name == "Order", "quoted table parsing changed")
check(shared.quote_identifier("Order", "postgres") == '"Order"', "quoted identifier behavior changed")
check(shared.quote_identifier('"Order"', "postgres") == '"Order"', "existing identifier quotes changed")

vim.api.nvim_buf_delete(bufnr, { force = true })

if #failures > 0 then
  io.stderr:write(("Dadbod SQL characterization failed (%d/%d):\n- %s\n"):format(
    #failures,
    assertions,
    table.concat(failures, "\n- ")
  ))
  vim.cmd("cquit 1")
end

print(("Dadbod SQL characterization passed: %d assertions"):format(assertions))
