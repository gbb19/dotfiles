-- Add auto-session using built-in vim.pack
vim.pack.add({ "https://github.com/rmagatti/auto-session" })

local ok, auto_session = pcall(require, "auto-session")
if ok then
  auto_session.setup({
    log_level = "error",
    enabled = true,
    auto_save = true,
    auto_restore = false, -- Disable auto-restore so Dashboard/Splash screen shows first
    -- Save sessions in Neovim's standard data directory (keeps project clean)
    root_dir = vim.fn.stdpath("data") .. "/sessions/",
    auto_create = vim.fn.argc() == 0, -- Don't create/overwrite session when opening specific files
    -- Disable git branch specific sessions (keep it simple per-directory)
    git_use_branch_name = false,
    -- Do not save sessions for Git commits, diffs, file explorers, or special buffers
    bypass_save_filetypes = {
      "gitcommit",
      "gitrebase",
      "diffview",
      "DiffviewFiles",
      "DiffviewFileHistory",
      "qf",
      "snacks_picker",
      "snacks_input",
      "oil",
      "overseer_list",
      "dbout",
    },
    pre_save_cmds = {
      function()
        -- Wipe out all dbout buffers before saving to prevent saving temp files
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "dbout" then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
      end,
    },
  })

  -- Keymaps for manual session management
  vim.keymap.set("n", "<leader>sr", "<cmd>AutoSession restore<cr>", { desc = "Restore Session (Current Directory)" })
  vim.keymap.set("n", "<leader>ss", "<cmd>AutoSession search<cr>", { desc = "Search / Load Session" })
end


