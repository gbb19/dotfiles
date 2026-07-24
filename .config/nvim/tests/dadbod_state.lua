local shared = require("plugins.dadbod.shared")
local history = require("plugins.dadbod.history")
local state = require("plugins.dadbod.state")

local function fail(message)
  io.stderr:write(message .. "\n")
  vim.cmd("cquit 1")
end

shared.set_user_closed("/tmp/query.sql", true)
if shared.user_closed_by_sql ~= state.user_closed_by_sql then
  fail("Dadbod user-closed compatibility table changed")
end
if not shared.is_user_closed("/tmp/query.sql") then
  fail("Dadbod user-closed state was not stored")
end
shared.set_user_closed("/tmp/query.sql", false)
if shared.is_user_closed("/tmp/query.sql") then
  fail("Dadbod user-closed state was not cleared")
end
if shared.is_user_closed("") then
  fail("Dadbod empty SQL path should not be marked closed")
end

local sql_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(sql_buf, "/tmp/project/queries/report.sql")
vim.b[sql_buf].db_service = "sales/dev"
local subdir = shared.get_subdir_for_sql("/tmp/project/queries/report.sql", sql_buf)
local expected_suffix = "/sales_dev/report"
if not subdir or subdir:sub(-#expected_suffix) ~= expected_suffix then
  fail(("Dadbod result subdirectory changed: %s"):format(tostring(subdir)))
end

local history_dir = vim.fn.tempname()
vim.fn.mkdir(history_dir, "p")
for _, name in ipairs({
  "Result_10_last.dbout",
  "Result_2_middle.dbout",
  "Result_1_first.dbout",
  "ignored.dbout",
}) do
  vim.fn.writefile({ "value" }, vim.fs.joinpath(history_dir, name))
end

history.last_dbout_dir = history_dir
if state.last_dbout_dir ~= history_dir then
  fail("Dadbod history compatibility state changed")
end
local files = history.get_result_files(nil)
if #files ~= 3 then
  fail(("Dadbod result history count changed: %d"):format(#files))
end
if files[1].counter ~= 1 or files[2].counter ~= 2 or files[3].counter ~= 10 then
  fail("Dadbod result history ordering changed")
end

vim.fn.delete(history_dir, "rf")
vim.api.nvim_buf_delete(sql_buf, { force = true })
print("Dadbod state characterization passed")
