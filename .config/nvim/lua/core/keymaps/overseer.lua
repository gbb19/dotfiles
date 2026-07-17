-- Lazy load overseer on task runner keymaps
local function run_overseer_normal(cmd)
  return function()
    -- Normal mode: clear previous selection to prevent stale values
    vim.g.overseer_selected_text = nil
    -- Ensure we are in a normal window before splitting or toggling Overseer
    require("core.layout").jump_to_normal_window()
    require("plugins.overseer")
    vim.cmd(cmd)
  end
end

local function run_overseer_visual(cmd)
  return function()
    -- Visual mode: yank selection to register 'v', store it, and restore register
    local s_reg = vim.fn.getreg("v")
    local s_type = vim.fn.getregtype("v")
    
    -- Executing "vy in visual mode yanks the current selection
    vim.cmd('noau normal! "vy')
    vim.g.overseer_selected_text = vim.fn.getreg("v")
    
    vim.fn.setreg("v", s_reg, s_type)

    -- Force visual mode exit
    vim.cmd("normal! \27")

    -- Ensure we are in a normal window before splitting or toggling Overseer
    require("core.layout").jump_to_normal_window()
    require("plugins.overseer")
    vim.cmd(cmd)
  end
end

vim.keymap.set("n", "<leader>tr", run_overseer_normal("OverseerRun"),         { desc = "Run Task" })
vim.keymap.set("v", "<leader>tr", run_overseer_visual("OverseerRun"),         { desc = "Run Task (Visual)" })
vim.keymap.set("n", "<leader>to", run_overseer_normal("OverseerToggle"),      { desc = "Toggle Task List" })
vim.keymap.set("v", "<leader>to", run_overseer_visual("OverseerToggle"),      { desc = "Toggle Task List (Visual)" })
vim.keymap.set("n", "<leader>tc", run_overseer_normal("OverseerClose"),       { desc = "Close Task List" })
vim.keymap.set("v", "<leader>tc", run_overseer_visual("OverseerClose"),       { desc = "Close Task List (Visual)" })
vim.keymap.set("n", "<leader>ta", run_overseer_normal("OverseerTaskAction"), { desc = "Task Action" })
vim.keymap.set("v", "<leader>ta", run_overseer_visual("OverseerTaskAction"), { desc = "Task Action (Visual)" })



