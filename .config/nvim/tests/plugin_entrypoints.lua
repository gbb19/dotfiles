local modules = {
  "plugins.snacks",
  "plugins.snacks.files",
  "plugins.snacks.grep",
  "plugins.snacks.git",
  "plugins.snacks.buffers",
  "plugins.snacks.keymaps",
  "plugins.lsp",
  "plugins.lsp.completion",
  "plugins.lsp.mason",
  "plugins.lsp.diagnostics",
  "plugins.diffview.actions",
  "core.commands",
  "core.autocmds",
  "core.files",
  "core.notify",
  "core.git.feature",
}

local failures = {}
for _, module in ipairs(modules) do
  local ok, err = pcall(require, module)
  if not ok then failures[#failures + 1] = module .. ": " .. tostring(err) end
end

if #failures > 0 then
  io.stderr:write("Plugin entrypoint smoke test failed:\n- " .. table.concat(failures, "\n- ") .. "\n")
  vim.cmd("cquit 1")
end

print(("Plugin entrypoint smoke test passed: %d modules"):format(#modules))
