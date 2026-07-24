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

function M.rename_current_buffer(opts)
  opts = opts or {}
  local utils = require("core.utils")
  local bufnr = vim.api.nvim_get_current_buf()
  local current_path = vim.api.nvim_buf_get_name(bufnr)
  if current_path == "" then
    utils.notify("buffer_no_name")
    return
  end

  local current_filename = vim.fn.fnamemodify(current_path, ":t")
  local display_name = opts.display_name
      and opts.display_name(current_filename)
    or current_filename

  vim.ui.input({
    prompt = opts.prompt or "Rename file/buffer to: ",
    default = display_name,
  }, function(input)
    if not input or vim.trim(input) == "" then return end

    local directory = vim.fn.fnamemodify(current_path, ":h")
    local extension = vim.fn.fnamemodify(current_path, ":e")
    local new_filename
    if opts.build_filename then
      new_filename = opts.build_filename(input, current_filename, extension)
    else
      new_filename = input:gsub("[^%w%s._-]", "")
      if extension ~= "" and not new_filename:match("%." .. extension .. "$") then
        new_filename = new_filename .. "." .. extension
      end
    end

    local new_path = directory .. "/" .. new_filename
    if new_path == current_path then return end
    if vim.fn.filereadable(new_path) == 1 then
      utils.notify("file_already_exists", new_filename)
      return
    end

    local has_file = vim.fn.filereadable(current_path) == 1
    if has_file then
      local success, err = os.rename(current_path, new_path)
      if not success then
        utils.notify("error_disk_rename", tostring(err))
        return
      end
    end

    local saved_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    vim.api.nvim_buf_set_name(bufnr, new_path)
    vim.o.eventignore = saved_eventignore
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].buflisted = opts.buflisted ~= false

    if opts.after_rename then
      opts.after_rename(bufnr, new_path, has_file)
    elseif not has_file then
      vim.cmd("write")
    else
      vim.cmd("edit!")
    end
    utils.notify("buffer_renamed", new_filename)
  end)
end

return M
