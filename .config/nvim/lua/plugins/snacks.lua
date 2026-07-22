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
  local resume_state = require("snacks.picker.resume").state["files"]
  if vim.v.count == 0 and resume_state ~= nil then
    Snacks.picker.resume({ source = "files" })
  else
    local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:~"):gsub("/+$", "")
    Snacks.picker.files({ title = "Files (" .. cwd .. ")" })
  end
end, { desc = "Find Files (Resume; [count]=new search)" })

vim.keymap.set("n", "<leader>fF", function()
  ensure_unfixed_window()
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:~"):gsub("/+$", "")
  Snacks.picker.files({ title = "Files (" .. cwd .. ")" })
end, { desc = "Find Files (Fresh Search)" })

vim.keymap.set("n", "<leader>ft", function()
  ensure_unfixed_window()
  Snacks.picker.colorschemes()
end, { desc = "Select Colorscheme / Themes" })
local function open_git_branches_picker(opts)
  ensure_unfixed_window()
  opts = opts or {}
  Snacks.picker.git_branches(vim.tbl_deep_extend("force", {
    all = true,
    cmd_args = { "--sort=-committerdate" },
    title = "Git Checkout Branch (Local First)",
    transform = function(item)
      if item.text then
        local text = item.text
        local branch = item.branch or ""
        item.is_remote = not not (text:find("remotes/") or branch:find("^remotes/") or branch:find("^origin/"))
      end
      return item
    end,
    sort = function(a, b)
      local a_rem = a.is_remote and 1 or 0
      local b_rem = b.is_remote and 1 or 0
      if a_rem ~= b_rem then
        return a_rem < b_rem
      end
      return 0
    end,
    format = function(item, picker)
      local ret = {}
      if item.is_remote then
        table.insert(ret, { "[remote] ", "SnacksPickerLabel" })
      else
        table.insert(ret, { "[local]  ", "SnacksPickerLabel" })
      end
      vim.list_extend(ret, Snacks.picker.format.git_branch(item, picker))
      return ret
    end,
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
  local resume_state = require("snacks.picker.resume").state["grep"]

  if vim.v.count == 0 and resume_state ~= nil then
    Snacks.picker.resume({ source = "grep" })
    return
  end

  vim.ui.input({
    prompt = "  Grep include (glob, Esc=skip): ",
    default = _grep_last_include or "",
  }, function(include)
    if include == nil then
      if resume_state ~= nil then
        Snacks.picker.resume({ source = "grep" })
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
  Snacks.picker.grep()
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



-- Monkey-patch snacks.nvim picker resume to cache items in memory and pre-set cursor position & target immediately
-- so resuming is 100% instant without re-scanning disk or cursor top-to-bottom jump animation.
local resume_ok, picker_resume = pcall(require, "snacks.picker.resume")
if resume_ok and picker_resume then
  local original_add = picker_resume.add
  picker_resume.add = function(picker)
    original_add(picker)
    local source = picker.opts.source or "custom"
    if picker_resume.state[source] then
      local items = (picker.finder and picker.finder.items) or (picker.list and picker.list.items)
      if items and #items > 0 then
        picker_resume.state[source].items = items
      end
    end
  end

  picker_resume._resume = function(state)
    state.opts.pattern = state.filter.pattern
    state.opts.search = state.filter.search
    if state.items and #state.items > 0 then
      state.opts.finder = function()
        return state.items
      end
    end
    local ret = Snacks.picker.pick(state.opts)
    if state.cursor and ret and ret.list then
      ret.list.target = { cursor = state.cursor, top = state.topline or 1 }
      ret.list.cursor = state.cursor
      if state.topline then
        ret.list.top = state.topline
      end
      pcall(function() ret.list:view(state.cursor, state.topline) end)
    end
    ret.list:set_selected(state.selected)
    ret.list:update()
    ret.input:update()
    ret.matcher.task:on(
      "done",
      vim.schedule_wrap(function()
        if ret.closed then
          return
        end
        if state.cursor then
          ret.list:view(state.cursor, state.topline)
          ret.list.target = nil
        end
      end)
    )
    return ret
  end
end
