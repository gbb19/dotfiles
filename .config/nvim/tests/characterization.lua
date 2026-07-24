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
  { "n", " fF", "Find Files (Fresh Search)" },
  { "n", " fg", "Live Grep (Resume; [count]=edit filters)" },
  { "n", " fG", "Live Grep (Fresh Search)" },
  { "n", " fb", "Find Buffers (Pinned First + MRU)" },
  { "n", " ft", "Select Colorscheme / Themes" },
  { "n", " fr", "Recent Files" },
  { "n", " fh", "Help Tags" },
  { "n", " gc", "Git Checkout Branch (Local First + MRU)" },
  { "n", " cd", "Search Diagnostics (Current File)" },
  { "n", " cD", "Search Diagnostics (Workspace)" },
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

local resume = require("plugins.snacks.resume")
check(type(resume.capture) == "function", "configured Snacks resume capture is unavailable")
check(type(resume.resume) == "function", "configured Snacks resume implementation is unavailable")

local previous_files_state = resume.state.files
local cached_items = {
  { file = "one.lua" },
  { file = "two.lua" },
}
resume.capture("files", {
  init_opts = { source = "files" },
  selected = function()
    return {}
  end,
  list = { cursor = 2, top = 1, items = cached_items },
  input = { filter = { pattern = "", search = "" } },
  finder = { items = cached_items },
})
check(resume.state.files ~= nil, "file picker resume state is not recorded")
check(resume.state.files.cursor == 2, "file picker resume cursor is not recorded")
check(resume.state.files.items == cached_items, "file picker items are not cached for instant resume")
resume.state.files = previous_files_state

local git_branches = require("core.git.branches")
local local_branches = git_branches.parse_local({
  "* main    abc1234 [origin/main: ahead 2, behind 1] current",
  "  feature def5678 [origin/feature: gone] old",
  "  remotes/origin/HEAD -> origin/main",
}, "/repo")
check(#local_branches == 2, "local Git branch parsing changed")
check(local_branches[1].branch == "main", "current Git branch name parsing changed")
check(local_branches[1].current == true, "current Git branch marker parsing changed")
check(local_branches[1].ahead == 2, "Git ahead count parsing changed")
check(local_branches[1].behind == 1, "Git behind count parsing changed")
check(local_branches[1].cwd == "/repo", "Git branch root propagation changed")
check(local_branches[2].gone == true, "gone Git branch parsing changed")

local remote_branches = git_branches.parse_remote({
  "  origin/HEAD -> origin/main",
  "  origin/main",
  "  origin/feature",
}, "/repo")
check(#remote_branches == 2, "remote Git branch parsing changed")
check(remote_branches[1].branch == "origin/main", "remote Git branch order changed")
check(remote_branches[1].is_remote == true, "remote Git branch marker changed")

if #failures > 0 then
  io.stderr:write(("characterization failed (%d/%d):\n- %s\n"):format(
    #failures,
    assertions,
    table.concat(failures, "\n- ")
  ))
  vim.cmd("cquit 1")
end

print(("characterization passed: %d assertions"):format(assertions))
