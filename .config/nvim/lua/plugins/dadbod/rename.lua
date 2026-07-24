local M = {}

function M.rename_current_result()
  require("core.files").rename_current_buffer({
    prompt = "Enter new result name: ",
    buflisted = false,
    display_name = function(filename)
      return filename:gsub("%.dbout$", ""):gsub("^Result_%d+_", ""):gsub("_", " ")
    end,
    build_filename = function(input, current_filename, extension)
      local clean_name = input:gsub("[^%w%s_-]", ""):gsub("%s+", "_")
      local counter = current_filename:match("^Result_(%d+)_")
      if counter then
        return string.format("Result_%s_%s.%s", counter, clean_name, extension)
      end
      return string.format("Result_%s.%s", clean_name, extension)
    end,
    after_rename = function(bufnr, new_path)
      local db = vim.b[bufnr].db or {}
      if type(db) == "table" then
        db.output = new_path
        vim.b[bufnr].db = db
      end
    end,
  })
end

function M.setup(bufnr)
  vim.keymap.set("n", "<leader>br", M.rename_current_result, {
    buffer = bufnr,
    desc = "Rename Buffer/File",
  })
end

return M
