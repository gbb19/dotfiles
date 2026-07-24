local M = {}

function M.copy_relative_path(path, base)
  local utils = require("core.utils")
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then
    utils.notify("buffer_no_name")
    return nil
  end

  path = vim.fs.abspath(path)
  base = vim.fs.abspath(base or vim.uv.cwd())
  local relative_path = vim.fs.relpath(base, path) or path
  vim.fn.setreg("+", relative_path)
  vim.fn.setreg('"', relative_path)
  utils.notify("file_path_copied", relative_path)
  return relative_path
end

return M
