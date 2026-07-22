-- Add snacks.nvim using built-in vim.pack
vim.pack.add({ "https://github.com/folke/snacks.nvim" })

-- Cache Neovim startup time once when VimEnter fires to prevent reload timers from counting up
local cached_startup_time = nil
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if _G.startup_start_time then
      cached_startup_time = (vim.uv.hrtime() - _G.startup_start_time) / 1e6
    end
  end,
})

-- Configure snacks.nvim
local ok, snacks = pcall(require, "snacks")
if not ok then return end

snacks.setup({
  bigfile = { enabled = true },
  dashboard = {
    enabled = true,
    preset = {
      keys = {
        { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
        { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('recent')" },
        { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
        { icon = " ", key = "s", desc = "Restore Session", action = ":AutoSession restore" },
        {
          icon = " ",
          key = "c",
          desc = "Config",
          action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
        },
        { icon = " ", key = "q", desc = "Quit", action = ":qa" },
      },
    },
    sections = {
      { section = "header" },
      { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1 },
      { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
      { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
      function()
        local version = vim.version()
        local ver_str = string.format("v%d.%d.%d", version.major, version.minor, version.patch)
        local stats = { "⚡ Neovim " .. ver_str }
        local duration = cached_startup_time
        if not duration and _G.startup_start_time then
          -- Fallback if VimEnter hasn't fired yet during the very first rendering step
          duration = (vim.uv.hrtime() - _G.startup_start_time) / 1e6
        end
        if duration then
          table.insert(stats, string.format(" loaded in %.2fms", duration))
        end
        return {
          align = "center",
          text = {
            { table.concat(stats), hl = "SnacksDashboardDesc" },
          },
        }
      end,
    },
  },
  input = {
    enabled = true,
  },
  picker = {
    enabled = true,
    ui_select = true, -- binds vim.ui.select to snacks.picker
    win = {
      input = {
        keys = {
          -- Remap Ctrl-d and Ctrl-u to scroll the preview pane and avoid terminal/tmux Ctrl-b conflicts
          ["<C-d>"] = { "preview_scroll_down", mode = { "i", "n" } },
          ["<C-u>"] = { "preview_scroll_up", mode = { "i", "n" } },
          -- Map Ctrl-Left and Ctrl-Right to scroll the preview pane horizontally (left and right) in all modes
          ["<M-h>"] = { "preview_scroll_left", mode = { "i", "n" } },
          ["<M-l>"] = { "preview_scroll_right", mode = { "i", "n" } },
        },
      },
      preview = {
        wo = {
          wrap = false, -- Disable line wrapping in the preview pane so horizontal scrolling actually works
        },
      },
    },
  },
  notifier = {
    enabled = true,
  },
  indent = {
    enabled = true,
    char = "│", -- thin solid vertical line (supported natively by standard coding fonts)
    animate = { enabled = false }, -- disable animations to keep it snappy
    scope = {
      enabled = true, -- Re-enable active scope highlighting
    },
  },
  words = {
    enabled = true,
  },
})

-- Global monkey-patch for Snacks picker file previewer to always show relative path & line number in preview title
local preview_ok, preview = pcall(function() return Snacks.picker.preview end)
if preview_ok and preview then
  local original_preview_file = preview.file
  preview.file = function(ctx)
    local ok = original_preview_file(ctx)
    if ok ~= false then
      local path = ctx.item and Snacks.picker.util.path(ctx.item)
      if path and type(path) == "string" and path ~= "" and not path:find("^%w+://") then
        local title = vim.fn.fnamemodify(path, ":.")
        if ctx.item.pos and ctx.item.pos[1] then
          title = title .. ":" .. ctx.item.pos[1]
        end
        if ctx.preview and ctx.preview.set_title then
          ctx.preview:set_title(title)
        end
      end
    end
    return ok
  end
end

-- Automatically shift focus to an un-fixed window if currently in a winfixbuf window before running picker
local function ensure_unfixed_window()
  if vim.wo.winfixbuf then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and not vim.wo[win].winfixbuf then
        vim.api.nvim_set_current_win(win)
        return win
      end
    end
    vim.wo.winfixbuf = false
    return vim.api.nvim_get_current_win()
  end
  return vim.api.nvim_get_current_win()
end

-- Global hook into Snacks.picker to ensure any picker launch switches to an unfixed window
pcall(function()
  local picker = require("snacks.picker")
  if picker then
    local orig_open = picker.open
    if type(orig_open) == "function" then
      picker.open = function(opts)
        ensure_unfixed_window()
        return orig_open(opts)
      end
    end
    if picker.Picker and type(picker.Picker.new) == "function" then
      local orig_new = picker.Picker.new
      picker.Picker.new = function(opts)
        local valid_win = ensure_unfixed_window()
        local instance = orig_new(opts)
        if instance and instance.main_win and vim.wo[instance.main_win].winfixbuf then
          instance.main_win = valid_win
        end
        return instance
      end
    end
  end
end)

-- Global search keymaps using Snacks picker
vim.keymap.set("n", "<leader>ff", function()
  ensure_unfixed_window()
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:~"):gsub("/+$", "")
  Snacks.picker.files({ title = "Files (" .. cwd .. ")" })
end, { desc = "Find Files" })
vim.keymap.set("n", "<leader>ft", function()
  ensure_unfixed_window()
  Snacks.picker.colorschemes()
end, { desc = "Select Colorscheme / Themes" })
vim.keymap.set("n", "<leader>gc", function()
  Snacks.picker.git_branches({
    all = true,
    cmd_args = { "--sort=-committerdate" },
    previewers = {
      diff = {
        style = "syntax",
      },
    },
    preview = function(ctx)
      if ctx.item and ctx.item.branch then
        ctx.preview:set_title("Branch: " .. ctx.item.branch)
      end
      return require("snacks.picker.preview").git_log(ctx)
    end,
  })
end, { desc = "Git Checkout Branch (All, sorted by date)" })

local _grep_last_include = nil
local _grep_last_exclude = nil
local _grep_last_search = ""
local _grep_reset_pending = false

local function build_grep_args(include, exclude)
  local args = {}
  for _, pat in ipairs(vim.split(include or "", "[,%s]+", { trimempty = true })) do
    vim.list_extend(args, { "--glob", pat })
  end
  for _, pat in ipairs(vim.split(exclude or "", "[,%s]+", { trimempty = true })) do
    vim.list_extend(args, { "--glob", "!" .. pat })
  end
  return args
end

-- Full reset: next <leader>fg (no count) will go through include/exclude prompts again
local function reset_grep_filters()
  _grep_last_include = nil
  _grep_last_exclude = nil
  _grep_last_search = ""
end

local function open_grep(include, exclude, search)
  ensure_unfixed_window()
  local args = build_grep_args(include, exclude)
  _grep_reset_pending = false

  Snacks.picker.grep({
    args = #args > 0 and args or nil,
    search = search,
    win = {
      input = {
        keys = {
          ["<C-c>"] = { "grep_force_reset", mode = { "i", "n" } },
        },
      },
    },
    actions = {
      grep_force_reset = function(picker)
        _grep_reset_pending = true
        picker:close()
      end,
    },
    on_close = function(picker)
      local q = picker.input.filter.search

      if _grep_reset_pending or not q or vim.trim(q) == "" then
        reset_grep_filters()
        return
      end

      _grep_last_search = q
    end,
  })
end

vim.keymap.set("n", "<leader>fg", function()
  ensure_unfixed_window()
  local first_time = _grep_last_include == nil

  if vim.v.count == 0 and not first_time then
    open_grep(_grep_last_include, _grep_last_exclude, _grep_last_search)
    return
  end

  vim.ui.input({
    prompt = "  Grep include (glob, Esc=skip): ",
    default = _grep_last_include or "",
  }, function(include)
    if include == nil then
      open_grep(_grep_last_include or "", _grep_last_exclude or "", _grep_last_search)
      return
    end
    _grep_last_include = include

    vim.ui.input({
      prompt = "  Grep exclude (glob, Esc=skip): ",
      default = _grep_last_exclude or "",
    }, function(exclude)
      exclude = exclude or (_grep_last_exclude or "")
      _grep_last_exclude = exclude
      open_grep(_grep_last_include, exclude, _grep_last_search)
    end)
  end)
end, { desc = "Live Grep (resume; [count]=edit filters; C-c/empty in picker=reset)" })

vim.keymap.set("n", "<leader>fb", function()
  ensure_unfixed_window()
  Snacks.picker.buffers()
end, { desc = "Find Buffers" })
vim.keymap.set("n", "<leader>fr", function()
  ensure_unfixed_window()
  Snacks.picker.recent()
end, { desc = "Recent Files" })
vim.keymap.set("n", "<leader>fh", function()
  ensure_unfixed_window()
  Snacks.picker.help()
end, { desc = "Help Tags" })

-- Diagnostic search using Snacks picker
vim.keymap.set("n", "<leader>cd", function()
  ensure_unfixed_window()
  Snacks.picker.diagnostics({ filter = { bufnr = 0 } })
end, { desc = "Search Diagnostics (Current File)" })
vim.keymap.set("n", "<leader>cD", function()
  ensure_unfixed_window()
  Snacks.picker.diagnostics()
end, { desc = "Search Diagnostics (Workspace)" })

-- Monkey-patch snacks.nvim picker async yielder to prevent yielding across C-call boundary in Neovim 0.12+
local async_ok, async = pcall(require, "snacks.picker.util.async")
if async_ok then
  local original_yielder = async.yielder
  async.yielder = function(ms)
    local is_yieldable = true
    if type(coroutine.isyieldable) == "function" then
      is_yieldable = coroutine.isyieldable()
    end
    if not async.running() or not is_yieldable then
      return function() end
    end
    return original_yielder(ms)
  end
end

-- Monkey-patch snacks.nvim picker path truncation to remove the vertical ellipsis symbol (⋮)
local util_ok, picker_util = pcall(require, "snacks.picker.util")
if util_ok and picker_util then
  local original_truncpath = picker_util.truncpath
  picker_util.truncpath = function(path, len, opts)
    local res = original_truncpath(path, len, opts)
    if type(res) == "string" then
      return (res:gsub("^⋮", ""))
    end
    return res
  end
end
