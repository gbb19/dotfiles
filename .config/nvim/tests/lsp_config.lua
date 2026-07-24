local failures = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then failures[#failures + 1] = message end
end

local ok, error_message = pcall(require, "plugins.lsp")
if not ok then
  io.stderr:write("LSP configuration failed to load: " .. tostring(error_message) .. "\n")
  vim.cmd("cquit 1")
end

local function keymap(lhs)
  for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
    if map.lhs == lhs then return map end
  end
end

for lhs, description in pairs({
  ["[d"] = "Go to Previous Diagnostic",
  ["]d"] = "Go to Next Diagnostic",
  ["[e"] = "Go to Previous Error",
  ["]e"] = "Go to Next Error",
  [" cy"] = "Copy / Yank Diagnostic Message",
}) do
  local map = keymap(lhs)
  check(map and map.desc == description, "LSP diagnostic keymap changed: " .. lhs)
end

for _, server in ipairs(require("languages").lsp_servers) do
  check(vim.lsp.config[server] ~= nil, "LSP server config missing: " .. server)
end

if #failures > 0 then
  io.stderr:write(("LSP characterization failed (%d/%d):\n- %s\n"):format(
    #failures,
    assertions,
    table.concat(failures, "\n- ")
  ))
  vim.cmd("cquit 1")
end

print(("LSP characterization passed: %d assertions"):format(assertions))
