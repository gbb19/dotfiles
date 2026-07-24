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

local function on_attach(ev)
  local opts = { buffer = ev.buf }
  local client = vim.lsp.get_client_by_id(ev.data.client_id)
  if not client then return end

  M.disable_formatting_if_conform(client, ev.buf)
  vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })

  if client.name ~= "graphql" then
    vim.keymap.set("n", "gd", function()
      Snacks.picker.lsp_definitions()
    end, vim.tbl_extend("force", opts, { desc = "Go to Definition" }))
  end
  vim.keymap.set("n", "gy", M.type_definition, vim.tbl_extend("force", opts, { desc = "Go to Type Definition" }))
  if client.name ~= "graphql" then
    vim.keymap.set("n", "gr", function()
      Snacks.picker.lsp_references()
    end, vim.tbl_extend("force", opts, { desc = "Go to References" }))
  end
  vim.keymap.set("n", "gi", function()
    Snacks.picker.lsp_implementations()
  end, vim.tbl_extend("force", opts, { desc = "Go to Implementation" }))

  local ft = vim.bo[ev.buf].filetype
  if client.name ~= "graphql" and ft ~= "sql" and ft ~= "dbout" then
    vim.keymap.set("n", "K", function()
      vim.lsp.buf.hover({ border = "rounded" })
    end, vim.tbl_extend("force", opts, { desc = "Hover Documentation" }))
  end
  vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename Symbol" }))
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code Action" }))
  vim.keymap.set("n", "<leader>ci", function()
    local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
    vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
  end, vim.tbl_extend("force", opts, { desc = "Toggle Inlay Hints" }))
  vim.keymap.set("n", "<leader>cs", "<cmd>lsp restart<CR>", vim.tbl_extend("force", opts, {
    desc = "Restart LSP Server",
  }))

  local ok, server_config = pcall(require, "plugins.lsp.servers." .. client.name)
  if ok and server_config.on_attach then server_config.on_attach(client, ev.buf) end
end

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("UserLspConfig", {}),
    callback = on_attach,
  })
end

return M
