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

local function jump_to_item(item)
  require("core.layout").jump_to_normal_window()
  vim.cmd("normal! m'")
  vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
  vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
end

function M.type_definition()
  vim.lsp.buf.type_definition({
    on_list = function(options)
      local items = options.items
      local has_custom = false

      if #items > 1 then
        local filtered = {}
        for _, item in ipairs(items) do
          local filename = item.filename
          if filename and not filename:match("node_modules") and not filename:match("lib%..*%.d%.ts") then
            filtered[#filtered + 1] = item
          end
        end
        if #filtered > 0 then
          items = filtered
          has_custom = true
        end
      else
        local filename = items[1] and items[1].filename
        has_custom = filename
          and not filename:match("node_modules")
          and not filename:match("lib%..*%.d%.ts")
          or false
      end

      if #items == 1 then
        jump_to_item(items[1])
      elseif #items > 1 then
        if not has_custom then
          jump_to_item(items[1])
        else
          vim.fn.setqflist({}, " ", {
            title = options.title,
            items = items,
            context = options.context,
          })
          vim.schedule(function() Snacks.picker.qflist() end)
        end
      end
    end,
  })
end

function M.setup(callback)
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = callback,
  })
end

return M
