-- Snacks entry point: package registration, setup, and domain orchestration.

vim.pack.add({ "https://github.com/folke/snacks.nvim" })
local cached_startup_time = nil
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function()
  if _G.startup_start_time then cached_startup_time = (vim.uv.hrtime() - _G.startup_start_time) / 1e6 end
end })

local ok, snacks = pcall(require, "snacks")
if not ok then
  require("core.utils").notify("config_snacks_failed", tostring(snacks), { title = "Neovim config" })
  return
end
local picker_resume = require("plugins.snacks.resume")
snacks.setup({
  bigfile = { enabled = true },
  dashboard = {
    enabled = true,
    preset = { keys = {
      { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
      { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('recent')" },
      { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
      { icon = " ", key = "s", desc = "Restore Session", action = ":AutoSession restore" },
      { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
      { icon = " ", key = "q", desc = "Quit", action = ":qa" },
    } },
    sections = {
      { section = "header" },
      { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1 },
      { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
      { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
      function()
        local version = vim.version()
        local stats = { string.format("⚡ Neovim v%d.%d.%d", version.major, version.minor, version.patch) }
        local duration = cached_startup_time
        if not duration and _G.startup_start_time then duration = (vim.uv.hrtime() - _G.startup_start_time) / 1e6 end
        if duration then table.insert(stats, string.format(" loaded in %.2fms", duration)) end
        return { align = "center", text = { { table.concat(stats), hl = "SnacksDashboardDesc" } } }
      end,
    },
  },
  input = { enabled = true },
  picker = {
    enabled = true, ui_select = true,
    win = { input = { keys = {
      ["<C-d>"] = { "preview_scroll_down", mode = { "i", "n" } },
      ["<C-u>"] = { "preview_scroll_up", mode = { "i", "n" } },
      ["<M-h>"] = { "preview_scroll_left", mode = { "i", "n" } },
      ["<M-l>"] = { "preview_scroll_right", mode = { "i", "n" } },
      ["<C-l>"] = { "clear_search", mode = { "i", "n" } },
    } } },
    actions = { clear_search = function(picker) picker.input:set("") end },
  },
  notifier = { enabled = true },
  indent = { enabled = true, char = "│", animate = { enabled = false }, scope = { enabled = true } },
  words = { enabled = true },
})

local function ensure_unfixed_window()
  if vim.wo.winfixbuf then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and not vim.wo[win].winfixbuf then
        vim.api.nvim_set_current_win(win)
        return win
      end
    end
    vim.wo.winfixbuf = false
  end
  return vim.api.nvim_get_current_win()
end

require("plugins.snacks.keymaps").setup({ ensure_unfixed_window = ensure_unfixed_window, picker_resume = picker_resume })
require("plugins.snacks.buffers").setup(ensure_unfixed_window)

return {}
