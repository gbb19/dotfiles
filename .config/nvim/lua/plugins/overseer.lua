-- Add overseer.nvim using built-in vim.pack
vim.pack.add({ "https://github.com/stevearc/overseer.nvim" })



-- Configure overseer
local ok, overseer = pcall(require, "overseer")
if ok then
  overseer.setup({
    -- Scan only vscode tasks and general shell scripts, excluding heavy autodetected npm scripts
    templates = { "vscode", "shell" },
    -- Explicitly disable auto-detected templates to prevent clutter
    disable_template_modules = { "overseer.template.npm", "overseer.template.deno" },
    task_list = {
      direction = "bottom",
      min_height = 14,
      max_height = 18,
      bindings = {
        ["?"] = "ShowBindings",
        ["g?"] = "ShowBindings",
        ["<CR>"] = "RunAction",
        ["<C-e>"] = "EditTask",
        ["o"] = "Open",
        ["<C-v>"] = "OpenVsplit",
        ["<C-s>"] = "OpenSplit",
        ["<C-f>"] = "OpenFloat",
        ["p"] = "TogglePreview",
        ["<C-l>"] = "IncreaseDetail",
        ["<C-h>"] = "DecreaseDetail",
        ["L"] = "IncreaseAllDetail",
        ["H"] = "DecreaseAllDetail",
        ["["] = "DecreaseWidth",
        ["]"] = "IncreaseWidth",
        ["{"] = "DecreaseHeight",
        ["}"] = "IncreaseHeight",
        ["q"] = "Close",
      },
    },
  })

  -- Override Overseer's VS Code variable resolver for selectedText to prevent context loss
  local ok_vars, vscode_vars = pcall(require, "overseer.vscode.variables")
  if ok_vars then
    vscode_vars.get_selected_text = function()
      return vim.g.overseer_selected_text or ""
    end
  end
end

-- Keymaps are registered as lazy-loaders in lua/core/keymaps.lua
-- and replaced by direct commands once this module is loaded.

