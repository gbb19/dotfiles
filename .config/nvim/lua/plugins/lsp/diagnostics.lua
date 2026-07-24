local M = {}

function M.setup(utils)
  vim.keymap.set("n", "[d", function()
    vim.diagnostic.jump({ count = -1 })
  end, { desc = "Go to Previous Diagnostic" })

  vim.keymap.set("n", "]d", function()
    vim.diagnostic.jump({ count = 1 })
  end, { desc = "Go to Next Diagnostic" })

  vim.keymap.set("n", "[e", function()
    vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR })
  end, { desc = "Go to Previous Error" })

  vim.keymap.set("n", "]e", function()
    vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR })
  end, { desc = "Go to Next Error" })

  vim.keymap.set("n", "<leader>cy", function()
    local line_diags = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
    if #line_diags == 0 then
      utils.notify("diagnostic_missing")
      return
    end
    local messages = {}
    for _, diag in ipairs(line_diags) do
      messages[#messages + 1] = string.format("[%s] %s", diag.source or "LSP", diag.message)
    end
    vim.fn.setreg("+", table.concat(messages, "\n"))
    utils.notify("diagnostic_copied", line_diags[1].message)
  end, { desc = "Copy / Yank Diagnostic Message" })
end

return M
