-- lua/core/keymaps/dap.lua
-- Keyboard shortcuts for debugging (DAP)
-- Uses Leader combos instead of standard F-keys

-- Helper to lazy load DAP module and its UI on key press
local function load_dap(fn_name, ...)
  local args = { ... }
  return function()
    require("plugins.dap")
    local dap = require("dap")
    if dap[fn_name] then
      dap[fn_name](unpack(args))
    end
  end
end

local function load_dapui(fn_name, ...)
  local args = { ... }
  return function()
    require("plugins.dap")
    local dapui = require("dapui")
    if dapui[fn_name] then
      dapui[fn_name](unpack(args))
    end
  end
end

-- Keymaps prefix with <leader>d (Debug)
vim.keymap.set("n", "<leader>db", load_dap("toggle_breakpoint"), { desc = "DAP: Toggle Breakpoint" })
vim.keymap.set("n", "<leader>dc", load_dap("continue"),          { desc = "DAP: Start/Continue" })
vim.keymap.set("n", "<leader>di", load_dap("step_into"),         { desc = "DAP: Step Into" })
vim.keymap.set("n", "<leader>do", load_dap("step_over"),         { desc = "DAP: Step Over" })
vim.keymap.set("n", "<leader>dt", load_dap("step_out"),          { desc = "DAP: Step Out" })
vim.keymap.set("n", "<leader>dr", load_dap("restart"),           { desc = "DAP: Restart Session" })
vim.keymap.set("n", "<leader>dq", load_dap("terminate"),         { desc = "DAP: Terminate Session" })
vim.keymap.set("n", "<leader>dC", load_dap("clear_breakpoints"),  { desc = "DAP: Clear All Breakpoints" })
vim.keymap.set("n", "<leader>dl", function()
  -- Check if there are any active breakpoints set to prevent opening empty picker
  local has_breakpoints = false
  if package.loaded["dap"] then
    local breakpoints = require("dap.breakpoints").get()
    for _, buf_breakpoints in pairs(breakpoints) do
      if #buf_breakpoints > 0 then
        has_breakpoints = true
        break
      end
    end
  end

  if not has_breakpoints then
    require("core.utils").notify("dap_no_breakpoints", nil, { title = "DAP" })
    return
  end

  -- Populate Neovim's quickfix list with breakpoints first
  require("plugins.dap")
  require("dap").list_breakpoints()

  -- Open the populated quickfix list using the beautiful Snacks picker
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker and snacks.picker.qflist then
    snacks.picker.qflist({ title = "DAP Breakpoints" })
  else
    -- Fallback to default Neovim quickfix window if snacks is not available
    vim.cmd("copen")
  end
end, { desc = "DAP: List All Breakpoints (Fuzzy)" })
vim.keymap.set("n", "<leader>du", load_dapui("toggle"),          { desc = "DAP UI: Toggle Panel" })
vim.keymap.set("n", "<leader>de", load_dapui("eval"),            { desc = "DAP UI: Evaluate under Cursor" })
vim.keymap.set("n", "<leader>dvs", load_dapui("float_element", "scopes", { enter = true }), { desc = "DAP UI: View Scopes (Float)" })
vim.keymap.set("n", "<leader>dvt", load_dapui("float_element", "stacks", { enter = true }), { desc = "DAP UI: View Stacks (Float)" })
