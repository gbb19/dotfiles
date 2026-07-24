local M = {}

function M.setup(callback)
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = callback,
  })
end

return M
