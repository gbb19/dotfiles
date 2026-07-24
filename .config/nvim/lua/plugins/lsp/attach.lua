local M = {}

function M.disable_formatting_if_conform(client, bufnr)
  local conform_ok, conform = pcall(require, "conform")
  if not conform_ok then return end

  for _, formatter in ipairs(conform.list_formatters(bufnr) or {}) do
    if formatter.available then
      client.server_capabilities.documentFormattingProvider = false
      client.server_capabilities.documentRangeFormattingProvider = false
      return
    end
  end
end

function M.setup(callback)
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = callback,
  })
end

return M
