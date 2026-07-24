local dadbod = require("plugins.dadbod")
local cell = require("plugins.dadbod.cell")
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
  "yank_in_clause",
  "yank_insert_statements",
  "yank_csv",
}) do
  check(type(cell[name]) == "function", ("Dadbod cell export API changed: %s"):format(name))
end

local dbout_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(dbout_buf, "/tmp/Result_1_users.dbout")
vim.api.nvim_set_current_buf(dbout_buf)
vim.bo[dbout_buf].filetype = "dbout"
vim.api.nvim_buf_set_lines(dbout_buf, 0, -1, false, {
  "id | name",
  "---+-------",
  "1  | O'Neil",
})
vim.b[dbout_buf].original_lines = {
  "id | name",
  "---+-------",
  "1  | O'Neil",
}
vim.api.nvim_win_set_cursor(0, { 3, 0 })

local expected_dbout_maps = {
  ["gz"] = "Inspect full cell value",
  ["K"] = "Inspect full cell value (Hover)",
  ["gW"] = "Toggle fixed column width",
  ["<Tab>"] = "Next Column",
  ["<S-Tab>"] = "Previous Column",
  ["gh"] = "Jump to Header",
  ["yic"] = "Yank full inner cell",
  ["yac"] = "Yank full around cell",
  ["yin"] = "Yank Column as SQL IN Condition",
  [" yI"] = nil,
  [" yi"] = "Yank Column as SQL IN Condition",
  ["yis"] = "Yank Rows as SQL INSERT Statement",
  [" ys"] = "Yank Rows as SQL INSERT Statement",
  [" yc"] = "Yank Rows as CSV",
  [" rc"] = "Yank Rows as CSV",
  [" rq"] = "Delete Result Buffer & File",
  ["[b"] = "Previous Result Buffer",
  ["]b"] = "Next Result Buffer",
  [" rh"] = "Query Result History",
  [" rx"] = "Clear Query History",
}

local dbout_maps = {}
for _, map in ipairs(vim.api.nvim_buf_get_keymap(dbout_buf, "n")) do
  dbout_maps[map.lhs] = map.desc
end
for lhs, description in pairs(expected_dbout_maps) do
  if description then
    check(dbout_maps[lhs] == description, ("dbout buffer keymap changed: %s"):format(lhs))
  end
end

cell.yank_in_clause()
check(vim.fn.getreg('"') == "id IN (1)", "SQL IN-clause generation changed")

cell.yank_insert_statements()
check(
  vim.fn.getreg('"') == "INSERT INTO users (id, name) VALUES\n  (1, 'O''Neil');",
  "SQL INSERT generation changed"
)

cell.yank_csv()
check(vim.fn.getreg('"') == "id,name\n1,O'Neil", "dbout CSV generation changed")

vim.wo.winfixbuf = false
vim.api.nvim_buf_delete(dbout_buf, { force = true })

local sql_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(sql_buf, "/tmp/dadbod_runtime.sql")
vim.api.nvim_set_current_buf(sql_buf)
vim.bo[sql_buf].filetype = "sql"

local expected_sql_maps = {
  [" rr"] = "Run SQL Block",
  [" rc"] = "Copy Results as CSV",
  [" rj"] = "Copy Results as JSON",
  [" rp"] = "Explain Performance (Clean)",
  [" rv"] = "Explain Performance (Verbose)",
  [" ro"] = "Open Last Result for this SQL file",
  [" rs"] = "Switch Database Environment",
  [" rf"] = "Find & Insert DB Table",
  [" ri"] = "Inspect DB Schema & Tables (View Only)",
  [" rh"] = "Query Result History",
  [" rx"] = "Clear Query History",
  ["K"] = "Show Table Detail (Hover)",
}

local sql_maps = {}
for _, map in ipairs(vim.api.nvim_buf_get_keymap(sql_buf, "n")) do
  sql_maps[map.lhs] = map.desc
end
for lhs, description in pairs(expected_sql_maps) do
  check(sql_maps[lhs] == description, ("SQL buffer keymap changed: %s"):format(lhs))
end

vim.api.nvim_buf_delete(sql_buf, { force = true })

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
