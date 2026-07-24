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
local picker_resume = require("plugins.snacks.resume")

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
          -- Clear search query inside picker window
          ["<C-l>"] = { "clear_search", mode = { "i", "n" } },
        },
      },
    },
    actions = {
      clear_search = function(picker)
        picker.input:set("")
      end,
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

require("plugins.snacks.files").setup({
  ensure_unfixed_window = ensure_unfixed_window,
  picker_resume = picker_resume,
})

local _branch_preview_timer = nil

local function open_git_branches_picker(opts)
  ensure_unfixed_window()
  opts = opts or {}
  local git_branches = require("core.git.branches")
  Snacks.picker(vim.tbl_deep_extend("force", {
    source = "git_branches",
    title = "Git Branches",
    finder = function(picker_opts, ctx)
      local root = ctx:git_root()
      return ctx.filter:filter(git_branches.list(root))
    end,
    format = function(item, picker)
      local a = Snacks.picker.util.align
      local ret = {}
      if item.current then
        table.insert(ret, { a("* ", 2), "SnacksPickerGitBranchCurrent" })
      else
        table.insert(ret, { a("  ", 2) })
      end
      table.insert(ret, { item.branch, "SnacksPickerGitBranch" })

      if not item.is_remote then
        local status_parts = {}
        if item.ahead then
          table.insert(status_parts, { "↑" .. item.ahead, "SnacksPickerGitAhead" })
        end
        if item.behind then
          if #status_parts > 0 then
            table.insert(status_parts, { " " })
          end
          table.insert(status_parts, { "↓" .. item.behind, "SnacksPickerGitBehind" })
        end
        if item.gone then
          table.insert(status_parts, { "[gone]", "SnacksPickerGitGone" })
        end

        if #status_parts > 0 then
          table.insert(ret, { " " })
          vim.list_extend(ret, status_parts)
        end
      end

      return ret
    end,
    preview = function(ctx)
      if not ctx.item or not ctx.item.branch then
        return
      end
      ctx.preview:set_title("Branch: " .. ctx.item.branch)
      if _branch_preview_timer then
        pcall(vim.uv.timer_stop, _branch_preview_timer)
        _branch_preview_timer = nil
      end
      _branch_preview_timer = vim.defer_fn(function()
        if ctx.picker and not ctx.picker.closed and ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
          local cmd = { "git", "-c", "core.quotepath=false", "--no-pager", "log", "-n", "15", "--stat", ctx.item.branch }
          pcall(require("snacks.picker.preview").cmd, cmd, ctx, { ft = "git" })
        end
      end, 80)
    end,
  }, opts))
end

vim.keymap.set("n", "<leader>gc", function()
  open_git_branches_picker()
end, { desc = "Git Checkout Branch (Local First + MRU)" })

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

  picker_resume.open("grep", Snacks.picker.grep, {
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
  local has_resume_state = picker_resume.has("grep")
  local force_filter_prompts = _grep_reset_pending

  if vim.v.count == 0 and has_resume_state and not force_filter_prompts then
    picker_resume.resume("grep")
    return
  end

  vim.ui.input({
    prompt = "  Grep include (glob, Esc=skip): ",
    default = _grep_last_include or "",
  }, function(include)
    if include == nil then
      if has_resume_state and not force_filter_prompts then
        picker_resume.resume("grep")
      else
        open_grep(_grep_last_include or "", _grep_last_exclude or "", _grep_last_search)
      end
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
end, { desc = "Live Grep (Resume; [count]=edit filters)" })

vim.keymap.set("n", "<leader>fG", function()
  ensure_unfixed_window()
  reset_grep_filters()
  picker_resume.open("grep", Snacks.picker.grep)
end, { desc = "Live Grep (Fresh Search)" })

local function is_buffer_pinned(bufnr)
  local g_ok, groups = pcall(require, "bufferline.groups")
  if g_ok and groups and type(groups._is_pinned) == "function" then
    if groups._is_pinned({ id = bufnr }) then
      return true
    end
  end
  local pinned_g = vim.g.BufferlinePinnedBuffers
  if type(pinned_g) == "string" and pinned_g ~= "" then
    local path = vim.api.nvim_buf_get_name(bufnr)
    for _, p in ipairs(vim.split(pinned_g, ",")) do
      if p == path or p == tostring(bufnr) then
        return true
      end
    end
  end
  return false
end

vim.keymap.set("n", "<leader>fb", function()
  ensure_unfixed_window()
  Snacks.picker({
    source = "buffers",
    title = "Buffers",
    finder = function(opts, ctx)
      local current_buf = vim.api.nvim_get_current_buf()
      local alternate_buf = vim.fn.bufnr("#")
      local items = {}

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].filetype ~= "dbout" then
          local name = vim.api.nvim_buf_get_name(buf)
          if name == "" then
            name = "[Scratch]"
          end
          local info = (vim.fn.getbufinfo(buf)[1]) or {}
          local mark = vim.api.nvim_buf_get_mark(buf, '"')
          local flags = {
            buf == current_buf and "%" or (buf == alternate_buf and "#" or ""),
            info.hidden == 1 and "h" or (#(info.windows or {}) > 0) and "a" or "",
            vim.bo[buf].readonly and "=" or "",
            info.changed == 1 and "+" or "",
          }
          local pinned = is_buffer_pinned(buf)
          table.insert(items, {
            buf = buf,
            name = name,
            file = name,
            is_pinned = pinned,
            info = info,
            lastused = info.lastused or 0,
            flags = table.concat(flags),
            buftype = vim.bo[buf].buftype,
            filetype = vim.bo[buf].filetype,
            pos = mark[1] ~= 0 and mark or { info.lnum or 1, 0 },
          })
          items[#items].text = Snacks.picker.util.text(items[#items], { "buf", "name", "filetype", "buftype" })
        end
      end

      -- Sort: Pinned buffers FIRST (sorted by MRU lastused), then Regular buffers (sorted by MRU lastused)
      table.sort(items, function(a, b)
        local a_pin = a.is_pinned and 1 or 0
        local b_pin = b.is_pinned and 1 or 0
        if a_pin ~= b_pin then
          return a_pin > b_pin
        end
        return (a.lastused or 0) > (b.lastused or 0)
      end)

      return ctx.filter:filter(items)
    end,
    format = function(item, picker)
      local ret = {}
      if item.is_pinned then
        table.insert(ret, { "[P] ", "SnacksPickerLabel" })
      else
        table.insert(ret, { "    ", "SnacksPickerLabel" })
      end
      vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
      return ret
    end,
    win = {
      input = {
        keys = {
          ["<A-1>"] = { function(p) p.list:view(1) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-2>"] = { function(p) p.list:view(2) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-3>"] = { function(p) p.list:view(3) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-4>"] = { function(p) p.list:view(4) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-5>"] = { function(p) p.list:view(5) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-6>"] = { function(p) p.list:view(6) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-7>"] = { function(p) p.list:view(7) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-8>"] = { function(p) p.list:view(8) p:action("confirm") end, mode = { "i", "n" } },
          ["<A-9>"] = { function(p) p.list:view(9) p:action("confirm") end, mode = { "i", "n" } },
          ["1"] = { function(p) p.list:view(1) p:action("confirm") end, mode = "n" },
          ["2"] = { function(p) p.list:view(2) p:action("confirm") end, mode = "n" },
          ["3"] = { function(p) p.list:view(3) p:action("confirm") end, mode = "n" },
          ["4"] = { function(p) p.list:view(4) p:action("confirm") end, mode = "n" },
          ["5"] = { function(p) p.list:view(5) p:action("confirm") end, mode = "n" },
          ["6"] = { function(p) p.list:view(6) p:action("confirm") end, mode = "n" },
          ["7"] = { function(p) p.list:view(7) p:action("confirm") end, mode = "n" },
          ["8"] = { function(p) p.list:view(8) p:action("confirm") end, mode = "n" },
          ["9"] = { function(p) p.list:view(9) p:action("confirm") end, mode = "n" },
        },
      },
    },
  })
end, { desc = "Find Buffers (Pinned First + MRU)" })
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
