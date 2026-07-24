local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_name(bufnr, "/tmp/dadbod_immediate_load.sql")
vim.bo[bufnr].filetype = "sql"

local loaded, error_message = pcall(require, "plugins.dadbod")
if not loaded then
  io.stderr:write("Dadbod immediate SQL load failed: " .. tostring(error_message) .. "\n")
  vim.cmd("cquit 1")
end

local found = false
for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
  if map.lhs == " rr" and map.desc == "Run SQL Block" then
    found = true
    break
  end
end
if not found then
  io.stderr:write("Dadbod immediate SQL load did not configure buffer mappings\n")
  vim.cmd("cquit 1")
end

print("Dadbod immediate SQL load passed")
