local dadbod = require("plugins.dadbod")
local query = require("plugins.dadbod.query")

local failures = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then
    failures[#failures + 1] = message
  end
end

for _, name in ipairs({
  "get_sql_block",
  "run_query_async",
  "run_sql_block",
  "copy_block_as_csv",
  "copy_block_as_json",
  "explain_query",
}) do
  check(type(query[name]) == "function", ("Dadbod query API changed: %s"):format(name))
end

for _, name in ipairs({
  "run_sql_block",
  "copy_block_as_csv",
  "copy_block_as_json",
}) do
  check(type(dadbod[name]) == "function", ("Dadbod package compatibility API changed: %s"):format(name))
end

if #failures > 0 then
  io.stderr:write(("Dadbod runtime characterization failed (%d/%d):\n- %s\n"):format(
    #failures,
    assertions,
    table.concat(failures, "\n- ")
  ))
  vim.cmd("cquit 1")
end

print(("Dadbod runtime characterization passed: %d assertions"):format(assertions))
