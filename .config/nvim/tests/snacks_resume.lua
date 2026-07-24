local resume = require("plugins.snacks.resume")
local picker = resume.open("files_test", Snacks.picker.files, { cwd = vim.uv.cwd() })

local found = vim.wait(5000, function()
  return picker.finder and picker.finder.items and #picker.finder.items > 0
end, 50)
if not found then
  io.stderr:write("Snacks files finder timed out\n")
  vim.cmd("cquit 1")
end

local item_count = #picker.finder.items
picker:close()

local state = resume.state.files_test
if not state or not state.items or #state.items ~= item_count then
  io.stderr:write("Snacks files picker did not preserve cached items\n")
  vim.cmd("cquit 1")
end

local resumed = resume.resume("files_test")
if not resumed or resumed.closed or #resumed.finder.items ~= item_count then
  io.stderr:write("Snacks files picker did not resume from cached items\n")
  vim.cmd("cquit 1")
end

resumed:close()
print(("Snacks resume integration passed: %d cached items"):format(item_count))
