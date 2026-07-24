local failures = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then
    failures[#failures + 1] = message
  end
end

local function keymap(mode, lhs)
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if map.lhs == lhs then
      return map
    end
  end
end

local function has_autocmd_group(name)
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({})) do
    if autocmd.group_name == name then
      return true
    end
  end
  return false
end

local expected_keymaps = {
  { "n", " ff", "Find Files (Resume; [count]=new search)" },
  { "n", " fg", "Live Grep (Resume; [count]=edit filters)" },
  { "n", " fb", "Find Buffers (Pinned First + MRU)" },
  { "n", " gD", "Open Git Diffview" },
  { "n", " yp", "Copy Relative File Path" },
  { "n", " br", "Rename Buffer/File" },
}

for _, expected in ipairs(expected_keymaps) do
  local map = keymap(expected[1], expected[2])
  check(map ~= nil, ("missing keymap %s"):format(expected[2]))
  check(map and map.desc == expected[3], ("changed description for %s"):format(expected[2]))
end

local commands = vim.api.nvim_get_commands({})
for _, command in ipairs({
  "PackUpdate",
  "PackUpdateForce",
  "PackCheck",
  "PackRevert",
  "PackHealth",
  "PackClean",
  "PackLspInstall",
  "LoadEnv",
  "DiffviewOpen",
  "DiffviewFileHistory",
}) do
  check(commands[command] ~= nil, ("missing command :%s"):format(command))
end

for _, group in ipairs({
  "LazyFileTooling",
  "LazyInsertTooling",
  "LazyColorizer",
  "LazyDadbod",
  "LazyMarkdown",
  "LazyWhichKey",
  "LazySession",
  "AutoReloadFiles",
}) do
  check(has_autocmd_group(group), ("missing autocmd group %s"):format(group))
end

check(Snacks ~= nil, "Snacks global is unavailable")
check(Snacks and Snacks.config.bigfile.enabled == true, "Snacks bigfile is not enabled")
check(Snacks and Snacks.config.picker.enabled == true, "Snacks picker is not enabled")
check(Snacks and Snacks.config.input.enabled == true, "Snacks input is not enabled")

local resume = require("snacks.picker.resume")
check(type(resume.add) == "function", "Snacks resume.add is unavailable")
check(type(resume._resume) == "function", "configured Snacks resume implementation is unavailable")

if #failures > 0 then
  io.stderr:write(("characterization failed (%d/%d):\n- %s\n"):format(
    #failures,
    assertions,
    table.concat(failures, "\n- ")
  ))
  vim.cmd("cquit 1")
end

print(("characterization passed: %d assertions"):format(assertions))
