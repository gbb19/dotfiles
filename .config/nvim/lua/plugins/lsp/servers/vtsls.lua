local M = {}
local utils = require("core.utils")

M.settings = {
  typescript = {
    updateImportsOnFileMove = { enabled = "always" },
    inlayHints = {
      parameterNames             = { enabled = "literals" }, -- show param names for non-obvious literals
      parameterTypes             = { enabled = true },
      variableTypes              = { enabled = true },
      propertyDeclarationTypes   = { enabled = true },
      functionLikeReturnTypes    = { enabled = true },
      enumMemberValues           = { enabled = true },
    },
    preferences = {
      -- Exclude compiled dist/bundle files from auto-import suggestions
      autoImportFileExcludePatterns = {
        "**/node_modules/**/dist/**",
        "**/node_modules/**/build/**",
        "**/node_modules/**/out/**",
        "**/dist/**",
        "**/build/**",
        "**/out/**",
      },
    },
  },
  javascript = {
    updateImportsOnFileMove = { enabled = "always" },
    inlayHints = {
      parameterNames             = { enabled = "literals" },
      parameterTypes             = { enabled = true },
      variableTypes              = { enabled = true },
      propertyDeclarationTypes   = { enabled = true },
      functionLikeReturnTypes    = { enabled = true },
      enumMemberValues           = { enabled = true },
    },
    preferences = {
      -- Exclude compiled dist/bundle files from auto-import suggestions
      autoImportFileExcludePatterns = {
        "**/node_modules/**/dist/**",
        "**/node_modules/**/build/**",
        "**/node_modules/**/out/**",
        "**/dist/**",
        "**/build/**",
        "**/out/**",
      },
    },
  },
}

-- Custom attach handler for TypeScript/JavaScript specific keymaps
function M.on_attach(client, bufnr)
  local opts = { buffer = bufnr }

  -- 1. Organize Imports
  vim.keymap.set("n", "<leader>co", function()
    vim.lsp.buf.execute_command({
      command = "_typescript.organizeImports",
      arguments = { vim.api.nvim_buf_get_name(bufnr) },
    })
    utils.notify("imports_organized")
  end, vim.tbl_extend("force", opts, { desc = "Organize Imports (TS/JS)" }))

  -- 2. Add Missing Imports
  vim.keymap.set("n", "<leader>cm", function()
    vim.lsp.buf.execute_command({
      command = "_typescript.addMissingImports",
      arguments = { vim.api.nvim_buf_get_name(bufnr) },
    })
    utils.notify("imports_added")
  end, vim.tbl_extend("force", opts, { desc = "Add Missing Imports (TS/JS)" }))

  -- 3. Go to Source Definition (jumps to source code implementation, not .d.ts)
  vim.keymap.set("n", "gS", function()
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    client:request("workspace/executeCommand", {
      command = "_typescript.goToSourceDefinition",
      arguments = { params.textDocument.uri, params.position },
    }, function(err, result)
      if err then
        utils.notify("error_source_def", err)
        return
      end
      if result and result[1] then
        vim.lsp.util.show_document(result[1], "utf-8", { focus = true })
      else
        utils.notify("no_source_def")
      end
    end, bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Go to Source Definition" }))

  -- 4. Rename File (renames file physically on disk and updates its workspace imports automatically)
  vim.keymap.set("n", "<leader>cR", function()
    local source = vim.api.nvim_buf_get_name(bufnr)
    if source == "" then return end

    vim.ui.input({ prompt = "Rename file to: ", default = source }, function(target)
      if not target or target == "" or target == source then return end

      local source_uri = vim.uri_from_fname(source)
      local target_uri = vim.uri_from_fname(target)

      client:request("workspace/executeCommand", {
        command = "_typescript.renameFile",
        arguments = {
          {
            files = {
              { sourceUri = source_uri, targetUri = target_uri }
            }
          },
        },
      }, function(err, result)
          if err then
            utils.notify("error_file_rename", err)
            return
          end
          -- Apply workspace edits to update import paths
          if result then
            vim.lsp.util.apply_workspace_edit(result, "utf-8")
          end
          -- Ensure target directory exists before renaming
          local target_dir = vim.fn.fnamemodify(target, ":h")
          if vim.fn.isdirectory(target_dir) == 0 then
            vim.fn.mkdir(target_dir, "p")
          end

          -- Rename the physical file on disk
          local ok, err_msg = os.rename(source, target)
          if ok then
            vim.cmd("edit " .. vim.fn.fnameescape(target))
            local old_bufnr = vim.fn.bufnr(source)
            if old_bufnr ~= -1 then
              vim.cmd("bdelete! " .. old_bufnr)
            end
            utils.notify("file_renamed")
          else
            utils.notify("error_disk_rename", err_msg)
          end
        end, bufnr)
      end)
    end, vim.tbl_extend("force", opts, { desc = "Rename File & Update Imports" }))
end

return M
